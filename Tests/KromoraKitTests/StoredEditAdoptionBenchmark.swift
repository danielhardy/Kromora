import CoreGraphics
import QuartzCore
import XCTest

@testable import KromoraKit

/// KRMA-755: measure when stored edit values reach the panel, the source is prepared, the photo
/// settles, and its histogram is published. Model state only: no `NSWindow`, no drawable, so this
/// needs neither an unlocked display nor a composited surface (unlike the last-known-frame capture).
/// It uses the real `RenderEngine` and a real RAW, so preparation costs what it costs in the app.
///
/// Opt-in: set `KROMORA_STORED_EDIT_ADOPTION_BENCHMARK=1`. `KROMORA_LAST_KNOWN_FRAME_RAW` picks the
/// source (default `realworldtest/DSC01019.ARW`) and `KROMORA_STORED_EDIT_ADOPTION_ITERATIONS` the
/// sample count (default 10). The relaunch scenario reopens the package for each sample; the switch
/// scenario keeps one view model open and measures warm A→B→C→B switches.
@MainActor
final class StoredEditAdoptionBenchmark: TempDirectoryTestCase {
    private struct Sample {
        var adoptedMilliseconds = Double.infinity
        var preparedMilliseconds = Double.infinity
        var readyMilliseconds = Double.infinity
        var histogramMilliseconds = Double.infinity
    }

    private struct Photo {
        let name: String
        let exposure: Double
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
        let relaunchPhoto = Photo(name: rawURL.lastPathComponent, exposure: 1.5)
        let relaunchPackageURL = try await makePackage(from: rawURL, photos: [relaunchPhoto])
        let switchPhotos = [
            Photo(name: "Adoption-A-\(rawURL.lastPathComponent)", exposure: -1.5),
            Photo(name: "Adoption-B-\(rawURL.lastPathComponent)", exposure: 0.0),
            Photo(name: "Adoption-C-\(rawURL.lastPathComponent)", exposure: 1.5),
        ]
        let switchPackageURL = try await makePackage(from: rawURL, photos: switchPhotos)

        // Cold relaunch samples have no previous histogram to mistake for the selected photo.
        var relaunchSamples: [Sample] = []
        for iterationIndex in 0..<iterations {
            let session = try PortableLibrarySession(at: relaunchPackageURL)
            let viewModel = makeAppViewModel(
                engine: RenderEngine(),
                previewFrameStoreDirectory: tempDirectory.appendingPathComponent(
                    "relaunch-frames-\(iterationIndex)", isDirectory: true),
                portablePackageURL: relaunchPackageURL, portableLibrarySession: session)
            viewModel.collection.loadPortableAssets(try session.browsingAssets())
            await viewModel.collection.scanCompletion()
            viewModel.inspectorState.isPresented = true
            let photo = relaunchPhoto
            let sample = try await measure(
                photo, at: try index(of: photo, in: viewModel),
                previousHistogram: nil, in: viewModel)
            await viewModel.shutdown()
            relaunchSamples.append(sample)
        }
        report(relaunchSamples, scenario: "relaunch", source: rawURL.lastPathComponent)

        // Warm samples share the view model. Start on A with its histogram, then repeat A→B→C→B;
        // resetting to A between rounds gives each round the same three measured transitions.
        let session = try PortableLibrarySession(at: switchPackageURL)
        let viewModel = makeAppViewModel(
            engine: RenderEngine(),
            previewFrameStoreDirectory: tempDirectory.appendingPathComponent(
                "switch-frames", isDirectory: true),
            portablePackageURL: switchPackageURL, portableLibrarySession: session)
        viewModel.collection.loadPortableAssets(try session.browsingAssets())
        await viewModel.collection.scanCompletion()
        viewModel.inspectorState.isPresented = true
        let first = switchPhotos[0]
        _ = try await measure(
            first, at: try index(of: first, in: viewModel),
            previousHistogram: nil, in: viewModel)

        var switchSamples: [Sample] = []
        for _ in 0..<iterations {
            // This unmeasured return to A establishes the requested A→B→C→B measured sequence.
            try await settle(first, in: viewModel)
            for photo in [switchPhotos[1], switchPhotos[2], switchPhotos[1]] {
                let previousHistogram = try XCTUnwrap(viewModel.histogram)
                let sample = try await measure(
                    photo, at: try index(of: photo, in: viewModel),
                    previousHistogram: previousHistogram, in: viewModel)
                switchSamples.append(sample)
            }
        }
        await viewModel.shutdown()
        report(switchSamples, scenario: "switch", source: rawURL.lastPathComponent)
    }

