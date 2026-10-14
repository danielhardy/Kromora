import AppKit
import CoreImage
import Foundation
import Observation
import QuartzCore
import SwiftUI
import XCTest

@testable import KromoraKit

/// KRMA-1002: window-independent breakdown of warm Library ⇄ Edit navigation.
///
/// Mounts the shipping `ContentView` in an `NSHostingView` that is never attached to an
/// `NSWindow`, drives the same `selectCollectionImage` / `navigate(to:)` entry points as the
/// display capture, and separates state publication, view mounting plus layout, and frame
/// hydration. Drawable presentation needs a window and a compositor, so it is deliberately not
/// measured here; it is the remainder between these numbers and the supervised capture in
/// `docs/TESTING.md`. Uses the exact stored frame so the warm Edit path admits zero renders.
///
/// Opt in with `KROMORA_WARM_NAVIGATION_PROFILE=1` and run in Release. Optional lane only
/// (`scripts/ci-tests.sh optional`); it never runs `scripts/run-kromora-capture.sh`.
///
/// - `KROMORA_WARM_NAVIGATION_RAW` chooses the source (default `realworldtest/DSC01019.ARW`).
/// - `KROMORA_WARM_NAVIGATION_ITERATIONS` is the sample count (5...100, default 30).
@MainActor
final class WarmNavigationProfileBenchmark: TempDirectoryTestCase {
    private static let gridCellCount = 30

    private struct Sample {
        var selectSyncMS = 0.0
        var firstLayoutMS = 0.0
        var layoutTotalMS = 0.0
        var hydrationMS = 0.0
        var settledLayoutMS = 0.0
        var renderAdmissions = 0
        var bodyEvaluations = 0
        var documentInvalidations = 0
    }

