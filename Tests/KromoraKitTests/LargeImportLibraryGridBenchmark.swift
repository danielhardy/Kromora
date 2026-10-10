import Darwin
import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-841: window-independent large-import benchmark for the Library grid's thumbnail path.
///
/// Drives a real `ImageCollection` (real scheduler, frame store disabled, real ImageIO/RAW
/// decode) over many large originals with a simulated fast scroll and select-all, and measures
/// main-actor stalls with a heartbeat task. No `NSWindow` is mounted, so it measures model and
/// scheduling cost, not SwiftUI layout. Opt in with `KROMORA_LARGE_IMPORT_BENCHMARK=1` and run in
/// Release: `swift test -c release --filter LargeImportLibraryGridBenchmark`.
@MainActor
final class LargeImportLibraryGridBenchmark: TempDirectoryTestCase {

    private func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1e3 + Double(duration.components.attoseconds) / 1e15
    }

    private func milliseconds(_ duration: Duration) -> Double { Self.milliseconds(duration) }

    private func peakMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576  // bytes on Darwin
    }

    func testLargeImportScrollAndSelectAll() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["KROMORA_LARGE_IMPORT_BENCHMARK"] != nil, "opt-in benchmark")
        let sources = Fixtures.localRAWURLs
        try XCTSkipIf(sources.isEmpty, "no RAW fixtures in realworldtest/ or KROMORA_RAW_FIXTURE_DIR")
        let count = Int(env["KROMORA_LARGE_IMPORT_COUNT"] ?? "") ?? 1_000

        // Identity and the memory cache are content-keyed, so links or plain copies would share
        // one decode. Each copy gets unique trailing bytes (ignored by TIFF/ISO-BMFF readers) so
        // every file is a cold miss.
        var urls: [URL] = []
        for index in 0..<count {
            let source = sources[index % sources.count]
            let url = tempDirectory.appendingPathComponent(
                "import-\(index).\(source.pathExtension)")
            try FileManager.default.copyItem(at: source, to: url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("KRMA841-\(index)-\(UUID().uuidString)".utf8))
            try handle.close()
            urls.append(url)
        }

        let collection = ImageCollection()
        let assets = urls.map { PhotoAsset(url: $0) }
        collection.loadPortableWindow(
            assets: assets, totalCount: count, pageIndex: 0, pageSize: count, query: .all)
        collection.beginThumbnailDemand()

        // Heartbeat: a main-actor task that should wake every 4 ms. Gaps above that are time
        // the main actor was occupied by something else.
        var gaps: [Double] = []
        let heartbeat = Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(4))
                let now = ContinuousClock.now
                gaps.append(Self.milliseconds(now - last))
                last = now
            }
        }

        let columns = 6
        let rowsVisible = 5
        let window = columns * rowsVisible
        let clock = ContinuousClock()

        // Visible-fill: first window.
        var visible = Array(assets[0..<window].map(\.id))
        for id in visible { collection.requestThumbnail(for: id) }
        collection.requestVisibleThumbnails(for: visible)
        let fillStart = clock.now
        while collection.items.prefix(window).contains(where: { $0.thumbnail == nil }) {
            if clock.now - fillStart > .seconds(120) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let fillMs = milliseconds(clock.now - fillStart)

        // Fast scroll: advance one row every 16 ms across the whole library, requesting the new
        // row and releasing the one that left, the way LibraryGridView's onAppear/onDisappear do.
        let scrollStart = clock.now
        var top = 0
        while top + window + columns <= count {
            let leaving = Array(assets[top..<top + columns].map(\.id))
            let entering = Array(assets[top + window..<top + window + columns].map(\.id))
            for id in leaving { collection.releaseThumbnail(for: id) }
            for id in entering { collection.requestThumbnail(for: id) }
            visible = Array(visible.dropFirst(columns)) + entering
            collection.requestVisibleThumbnails(for: visible)
            top += columns
            try await Task.sleep(for: .milliseconds(16))
        }
        let scrollMs = milliseconds(clock.now - scrollStart)

        // Select-all and a click, while decodes are still in flight.
        var selectAllMs: [Double] = []
        for _ in 0..<5 {
            let start = clock.now
            collection.selectAll()
            selectAllMs.append(milliseconds(clock.now - start))
            collection.select(at: 0)
            try await Task.sleep(for: .milliseconds(50))
        }
        let clickStart = clock.now
        collection.select(at: count / 2, modifiers: .shift)
        let shiftClickMs = milliseconds(clock.now - clickStart)

        heartbeat.cancel()
        let sorted = gaps.sorted()
        func percentile(_ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        let report = """
            KRMA-841 large-import grid benchmark: files=\(count) window=\(window)
              visible-fill (\(window) cells): \(String(format: "%.0f", fillMs)) ms
              scroll pass: \(String(format: "%.0f", scrollMs)) ms; heartbeat gaps (ms) p50=\(String(format: "%.1f", percentile(0.5))) p95=\(String(format: "%.1f", percentile(0.95))) p99=\(String(format: "%.1f", percentile(0.99))) max=\(String(format: "%.1f", sorted.last ?? 0)); gaps>33ms=\(sorted.filter { $0 > 33 }.count)/\(sorted.count)
              select-all (ms): \(selectAllMs.map { String(format: "%.2f", $0) }.joined(separator: ", ")); shift-click \(String(format: "%.2f", shiftClickMs)) ms
              decoded thumbnails: \(collection.items.filter { $0.thumbnail != nil }.count)
              memory: resident \(String(format: "%.0f", residentMegabytes())) MB, peak \(String(format: "%.0f", peakMegabytes())) MB
            """
        print(report)
        if let path = env["KROMORA_LARGE_IMPORT_OUTPUT"] {
            try report.write(toFile: path, atomically: true, encoding: .utf8)
        }
        await collection.shutdown()
    }
}
