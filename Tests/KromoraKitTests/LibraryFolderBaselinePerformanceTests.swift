import Foundation
import Darwin
import XCTest

@testable import KromoraKit

/// Opt-in pre-package baseline for the current folder-backed library.
///
/// This is intentionally a benchmark test rather than a production instrumentation seam. It
/// exercises ImageCollection's existing folder scan, projection, and demand-driven thumbnail
/// behavior, then exercises AppViewModel's existing interactive preview submission path with the
/// test renderer. Generated files are owned by the test and removed before it returns.
@MainActor
final class LibraryFolderBaselinePerformanceTests: TempDirectoryTestCase {

    private static let firstPageSize = 60
    private static let defaultSampleCount = 3

    private struct Metric: Codable {
        let unit: String
        let samples: Int
        let p95: Double
        let p999: Double
    }

    private struct ScaleResult: Codable {
        let assetCount: Int
        let method: String
        let metrics: [String: Metric]
    }

    private struct Environment: Codable {
        let machineClass: String
        let macOS: String
        let disk: String
        let swift: String
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let benchmark: String
        let sampleCount: Int
        let firstPageSize: Int
        let environment: Environment
        let scales: [String: ScaleResult]
    }

    private enum BenchmarkError: Error, CustomStringConvertible {
        case timeout(String)
        case unexpected(String)

        var description: String {
            switch self {
            case .timeout(let message), .unexpected(let message): return message
            }
        }
    }

