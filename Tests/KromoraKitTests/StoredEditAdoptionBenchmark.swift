import CoreGraphics
import QuartzCore
import XCTest

@testable import KromoraKit

/// KRMA-755: when does the Edit panel get a photo's stored edit values, relative to the source
/// finishing preparation? Model state only: no `NSWindow`, no drawable, so it needs neither an
/// unlocked display nor a composited surface (unlike the last-known-frame capture). It uses the
/// real `RenderEngine` and a real RAW, so preparation costs what it costs in the app.
///
/// Opt-in: set `KROMORA_STORED_EDIT_ADOPTION_BENCHMARK=1`. `KROMORA_LAST_KNOWN_FRAME_RAW` picks the
/// source (default `realworldtest/DSC01019.ARW`) and `KROMORA_STORED_EDIT_ADOPTION_ITERATIONS` the
/// sample count (default 10). Each sample reopens the package, as a relaunch would, with an empty
/// preview-frame store, and selects the photo through the production selection entry point.
@MainActor
final class StoredEditAdoptionBenchmark: TempDirectoryTestCase {
    private struct Sample {
        var adoptedMilliseconds = Double.infinity
        var preparedMilliseconds = Double.infinity
        var readyMilliseconds = Double.infinity
    }

    func testStoredEditsReachThePanelBeforeSourcePreparationFinishes() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["KROMORA_STORED_EDIT_ADOPTION_BENCHMARK"] != nil,
            "set KROMORA_STORED_EDIT_ADOPTION_BENCHMARK=1 (no display needed)"
        )
        let rawPath = environment["KROMORA_LAST_KNOWN_FRAME_RAW"] ?? "realworldtest/DSC01019.ARW"
        let rawURL = URL(
            fileURLWithPath: rawPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw XCTSkip("RAW benchmark source is missing: \(rawURL.path)")
        }
        let iterations = min(
            50, max(3, Int(environment["KROMORA_STORED_EDIT_ADOPTION_ITERATIONS"] ?? "10") ?? 10))
        let storedExposure = 1.5

        let source = tempDirectory.appendingPathComponent(rawURL.lastPathComponent)
        try FileManager.default.copyItem(at: rawURL, to: source)
        let packageURL = tempDirectory.appendingPathComponent("Adoption.kromoralibrary")

        // Give the photo a stored edit, then relaunch for every sample.
        do {
            let session = try PortableLibrarySession(at: packageURL)
            _ = try session.importURLs([source], duplicatePolicy: .importAnyway)
            let seed = makeAppViewModel(
                engine: RenderEngine(), portablePackageURL: packageURL,
                portableLibrarySession: session)
            seed.collection.loadPortableAssets(try session.materializedAssets())
            await seed.collection.scanCompletion()
            seed.collection.setSelection(at: 0)
            seed.openActiveCollectionImage()
            try await wait(30, "the seed photo to open") { seed.previewState == .ready }
            seed.updateDocument { $0.light.exposure = storedExposure }
            let flushed = await seed.flushPendingWrites()
            XCTAssertEqual(flushed, .success)
            await seed.shutdown()
        }

        var samples: [Sample] = []
        for index in 0..<iterations {
            let session = try PortableLibrarySession(at: packageURL)
            let viewModel = makeAppViewModel(
                engine: RenderEngine(),
                previewFrameStoreDirectory: tempDirectory.appendingPathComponent(
                    "frames-\(index)", isDirectory: true),
                portablePackageURL: packageURL, portableLibrarySession: session)
            // Production browsing items carry placeholder identities that resolve on open.
            viewModel.collection.loadPortableAssets(try session.browsingAssets())
            await viewModel.collection.scanCompletion()

            var sample = Sample()
            let start = CACurrentMediaTime()
            viewModel.selectCollectionImage(at: 0)
            let deadline = start + 60
            while sample.readyMilliseconds == .infinity, CACurrentMediaTime() < deadline {
                let elapsed = (CACurrentMediaTime() - start) * 1_000
                if sample.adoptedMilliseconds == .infinity,
                    viewModel.document.light.exposure == storedExposure
                {
                    sample.adoptedMilliseconds = elapsed
                }
                if sample.preparedMilliseconds == .infinity, viewModel.sourceImage != nil {
                    sample.preparedMilliseconds = elapsed
                }
                if viewModel.previewState == .ready { sample.readyMilliseconds = elapsed }
                try await Task.sleep(for: .milliseconds(1))
            }
            await viewModel.shutdown()
            XCTAssertNotEqual(sample.adoptedMilliseconds, .infinity, "stored edits never adopted")
            samples.append(sample)
        }

        let adopted = samples.map(\.adoptedMilliseconds)
        let prepared = samples.map(\.preparedMilliseconds)
        let ready = samples.map(\.readyMilliseconds)
        let gap = zip(prepared, adopted).map { $0 - $1 }
        print(
            "STORED_EDIT_ADOPTION source=\(rawURL.lastPathComponent) samples=\(samples.count) "
                + "adopted_p50=\(fmt(percentile(adopted, 0.5))) adopted_p95=\(fmt(percentile(adopted, 0.95))) "
                + "prepared_p50=\(fmt(percentile(prepared, 0.5))) prepared_p95=\(fmt(percentile(prepared, 0.95))) "
                + "ready_p50=\(fmt(percentile(ready, 0.5))) ready_p95=\(fmt(percentile(ready, 0.95))) "
                + "panel_lead_p50=\(fmt(percentile(gap, 0.5))) (ms; lead = prepared - adopted)"
        )
    }

    private func wait(
        _ seconds: Double, _ description: String, _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = CACurrentMediaTime() + seconds
        while !condition() {
            if CACurrentMediaTime() > deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    /// Nearest-rank percentile.
    private func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }
}