    func testProfileWarmNavigation() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["KROMORA_WARM_NAVIGATION_PROFILE"] != nil,
            "set KROMORA_WARM_NAVIGATION_PROFILE=1 (Release, optional lane)")
        let rawURL = URL(
            fileURLWithPath: environment["KROMORA_WARM_NAVIGATION_RAW"]
                ?? "realworldtest/DSC01019.ARW",
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw XCTSkip("RAW source is missing: \(rawURL.path)")
        }
        let iterations = min(
            100, max(5, Int(environment["KROMORA_WARM_NAVIGATION_ITERATIONS"] ?? "") ?? 30))
        let dimensions = try XCTUnwrap(Fixtures.storedSize(of: rawURL))

        let jpegs = try (0..<(Self.gridCellCount - 1)).map { index in
            try Fixtures.writeJPEG(
                width: 160 + index, height: 120, orientation: 1,
                named: String(format: "grid-%02d.jpg", index), in: tempDirectory)
        }
        let rawCopy = tempDirectory.appendingPathComponent(rawURL.lastPathComponent)
        try FileManager.default.copyItem(at: rawURL, to: rawCopy)
        let model = makeAppViewModel(
            engine: RenderEngine(),
            libraryFolderURL: tempDirectory.appendingPathComponent("managed-library"),
            previewFrameStoreDirectory: tempDirectory.appendingPathComponent("last-known-frames"))
        let summary = await model.openImagesAndWait(urls: jpegs + [rawCopy])
        guard let summary, summary.imported + summary.duplicates == Self.gridCellCount else {
            throw XCTSkip("fixtures could not be imported")
        }

        // No NSWindow: a hosting view that is laid out by hand at the capture viewport size.
        let viewport = NSRect(x: 0, y: 0, width: 1440, height: 897)
        let hosting = NSHostingView(rootView: ContentView(viewModel: model))
        hosting.frame = viewport
        func layout() -> Double {
            let start = CACurrentMediaTime()
            hosting.layoutSubtreeIfNeeded()
            return (CACurrentMediaTime() - start) * 1_000
        }

        // Without a window nothing is composited, so Metal reports presentedTime == 0; confirm
        // with the handler clock exactly as the display capture does.
        model.previewSurface.zeroPresentedTimeFallback = { LiveEditTelemetryClock.now }
        XCTAssertTrue(model.navigate(to: .grid))
        try await waitUntil("grid hydrated") {
            _ = layout()
            let ids = model.collection.visibleEditedThumbnailAssetIDs
            return !ids.isEmpty
                && ids.allSatisfy { id in
                    model.collection.items.first(where: { $0.id == id })?.thumbnail != nil
                }
        }
        let rawIndex = try XCTUnwrap(
            model.collection.items.firstIndex {
                $0.url?.lastPathComponent == rawCopy.lastPathComponent
            })

        // Cold visit once, then store the exact frame so every sample is a zero-render warm open.
        model.selectCollectionImage(at: rawIndex)
        try await waitUntil("first Edit visit") {
            _ = layout()
            return model.previewSurface.image != nil
                && model.previewRenderAdmissionCountForDiagnostics >= 1
        } diagnostics: {
            "mode=\(model.navigation.mode) state=\(model.previewState) image=\(model.previewSurface.image != nil) status=\(model.statusMessage) renders=\(model.previewRenderAdmissionCountForDiagnostics) session=\(String(describing: model.presentationSessionForDiagnostics))"
        }
        try await Task.sleep(for: .milliseconds(300))
        try await storeExactWarmFrame(model: model)

        let invalidations = InvalidationCounter(model: model)
        // The first few opens after the frame is stored may still admit a render while the
        // store read and caches settle; report them instead of folding them into the samples.
        var warmUpRenders = 0
        for _ in 0..<5 {
            _ = try await navigateToGrid(model, layout: layout, invalidations: invalidations)
            warmUpRenders +=
                try await selectRAW(
                    model, index: rawIndex, layout: layout, invalidations: invalidations
                ).renderAdmissions
        }
        print("WARM_NAVIGATION_PROFILE warm-up opens=5 renderAdmissions=\(warmUpRenders)")
        var edit: [Sample] = []
        var grid: [Sample] = []
        for _ in 0..<iterations {
            grid.append(try await navigateToGrid(model, layout: layout, invalidations: invalidations))
            edit.append(
                try await selectRAW(
                    model, index: rawIndex, layout: layout, invalidations: invalidations))
        }
        invalidations.stop()

        let machine = Self.sysctlString("machdep.cpu.brand_string")
        print(
            "WARM_NAVIGATION_PROFILE context machine=\(machine) "
                + "memoryGB=\(ProcessInfo.processInfo.physicalMemory >> 30) "
                + "os=\(ProcessInfo.processInfo.operatingSystemVersionString) "
                + "commit=\(Self.gitCommit()) source=\(rawURL.lastPathComponent) "
                + "\(Int(dimensions.width))x\(Int(dimensions.height)) "
                + "viewport=\(Int(viewport.width))x\(Int(viewport.height)) "
                + "samples=\(iterations) window=none")
        report("library-to-edit", edit)
        report("edit-to-library", grid)
        // Render admissions are reported, not asserted: with no window the presentation session
        // never confirms, so the coordinator can retry a render the display path would not.
        XCTAssertEqual(edit.count, iterations)
    }

    // MARK: - Transitions

    private func selectRAW(
        _ model: AppViewModel, index: Int, layout: () -> Double,
        invalidations: InvalidationCounter
    ) async throws -> Sample {
        var sample = Sample()
        let rendersBefore = model.previewRenderAdmissionCountForDiagnostics
        let bodiesBefore = bodyEvaluations()
        let invalidationsBefore = invalidations.documentCount
        let start = CACurrentMediaTime()
        model.selectCollectionImage(at: index)
        sample.selectSyncMS = (CACurrentMediaTime() - start) * 1_000
        let unmounts = RenderDiagnostics.snapshot.gridUnmounts
        sample.firstLayoutMS = layout()
        sample.layoutTotalMS = sample.firstLayoutMS
        var hydrated = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if !hydrated, model.previewSurface.image != nil {
                hydrated = true
                sample.hydrationMS = (CACurrentMediaTime() - start) * 1_000
            }
            if hydrated,
                RenderDiagnostics.snapshot.gridUnmounts > unmounts
            { break }
            try await Task.sleep(for: .milliseconds(1))
            sample.layoutTotalMS += layout()
        }
        guard hydrated else { throw XCTSkip("Edit never hydrated a frame") }
        sample.settledLayoutMS = layout()
        sample.renderAdmissions = model.previewRenderAdmissionCountForDiagnostics - rendersBefore
        sample.bodyEvaluations = bodyEvaluations() - bodiesBefore
        sample.documentInvalidations = invalidations.documentCount - invalidationsBefore
        return sample
    }

    private func navigateToGrid(
        _ model: AppViewModel, layout: () -> Double, invalidations: InvalidationCounter
    ) async throws -> Sample {
        var sample = Sample()
        let bodiesBefore = bodyEvaluations()
        let invalidationsBefore = invalidations.documentCount
        let mounts = RenderDiagnostics.snapshot.gridMounts
        let start = CACurrentMediaTime()
        XCTAssertTrue(model.navigate(to: .grid))
        sample.selectSyncMS = (CACurrentMediaTime() - start) * 1_000
        sample.firstLayoutMS = layout()
        sample.layoutTotalMS = sample.firstLayoutMS
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let ids = model.collection.visibleEditedThumbnailAssetIDs
            if RenderDiagnostics.snapshot.gridMounts > mounts, !ids.isEmpty,
                ids.allSatisfy({ id in
                    model.collection.items.first(where: { $0.id == id })?.thumbnail != nil
                })
            {
                sample.hydrationMS = (CACurrentMediaTime() - start) * 1_000
                sample.bodyEvaluations = bodyEvaluations() - bodiesBefore
                sample.documentInvalidations = invalidations.documentCount - invalidationsBefore
                return sample
            }
            try await Task.sleep(for: .milliseconds(1))
            sample.layoutTotalMS += layout()
        }
        throw XCTSkip("grid never re-mounted with hydrated cells")
    }

    // MARK: - Reporting

    private func report(_ name: String, _ samples: [Sample]) {
        func line(_ label: String, _ values: [Double]) {
            print(
                String(
                    format: "WARM_NAVIGATION_PROFILE %@ %@ p50=%.2f p95=%.2f max=%.2f ms n=%d",
                    name, label, percentile(values, 0.5), percentile(values, 0.95),
                    values.max() ?? 0, values.count))
        }
        line("statePublication(selectSync)", samples.map(\.selectSyncMS))
        line("mountAndLayout(firstPass)", samples.map(\.firstLayoutMS))
        line("layoutAllPasses", samples.map(\.layoutTotalMS))
        line("hydrationFromSelection", samples.map(\.hydrationMS))
        line("settledLayoutPass", samples.map(\.settledLayoutMS))
        print(
            "WARM_NAVIGATION_PROFILE \(name) counts renderAdmissions="
                + "\(samples.reduce(0) { $0 + $1.renderAdmissions }) bodyEvaluationsPerSample="
                + "\(Double(samples.reduce(0) { $0 + $1.bodyEvaluations }) / Double(samples.count)) "
                + "documentInvalidationsPerSample="
                + "\(Double(samples.reduce(0) { $0 + $1.documentInvalidations }) / Double(samples.count))"
        )
    }

    private func bodyEvaluations() -> Int {
        let snapshot = RenderDiagnostics.snapshot
        return snapshot.contentViewBodyEvaluations + snapshot.inspectorBodyEvaluations
            + snapshot.gridBodyEvaluations + snapshot.toolbarBodyEvaluations
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        let rank = Int((percentile * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    private func waitUntil(
        _ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool,
        diagnostics: () -> String = { "" }
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw XCTSkip("timed out waiting for \(what) \(diagnostics())")
    }

    private func storeExactWarmFrame(model: AppViewModel) async throws {
        let frameStore = LatestPreviewFrameStore(
            directory: tempDirectory.appendingPathComponent("last-known-frames"))
        let source = try XCTUnwrap(model.admissionImageSource)
        let displayedImage = try XCTUnwrap(model.previewSurface.image)
        let request = RenderRequest(source: source, document: model.document, quality: .preview)
        guard
            let raster = await RenderEngine.shared.makeCanonicalPreviewRaster(
                displayedImage, space: request.space,
                longEdge: LatestPreviewFrameStore.canonicalLongEdge)
        else { throw XCTSkip("displayed frame could not be encoded") }
        let identity = source.portableIdentity
        await frameStore.enqueueWrite(
            PresentationFrame(
                metadata: PresentationFrameMetadata(
                    identity: identity, kind: .preview2048,
                    signature: FrameSignature(
                        source: identity, editHash: request.document.editHash,
                        look: request.lookSignature, workingSpace: request.space,
                        pixelEpoch: RenderPipeline.pixelEpoch),
                    geometry: PresentedGeometry(
                        crop: request.document.crop, rotation: request.document.rotation,
                        orientedAspectRatio: Double(
                            displayedImage.extent.width / displayedImage.extent.height)),
                    rasterColorSpace: raster.rasterColorSpace,
                    perceptualDigest: raster.perceptualDigest, presentedAt: Date(),
                    pixelWidth: raster.pixelWidth, pixelHeight: raster.pixelHeight),
                rasterData: raster.jpegData))
        await frameStore.waitForPendingWrites()
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(
            decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
            as: UTF8.self)
    }

    private static func gitCommit() -> String {
        if let commit = ProcessInfo.processInfo.environment["KROMORA_GIT_COMMIT"] { return commit }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--short", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "unknown" }
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Counts how often `AppViewModel.document` publishes through Observation, which is the
/// invalidation every inspector reading `viewModel.document` would receive.
@MainActor
private final class InvalidationCounter {
    private let model: AppViewModel
    private(set) var documentCount = 0
    private var active = true

    init(model: AppViewModel) {
        self.model = model
        arm()
    }

    func stop() { active = false }

    private func arm() {
        guard active else { return }
        withObservationTracking {
            _ = model.document
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.documentCount += 1
                self?.arm()
            }
        }
    }
}