    func testCurrentFolderBackedLibraryBaseline() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_LIBRARY_BASELINE_BENCHMARK"] != nil,
            "set KROMORA_LIBRARY_BASELINE_BENCHMARK=1 to run the folder-backed library baseline"
        )

        let sampleCount = max(
            1,
            Int(ProcessInfo.processInfo.environment["KROMORA_LIBRARY_BASELINE_SAMPLES"] ?? "")
                ?? Self.defaultSampleCount
        )
        var scaleResults: [String: ScaleResult] = [:]

        for scale in SyntheticLibraryGenerator.Scale.allCases {
            print("LIBRARY_BASELINE_SCALE_BEGIN items=\(scale.assetCount)")
            let root = try await generatedRoot(for: scale)
            defer { try? FileManager.default.removeItem(at: root) }

            var warmLaunch: [Double] = []
            var firstPage: [Double] = []
            var filter: [Double] = []
            var scroll: [Double] = []
            var memory: [Double] = []
            var decodedThumbnails: [Double] = []
            var interactivePreview: [Double] = []

            for _ in 0..<sampleCount {
                print("LIBRARY_BASELINE_SAMPLE_BEGIN items=\(scale.assetCount)")
                let collectionMetrics = try await measureCollection(
                    at: root, scale: scale
                )
                warmLaunch.append(collectionMetrics.warmLaunchMs)
                firstPage.append(collectionMetrics.firstPageMs)
                filter.append(collectionMetrics.filterMs)
                scroll.append(collectionMetrics.scrollMs)
                memory.append(collectionMetrics.memoryBytes)
                decodedThumbnails.append(collectionMetrics.decodedThumbnailCount)

                interactivePreview.append(
                    try await measureInteractivePreview(at: root)
                )
                print("LIBRARY_BASELINE_SAMPLE_END items=\(scale.assetCount)")
            }

            scaleResults[String(scale.assetCount)] = ScaleResult(
                assetCount: scale.assetCount,
                method: scale == .oneHundredThousand
                    ? "bounded-in-process-item-materialization"
                    : "folder-loader",
                metrics: [
                    "warm-launch": Self.metric(warmLaunch, unit: "ms"),
                    "first-page-delivery": Self.metric(firstPage, unit: "ms"),
                    "filter": Self.metric(filter, unit: "ms"),
                    "scroll": Self.metric(scroll, unit: "ms"),
                    "memory-footprint": Self.metric(memory, unit: "bytes"),
                    "decoded-thumbnail-count": Self.metric(decodedThumbnails, unit: "count"),
                    "interactive-preview-submission": Self.metric(interactivePreview, unit: "ms"),
                ]
            )
        }

        let report = Report(
            schemaVersion: 1,
            benchmark: "current-folder-backed-library",
            sampleCount: sampleCount,
            firstPageSize: Self.firstPageSize,
            environment: Environment(
                machineClass: command("/usr/sbin/sysctl", arguments: ["-n", "hw.model"]),
                macOS: command("/usr/bin/sw_vers", arguments: ["-productVersion"]),
                disk: diskDescription(for: tempDirectory),
                swift: command("/usr/bin/swift", arguments: ["--version"])
            ),
            scales: scaleResults
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BenchmarkError.unexpected("could not encode benchmark report")
        }
        print("LIBRARY_BASELINE_REPORT_BEGIN")
        print(text)
        print("LIBRARY_BASELINE_REPORT_END")

        if let outputPath = ProcessInfo.processInfo.environment["KROMORA_LIBRARY_BASELINE_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    private struct CollectionMetrics {
        let warmLaunchMs: Double
        let firstPageMs: Double
        let filterMs: Double
        let scrollMs: Double
        let memoryBytes: Double
        let decodedThumbnailCount: Double
    }

    private func measureCollection(
        at root: URL, scale: SyntheticLibraryGenerator.Scale
    ) async throws -> CollectionMetrics {
        let beforeMemory = residentMemoryBytes()
        let collection = makeTestCollection()
        collection.beginThumbnailDemand()

        do {
            return try await measureCollection(
                using: collection, at: root, scale: scale, beforeMemory: beforeMemory
            )
        } catch {
            await collection.shutdown()
            throw error
        }
    }

    private func measureCollection(
        using collection: ImageCollection,
        at root: URL,
        scale: SyntheticLibraryGenerator.Scale,
        beforeMemory: UInt64
    ) async throws -> CollectionMetrics {

        let start = DispatchTime.now().uptimeNanoseconds
        let warmLaunchEnd: UInt64
        let firstPageEnd: UInt64

        // The shipped loader intentionally keeps metadata deferred. Stop the deferred reader and
        // thumbnail queue before measuring user operations so a late metadata publication cannot
        // contaminate filter, scroll, or RSS samples.
        if scale == .oneHundredThousand {
            // The current loader retains the complete discovery array, then materializes another
            // complete Item array, before its deferred metadata callbacks perform O(n) lookups.
            // On ordinary CI runners the real 100k path is therefore not a bounded in-process
            // measurement (it can exceed a gigabyte before publishing its first batch). Use the
            // same current Item value shape for the scale-dependent measurements so this lane
            // remains runnable and records the eager-object baseline.
            let items = try baselineItems(at: root, count: scale.assetCount)
            collection.clear()
            collection.items = items
            collection.isActive = !items.isEmpty
            collection.beginThumbnailDemand()
            firstPageEnd = DispatchTime.now().uptimeNanoseconds
            warmLaunchEnd = firstPageEnd
        } else {
            collection.loadFromFolder(root)
            try await waitFor("first page at \(scale.assetCount)") {
                collection.items.count >= min(Self.firstPageSize, scale.assetCount)
            }
            firstPageEnd = DispatchTime.now().uptimeNanoseconds
            try await waitFor("folder discovery at \(scale.assetCount)") {
                collection.items.count >= scale.assetCount
            }
            let discoveryEnd = DispatchTime.now().uptimeNanoseconds
            await collection.shutdown()
            warmLaunchEnd = discoveryEnd
        }
        let memory = max(0, residentMemoryBytes() - beforeMemory)

        // Seed only isolated culling state for the filter projection. These values never touch the
        // generated files and the isolated UserDefaults are removed by TempDirectoryTestCase.
        for item in collection.items.prefix(min(100, collection.items.count)) {
            collection.setFlag(.pick, for: item.id)
        }
        let filterStart = DispatchTime.now().uptimeNanoseconds
        collection.setFilter(LibraryFilter(flag: .picks))
        _ = collection.filteredItemCount
        let filterEnd = DispatchTime.now().uptimeNanoseconds
        collection.clearFilter()

        let pageSize = min(Self.firstPageSize, collection.items.count)
        let firstIDs = collection.items.prefix(pageSize).map(\.id)
        for id in firstIDs {
            collection.requestThumbnail(for: id, priority: .visibleGrid)
        }
        try await waitFor("first visible thumbnails at \(scale.assetCount)") {
            collection.items.prefix(pageSize).allSatisfy { $0.thumbnail != nil }
        }
        let decodedCount = collection.items.reduce(into: 0) { count, item in
            if item.thumbnail != nil { count += 1 }
        }

        let nextIDs = collection.items.dropFirst(pageSize).prefix(pageSize).map(\.id)
        let decodedBeforeScroll = decodedCount
        let scrollStart = DispatchTime.now().uptimeNanoseconds
        for id in nextIDs {
            collection.requestThumbnail(for: id, priority: .visibleGrid)
        }
        if !nextIDs.isEmpty {
            try await waitFor("next visible thumbnail at \(scale.assetCount)") {
                collection.items.reduce(into: 0) { count, item in
                    if item.thumbnail != nil { count += 1 }
                } > decodedBeforeScroll
            }
        }
        let scrollEnd = DispatchTime.now().uptimeNanoseconds

        return CollectionMetrics(
            warmLaunchMs: milliseconds(from: start, to: warmLaunchEnd),
            firstPageMs: milliseconds(from: start, to: firstPageEnd),
            filterMs: milliseconds(from: filterStart, to: filterEnd),
            scrollMs: milliseconds(from: scrollStart, to: scrollEnd),
            memoryBytes: Double(memory),
            decodedThumbnailCount: Double(decodedCount)
        )
    }

    private func measureInteractivePreview(at root: URL) async throws -> Double {
        let fake = FakeRenderEngine()
        let reader = FakeRenderEventReader(await fake.eventStream())
        let viewModel = AppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: makeTestUserDefaults(),
            libraryFolderURL: tempDirectory.appendingPathComponent("managed-library"),
            userLookFolderURL: tempDirectory.appendingPathComponent("looks"),
            previewDiskCacheDirectory: tempDirectory.appendingPathComponent("preview-cache")
        )
        do {
            // Preview submission is independent of collection cardinality. Open one generated
            // source through the public AppViewModel URL path so this metric does not rescan the
            // 100k folder a second time for every sample.
            let firstURL = root
                .appendingPathComponent("Group-00", isDirectory: true)
                .appendingPathComponent("Photo-000000.jpg")
            viewModel.openImage(url: firstURL)
            _ = try await nextEvent(from: reader, description: "source preparation") { event in
                if case .sourcePreparationCompleted = event { return true }
                return false
            }
            _ = try await nextEvent(from: reader, description: "settled preview") { event in
                if case .previewRequested = event { return true }
                return false
            }
            _ = try await nextEvent(from: reader, description: "settled preview completion") { event in
                if case .previewCompleted = event { return true }
                return false
            }

            viewModel.beginPreviewInteraction()
            let start = DispatchTime.now().uptimeNanoseconds
            viewModel.updateDocument(debounced: true) { document in
                document.light.exposure = 0.01
            }
            _ = try await nextEvent(from: reader, description: "interactive preview submission") { event in
                guard case .previewRequested(let record) = event else { return false }
                if case .interactive = record.scale { return true }
                return false
            }
            let end = DispatchTime.now().uptimeNanoseconds
            viewModel.endPreviewInteraction()
            await viewModel.shutdown()
            return milliseconds(from: start, to: end)
        } catch {
            await viewModel.shutdown()
            throw error
        }
    }

    private func nextEvent(
        from reader: FakeRenderEventReader,
        description: String,
        matching predicate: @escaping @Sendable (FakeRenderEngine.Event) -> Bool
    ) async throws -> FakeRenderEngine.Event {
        try await TestSynchronization.nextEvent(
            from: reader,
            description,
            timeout: .seconds(30),
            matching: predicate,
            diagnostics: { "library baseline event wait" }
        )
    }

    private func generatedRoot(for scale: SyntheticLibraryGenerator.Scale) async throws -> URL {
        let library = try await SyntheticLibraryGenerator.generate(
            scale: scale,
            seed: SyntheticLibraryGenerator.defaultSeed,
            in: tempDirectory,
            yieldEvery: 256
        )
        return library.rootURL
    }

    private func baselineItems(at root: URL, count: Int) throws -> [ImageCollection.Item] {
        var items: [ImageCollection.Item] = []
        items.reserveCapacity(count)
        // Avoid another 100k filesystem fingerprint pass in the safe in-process fallback. The
        // source still points at generated URLs, so thumbnail decoding exercises real bytes;
        // projections only need a stable current-schema file identity.
        let fingerprint = PhotoSourceFingerprint(
            byteCount: 1, modificationDate: nil, resourceIdentifier: nil, sampleDigest: nil
        )
        for group in 0..<10 {
            let groupName = String(format: "Group-%02d", group)
            let directory = root.appendingPathComponent(groupName, isDirectory: true)
            for index in stride(from: group, to: count, by: 10) {
                let filename = String(format: "Photo-%06d.jpg", index)
                let url = directory.appendingPathComponent(filename)
                let source = PhotoAssetSource(
                    url: url,
                    id: PhotoAssetID.file(url, fingerprint: fingerprint),
                    data: nil,
                    fingerprint: fingerprint
                )
                items.append(ImageCollection.Item(
                    asset: PhotoAsset(
                        source: source,
                        filename: url.deletingPathExtension().lastPathComponent,
                        fileType: url.pathExtension
                    ),
                    subfolder: groupName
                ))
            }
        }
        guard items.count == count else {
            throw BenchmarkError.unexpected(
                "baseline item materialization expected \(count), got \(items.count)"
            )
        }
        return items
    }

    private func waitFor(
        _ description: String,
        timeout: Duration = .seconds(45),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw BenchmarkError.timeout(description) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func metric(_ values: [Double], unit: String) -> Metric {
        let sorted = values.sorted()
        func percentile(_ fraction: Double) -> Double {
            let rank = max(1, Int(ceil(Double(sorted.count) * fraction)))
            return sorted[min(sorted.count, rank) - 1]
        }
        return Metric(
            unit: unit,
            samples: values.count,
            p95: percentile(0.95),
            p999: percentile(0.999)
        )
    }

    private func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    private func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private func command(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "unavailable" }
        process.waitUntilExit()
        guard let output = try? pipe.fileHandleForReading.readToEnd(),
              let value = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return "unavailable" }
        return value.replacingOccurrences(of: "\n", with: " ")
    }

    private func diskDescription(for url: URL) -> String {
        let output = command("/usr/sbin/diskutil", arguments: ["info", url.path])
        if output == "unavailable" { return output }
        let lines = output.split(separator: " ", omittingEmptySubsequences: true)
        if output.localizedCaseInsensitiveContains("Solid State") { return "solid-state" }
        if output.localizedCaseInsensitiveContains("Rotational") { return "rotational" }
        return lines.first.map(String.init) ?? "unknown"
    }
}
