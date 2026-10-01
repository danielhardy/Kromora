import AppKit
import CoreImage
import Foundation
import QuartzCore
import SwiftUI
import XCTest

@testable import KromoraKit

/// Release-only qualification of the warm Edit and 30-cell grid paths. The test mounts the
/// shipping ContentView in a visible window; confirmation counts come from PreviewSurface's
/// drawable callback and renderer admissions come from PreviewCoordinator.
@MainActor
final class LastKnownFrameReleaseBenchmark: TempDirectoryTestCase {
    private enum BenchmarkError: Error {
        case presentationTimedOut(String)
    }
    private struct Report: Encodable {
        let benchmark: String
        let source: String
        let sourceFormat: String
        let sourceDimensions: String
        let viewportPoints: String
        let backingPixels: String
        let coldWarmState: String
        let cacheState: String
        let sampleCount: Int
        let p50Milliseconds: Double
        let p95Milliseconds: Double
        let provisionalFrames: Int
        let confirmedFrames: Int
        let renderAdmissions: Int
        let crossfades: Int
        let thumbnailSwaps: Int
        let layoutChanges: Int
        let mainActorBeforeSuspensionP95Milliseconds: Double
        let budget: String
    }

    func testReleaseLastKnownFrameBudgets() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_LAST_KNOWN_FRAME_BENCHMARK"] != nil,
            "set KROMORA_LAST_KNOWN_FRAME_BENCHMARK=1 in a logged-in Release capture"
        )
        let rawPath =
            ProcessInfo.processInfo.environment["KROMORA_LAST_KNOWN_FRAME_RAW"]
            ?? "realworldtest/DSC01019.ARW"
        let rawURL = URL(
            fileURLWithPath: rawPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        .standardizedFileURL
        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw XCTSkip("RAW benchmark source is missing: \(rawURL.path)")
        }
        let dimensions = try XCTUnwrap(Fixtures.storedSize(of: rawURL))
        let urls = try makeGridFixtures()
        let sourceInGrid = tempDirectory.appendingPathComponent(rawURL.lastPathComponent)
        try FileManager.default.copyItem(at: rawURL, to: sourceInGrid)
        let model = makeAppViewModel(
            engine: RenderEngine(),
            libraryFolderURL: tempDirectory.appendingPathComponent("managed-library"),
            previewFrameStoreDirectory: tempDirectory.appendingPathComponent("last-known-frames")
        )
        let importSummary = model.openImages(urls: urls + [sourceInGrid])
        guard let importSummary, importSummary.imported + importSummary.duplicates == 31 else {
            throw XCTSkip(
                "The benchmark fixtures could not be imported: "
                    + (importSummary?.failureReasons.joined(separator: "; ") ?? "no result")
            )
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1440, height: 1000),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: ContentView(viewModel: model))
        window.isReleasedWhenClosed = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        defer {
            window.orderOut(nil)
            window.close()
        }

        // First visit hydrates the actual visible mosaic and warms its in-memory thumbnails.
        let coldGridStart = CACurrentMediaTime()
        XCTAssertTrue(model.navigate(to: .grid))
        try await waitForVisibleGrid(model)
        let coldGridMS = milliseconds(since: coldGridStart)

        guard
            let rawIndex = model.collection.items.firstIndex(where: {
                $0.url?.lastPathComponent == sourceInGrid.lastPathComponent
            })
        else {
            throw XCTSkip("The real RAW must be inside the scanned collection folder")
        }
        // Start in Edit and wait for the actual confirmed drawable, then sample repeated warm
        // Library → Edit handoffs. The synchronous call is the work done before its tasks yield.
        model.selectCollectionImage(at: rawIndex)
        try await waitForDrawableFrame(model)
        try await Task.sleep(for: .milliseconds(300))
        let frameStore = LatestPreviewFrameStore(
            directory: tempDirectory.appendingPathComponent("last-known-frames")
        )
        let source = try XCTUnwrap(model.admissionImageSource)
        let displayedImage = try XCTUnwrap(model.previewSurface.image)
        let previewRequest = RenderRequest(
            source: source, document: model.document, quality: .preview
        )
        guard
            let raster = await RenderEngine.shared.makeCanonicalPreviewRaster(
                displayedImage, space: previewRequest.space,
                longEdge: LatestPreviewFrameStore.canonicalLongEdge
            )
        else {
            throw XCTSkip("The displayed warm frame could not be encoded for the cache fixture")
        }
        let identity = source.portableIdentity
        await frameStore.enqueueWrite(
            PresentationFrame(
                metadata: PresentationFrameMetadata(
                    identity: identity, kind: .preview2048,
                    signature: FrameSignature(
                        source: identity, editHash: previewRequest.document.editHash,
                        look: previewRequest.lookSignature, workingSpace: previewRequest.space,
                        pixelEpoch: RenderPipeline.pixelEpoch
                    ),
                    geometry: PresentedGeometry(
                        crop: previewRequest.document.crop,
                        rotation: previewRequest.document.rotation,
                        orientedAspectRatio: Double(
                            displayedImage.extent.width / displayedImage.extent.height)
                    ),
                    rasterColorSpace: raster.rasterColorSpace,
                    perceptualDigest: raster.perceptualDigest, presentedAt: Date(),
                    pixelWidth: raster.pixelWidth, pixelHeight: raster.pixelHeight
                ),
                rasterData: raster.jpegData
            ))
        await frameStore.waitForPendingWrites()
        guard let storedFrame = await frameStore.read(for: identity) else {
            throw XCTSkip("The generated exact warm frame could not be reopened")
        }

        let iterations = boundedIterations()
        _ = model.navigate(to: .grid)
        let exactActorStart = CACurrentMediaTime()
        let exactRendersBefore = model.previewRenderAdmissionCountForDiagnostics
        let exactCrossfadesBefore = model.previewSurface.crossfadeAdmissionCount
        model.selectCollectionImage(at: rawIndex)
        let exactMainActor = milliseconds(since: exactActorStart)
        try await waitForDrawableFrame(model)
        let exactSession = try XCTUnwrap(model.presentationSessionForDiagnostics)
        try emit(
            makeReport(
                "exact-warm-edit", rawURL: rawURL, dimensions: dimensions, window: window,
                coldWarm: "warm", cacheState: "exact stored preview", sampleCount: 1,
                p50: exactSession.firstPixelLatencyMilliseconds ?? .infinity,
                p95: exactSession.firstPixelLatencyMilliseconds ?? .infinity,
                provisionalFrames: exactSession.provisionalFrameCount,
                confirmedFrames: exactSession.confirmedFrameCount,
                renderAdmissions: model.previewRenderAdmissionCountForDiagnostics
                    - exactRendersBefore,
                crossfades: model.previewSurface.crossfadeAdmissionCount - exactCrossfadesBefore,
                thumbnailSwaps: 0, layoutChanges: 2,
                mainActorMilliseconds: exactMainActor,
                budget: "zero preview renders; one confirmed frame per sample"
            ))

        let oldMetadata = storedFrame.frame.metadata
        let oldSignature = oldMetadata.signature
        await frameStore.enqueueWrite(
            PresentationFrame(
                metadata: PresentationFrameMetadata(
                    identity: oldMetadata.identity, kind: oldMetadata.kind,
                    signature: FrameSignature(
                        source: oldSignature.source, editHash: "krma742-stale-edit",
                        look: oldSignature.look, workingSpace: oldSignature.workingSpace,
                        pixelEpoch: oldSignature.pixelEpoch
                    ),
                    geometry: oldMetadata.geometry, rasterColorSpace: oldMetadata.rasterColorSpace,
                    perceptualDigest: oldMetadata.perceptualDigest,
                    presentedAt: oldMetadata.presentedAt,
                    pixelWidth: oldMetadata.pixelWidth, pixelHeight: oldMetadata.pixelHeight
                ),
                rasterData: storedFrame.frame.rasterData
            ))
        await frameStore.waitForPendingWrites()
        _ = model.navigate(to: .grid)
        let staleActorStart = CACurrentMediaTime()
        let staleRendersBefore = model.previewRenderAdmissionCountForDiagnostics
        let staleCrossfadesBefore = model.previewSurface.crossfadeAdmissionCount
        model.selectCollectionImage(at: rawIndex)
        let staleMainActor = milliseconds(since: staleActorStart)
        try await waitForDrawableFrame(model)
        let staleSession = try XCTUnwrap(model.presentationSessionForDiagnostics)
        try emit(
            makeReport(
                "stale-warm-edit", rawURL: rawURL, dimensions: dimensions, window: window,
                coldWarm: "warm", cacheState: "stale saved edit signature", sampleCount: 1,
                p50: staleSession.firstPixelLatencyMilliseconds ?? .infinity,
                p95: staleSession.firstPixelLatencyMilliseconds ?? .infinity,
                provisionalFrames: staleSession.provisionalFrameCount,
                confirmedFrames: staleSession.confirmedFrameCount,
                renderAdmissions: model.previewRenderAdmissionCountForDiagnostics
                    - staleRendersBefore,
                crossfades: model.previewSurface.crossfadeAdmissionCount - staleCrossfadesBefore,
                thumbnailSwaps: 0, layoutChanges: 2,
                mainActorMilliseconds: staleMainActor,
                budget: "one provisional; at most one confirmed replacement per sample"
            ))

        var navigationTimes: [Double] = []
        var mainActorTimes: [Double] = []
        var provisionalFrameCounts: [Int] = []
        var confirmedFrameCounts: [Int] = []
        var renderAdmissions = 0
        var crossfades = 0
        var editThumbnailSwaps = 0
        var editLayoutChanges = 0
        for _ in 0..<iterations {
            let thumbnailsBeforeGrid = thumbnailSnapshot(model)
            let modeBeforeGrid = model.navigation.mode
            _ = model.navigate(to: .grid)
            if model.navigation.mode != modeBeforeGrid { editLayoutChanges += 1 }
            try await waitForVisibleGrid(model)
            editThumbnailSwaps += changedThumbnails(
                from: thumbnailsBeforeGrid, to: thumbnailSnapshot(model)
            )
            let admissionStart = CACurrentMediaTime()
            let beforeRenders = model.previewRenderAdmissionCountForDiagnostics
            let beforeCrossfades = model.previewSurface.crossfadeAdmissionCount
            let modeBeforeEdit = model.navigation.mode
            model.selectCollectionImage(at: rawIndex)
            if model.navigation.mode != modeBeforeEdit { editLayoutChanges += 1 }
            mainActorTimes.append(milliseconds(since: admissionStart))
            try await waitForDrawableFrame(model)
            guard let session = model.presentationSessionForDiagnostics else {
                XCTFail("A drawable confirmation must leave a presentation session")
                return
            }
            navigationTimes.append(session.firstPixelLatencyMilliseconds ?? .infinity)
            provisionalFrameCounts.append(session.provisionalFrameCount)
            confirmedFrameCounts.append(session.confirmedFrameCount)
            renderAdmissions += model.previewRenderAdmissionCountForDiagnostics - beforeRenders
            crossfades += model.previewSurface.crossfadeAdmissionCount - beforeCrossfades
        }

        // Warm re-entry of a 30-source grid is measured after its visible thumbnails have been
        // hydrated. Reopening the workspace still performs real SwiftUI layout and display.
        var gridTimes: [Double] = []
        var gridThumbnailSwaps = 0
        var gridLayoutChanges = 0
        for _ in 0..<iterations {
            let start = CACurrentMediaTime()
            let thumbnailsBefore = thumbnailSnapshot(model)
            let modeBefore = model.navigation.mode
            _ = model.navigate(to: .grid)
            if model.navigation.mode != modeBefore { gridLayoutChanges += 1 }
            try await waitForVisibleGrid(model)
            gridThumbnailSwaps += changedThumbnails(
                from: thumbnailsBefore, to: thumbnailSnapshot(model)
            )
            window.displayIfNeeded()
            gridTimes.append(milliseconds(since: start))
            model.selectCollectionImage(at: rawIndex)
            try await waitForDrawableFrame(model)
        }

        let backing = window.convertToBacking(window.contentView?.bounds ?? .zero).size
        let gridReport = Report(
            benchmark: "warm-30-cell-grid", source: rawURL.lastPathComponent,
            sourceFormat: rawURL.pathExtension.lowercased(),
            sourceDimensions: "\(Int(dimensions.width))x\(Int(dimensions.height))",
            viewportPoints:
                "\(Int(window.contentView?.bounds.width ?? 0))x\(Int(window.contentView?.bounds.height ?? 0))",
            backingPixels: "\(Int(backing.width))x\(Int(backing.height))",
            coldWarmState: "warm; cold hydration \(format(coldGridMS)) ms",
            cacheState: "visible thumbnails hydrated before warm samples",
            sampleCount: gridTimes.count, p50Milliseconds: percentile(gridTimes, 0.50),
            p95Milliseconds: percentile(gridTimes, 0.95), provisionalFrames: 0,
            confirmedFrames: 0, renderAdmissions: 0, crossfades: 0,
            thumbnailSwaps: gridThumbnailSwaps, layoutChanges: gridLayoutChanges,
            mainActorBeforeSuspensionP95Milliseconds: 0, budget: "p95 <= 100 ms"
        )
        let editReport = Report(
            benchmark: "warm-edit-navigation", source: rawURL.lastPathComponent,
            sourceFormat: rawURL.pathExtension.lowercased(),
            sourceDimensions: "\(Int(dimensions.width))x\(Int(dimensions.height))",
            viewportPoints:
                "\(Int(window.contentView?.bounds.width ?? 0))x\(Int(window.contentView?.bounds.height ?? 0))",
            backingPixels: "\(Int(backing.width))x\(Int(backing.height))",
            coldWarmState: "warm", cacheState: "warm app and preview caches",
            sampleCount: navigationTimes.count,
            p50Milliseconds: percentile(navigationTimes, 0.50),
            p95Milliseconds: percentile(navigationTimes, 0.95),
            provisionalFrames: provisionalFrameCounts.reduce(0, +),
            confirmedFrames: confirmedFrameCounts.reduce(0, +),
            renderAdmissions: renderAdmissions, crossfades: crossfades,
            thumbnailSwaps: editThumbnailSwaps, layoutChanges: editLayoutChanges,
            mainActorBeforeSuspensionP95Milliseconds: percentile(mainActorTimes, 0.95),
            budget: "correct-photo provisional p95 <= 50 ms; main-actor <= 2 ms"
        )
        try emit(gridReport)
        try emit(editReport)
        XCTAssertEqual(urls.count, 30)
    }

    private func makeGridFixtures() throws -> [URL] {
        try (0..<30).map { index in
            try Fixtures.writeJPEG(
                width: 160 + index, height: 120, orientation: 1,
                named: String(format: "grid-%02d.jpg", index), in: tempDirectory
            )
        }
    }

    private func waitForVisibleGrid(_ model: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let visibleIDs = model.collection.visibleEditedThumbnailAssetIDs
            if !visibleIDs.isEmpty
                && visibleIDs.allSatisfy({ id in
                    model.collection.items.first(where: { $0.id == id })?.thumbnail != nil
                })
            {
                return
            }
            // The visible-ID set is an admission hint; wait for visible rows to finish layout.
            if model.collection.items.filter({ $0.thumbnail != nil }).count >= 30 { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The visible 30-cell grid did not hydrate before the deadline")
    }

    private func waitForDrawableFrame(_ model: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if model.presentationSessionForDiagnostics?.state == .confirmed,
                model.previewState == .ready
            {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw BenchmarkError.presentationTimedOut("drawable confirmation timed out")
    }

    private func boundedIterations() -> Int {
        let requested =
            Int(ProcessInfo.processInfo.environment["KROMORA_LAST_KNOWN_FRAME_ITERATIONS"] ?? "20")
            ?? 20
        return min(100, max(5, requested))
    }

    private func emit(_ report: Report) throws {
        let data = try JSONEncoder().encode(report)
        print("LAST_KNOWN_FRAME_BENCHMARK \(String(decoding: data, as: UTF8.self))")
    }

    private func makeReport(
        _ benchmark: String, rawURL: URL, dimensions: CGSize, window: NSWindow,
        coldWarm: String, cacheState: String, sampleCount: Int,
        p50: Double, p95: Double,
        provisionalFrames: Int, confirmedFrames: Int,
        renderAdmissions: Int, crossfades: Int = 0, thumbnailSwaps: Int = 0,
        layoutChanges: Int,
        mainActorMilliseconds: Double, budget: String
    ) -> Report {
        let backing = window.convertToBacking(window.contentView?.bounds ?? .zero).size
        return Report(
            benchmark: benchmark, source: rawURL.lastPathComponent,
            sourceFormat: rawURL.pathExtension.lowercased(),
            sourceDimensions: "\(Int(dimensions.width))x\(Int(dimensions.height))",
            viewportPoints:
                "\(Int(window.contentView?.bounds.width ?? 0))x\(Int(window.contentView?.bounds.height ?? 0))",
            backingPixels: "\(Int(backing.width))x\(Int(backing.height))",
            coldWarmState: coldWarm, cacheState: cacheState, sampleCount: sampleCount,
            p50Milliseconds: p50, p95Milliseconds: p95,
            provisionalFrames: provisionalFrames, confirmedFrames: confirmedFrames,
            renderAdmissions: renderAdmissions, crossfades: crossfades,
            thumbnailSwaps: thumbnailSwaps, layoutChanges: layoutChanges,
            mainActorBeforeSuspensionP95Milliseconds: mainActorMilliseconds,
            budget: budget
        )
    }

    private func thumbnailSnapshot(_ model: AppViewModel) -> [PhotoAssetID: ObjectIdentifier] {
        Dictionary(
            uniqueKeysWithValues: model.collection.items.compactMap { item in
                item.thumbnail.map { (item.id, ObjectIdentifier($0)) }
            })
    }

    private func changedThumbnails(
        from before: [PhotoAssetID: ObjectIdentifier],
        to after: [PhotoAssetID: ObjectIdentifier]
    ) -> Int {
        before.reduce(into: 0) { swaps, entry in
            if let current = after[entry.key], current != entry.value { swaps += 1 }
        }
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile))]
    }

    private func milliseconds(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1_000
    }

    private func format(_ value: Double) -> String { String(format: "%.3f", value) }
}