    private func makePackage(from rawURL: URL, photos: [Photo]) async throws -> URL {
        let sources = try photos.map { photo -> URL in
            let destination = tempDirectory.appendingPathComponent(photo.name)
            try FileManager.default.copyItem(at: rawURL, to: destination)
            return destination
        }
        let packageURL = tempDirectory.appendingPathComponent("Adoption.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL)
        _ = try session.importURLs(sources, duplicatePolicy: .importAnyway)
        let seed = makeAppViewModel(
            engine: RenderEngine(), portablePackageURL: packageURL,
            portableLibrarySession: session)
        seed.collection.loadPortableAssets(try session.materializedAssets())
        await seed.collection.scanCompletion()
        for photo in photos {
            let photoIndex = try index(of: photo, in: seed)
            seed.selectCollectionImage(at: photoIndex)
            try await wait(60, "\(photo.name) to open") {
                seed.sourceName == photo.name && seed.previewState == .ready
            }
            seed.updateDocument { $0.light.exposure = photo.exposure }
            let flushed = await seed.flushPendingWrites()
            XCTAssertEqual(flushed, .success)
        }
        await seed.shutdown()
        return packageURL
    }

    private func index(of photo: Photo, in viewModel: AppViewModel) throws -> Int {
        try XCTUnwrap(viewModel.collection.items.firstIndex { $0.displayName == photo.name })
    }

    private func measure(
        _ photo: Photo, at index: Int, previousHistogram: HistogramData?, in viewModel: AppViewModel
    ) async throws -> Sample {
        var sample = Sample()
        let start = CACurrentMediaTime()
        viewModel.selectCollectionImage(at: index)
        let deadline = start + 60
        while sample.readyMilliseconds == .infinity || sample.histogramMilliseconds == .infinity {
            let elapsed = (CACurrentMediaTime() - start) * 1_000
            if sample.adoptedMilliseconds == .infinity,
                viewModel.document.light.exposure == photo.exposure
            {
                sample.adoptedMilliseconds = elapsed
            }
            if sample.preparedMilliseconds == .infinity, viewModel.sourceName == photo.name,
                viewModel.sourceImage != nil
            {
                sample.preparedMilliseconds = elapsed
            }
            if sample.readyMilliseconds == .infinity,
                viewModel.sourceName == photo.name, viewModel.previewState == .ready
            {
                sample.readyMilliseconds = elapsed
            }
            // HistogramData is Equatable and each photo has a distinct stored exposure. Requiring
            // a value different from the previous photo prevents its intentionally retained chart
            // from satisfying this measurement while the newly selected image is loading.
            if sample.histogramMilliseconds == .infinity,
                let histogram = viewModel.histogram, histogram != previousHistogram
            {
                sample.histogramMilliseconds = elapsed
            }
            if CACurrentMediaTime() >= deadline { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNotEqual(sample.adoptedMilliseconds, .infinity, "stored edits never adopted")
        XCTAssertNotEqual(sample.preparedMilliseconds, .infinity, "source never prepared")
        XCTAssertNotEqual(sample.readyMilliseconds, .infinity, "photo never became ready")
        XCTAssertNotEqual(sample.histogramMilliseconds, .infinity, "new histogram never published")
        return sample
    }

    private func settle(_ photo: Photo, in viewModel: AppViewModel) async throws {
        let currentIndex = try index(of: photo, in: viewModel)
        if viewModel.sourceName == photo.name, viewModel.previewState == .ready,
            viewModel.histogram != nil
        {
            return
        }
        let previousHistogram = viewModel.histogram
        _ = try await measure(
            photo, at: currentIndex, previousHistogram: previousHistogram,
            in: viewModel)
    }

    private func report(_ samples: [Sample], scenario: String, source: String) {
        let adopted = samples.map(\.adoptedMilliseconds)
        let prepared = samples.map(\.preparedMilliseconds)
        let ready = samples.map(\.readyMilliseconds)
        let histogram = samples.map(\.histogramMilliseconds)
        let panelLead = zip(prepared, adopted).map { $0 - $1 }
        let histogramAfterReady = zip(histogram, ready).map { $0 - $1 }
        let fields = [
            "STORED_EDIT_ADOPTION scenario=\(scenario) source=\(source) samples=\(samples.count)",
            "adopted_p50=\(fmt(percentile(adopted, 0.5)))",
            "adopted_p95=\(fmt(percentile(adopted, 0.95)))",
            "prepared_p50=\(fmt(percentile(prepared, 0.5)))",
            "prepared_p95=\(fmt(percentile(prepared, 0.95)))",
            "ready_p50=\(fmt(percentile(ready, 0.5)))",
            "ready_p95=\(fmt(percentile(ready, 0.95)))",
            "histogram_p50=\(fmt(percentile(histogram, 0.5)))",
            "histogram_p95=\(fmt(percentile(histogram, 0.95)))",
            "panel_lead_p50=\(fmt(percentile(panelLead, 0.5)))",
            "histogram_after_ready_p50=\(fmt(percentile(histogramAfterReady, 0.5)))",
            "(ms; lead = prepared - adopted)",
        ]
        print(fields.joined(separator: " "))
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
