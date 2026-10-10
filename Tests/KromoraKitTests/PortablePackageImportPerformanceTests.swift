import Darwin
import Foundation
import XCTest
import os.lock

@testable import KromoraKit

/// Sequential sources, real package transactions, no window or decoder. Camera-sized payloads
/// are deterministic bytes: this measures transport/integrity, not image validation or scanning.
final class PortablePackageImportPerformanceTests: TempDirectoryTestCase {
    func testImportThroughput() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KROMORA_IMPORT_BENCHMARK"] == "1",
                          "set KROMORA_IMPORT_BENCHMARK=1; run with swift test -c release")
        var mixes: [(String, [URL])] = [
            ("small", try generate(name: "small", sizes: Array(repeating: 256 << 10, count: 192)
                                    + Array(repeating: 2 << 20, count: 8))),
            ("large", try generate(name: "large", sizes: Array(repeating: 32 << 20, count: 8)
                                    + Array(repeating: 64 << 20, count: 4))),
        ]
        if let path = environment["KROMORA_IMPORT_SOURCE_DIR"] {
            let urls = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil
            ).filter { !$0.lastPathComponent.hasPrefix(".")
                && ["arw", "cr3", "nef", "dng", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            XCTAssertFalse(urls.isEmpty)
            let count = Int(environment["KROMORA_IMPORT_SOURCE_COUNT"] ?? "12") ?? 12
            let offset = Int(environment["KROMORA_IMPORT_SOURCE_OFFSET"] ?? "0") ?? 0
            mixes.append(("card", Array(urls.dropFirst(max(0, offset)).prefix(max(1, count)))))
        }
        let samples = Int(environment["KROMORA_IMPORT_SAMPLES"] ?? "3") ?? 3
        let chunkSize = Int(environment["KROMORA_IMPORT_CHUNK_SIZE"] ?? "1048576") ?? 1048576
        for (name, urls) in mixes {
            for sample in 0..<max(1, samples) {
                let package = try PortableLibraryPackage.create(
                    at: tempDirectory.appendingPathComponent("\(name)-\(sample).kromoralibrary"))
                let lease = try PortablePackageLease.acquire(at: package.rootURL)
                defer { try? lease.release() }
                let projection = try LibraryIndexProjection(libraryID: package.manifest.libraryID, entries: [])
                // F_NOCACHE avoids adding this pass to the cache, but does not evict pages
                // already cached by an earlier import. Report warm and cold passes separately.
                let readStart = ContinuousClock.now
                let bytes = try sequentialRead(urls, chunkSize: chunkSize)
                let readSeconds = seconds(readStart.duration(to: .now))
                let timings = OSAllocatedUnfairLock<[String: Double]>(initialState: [:])
                let start = ContinuousClock.now
                let result = try package.importSources(
                    urls.map { .init(url: $0) }, lease: lease,
                    options: .init(chunkSize: chunkSize, copyMode: .streamed, timingObserver: { phase, duration in
                        let components = duration.components
                        let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1e18
                        timings.withLock { $0[phase.rawValue, default: 0] += elapsed }
                    })
                )
                let importSeconds = seconds(start.duration(to: .now))
                let indexStart = ContinuousClock.now
                let updated = try projection.applying(result.indexDelta)
                try updated.write(to: tempDirectory.appendingPathComponent("\(name)-\(sample)-index.json"))
                let indexSeconds = seconds(indexStart.duration(to: .now))
                XCTAssertEqual(result.imported.count, urls.count)
                XCTAssertTrue(result.failures.isEmpty)
                XCTAssertFalse(result.cancelled)
                XCTAssertEqual(result.imported.reduce(0) { $0 + $1.byteCount }, bytes)
                let phases = timings.withLock { $0 }.sorted { $0.key < $1.key }
                    .map { "\($0.key)_s=\(String(format: "%.4f", $0.value))" }.joined(separator: " ")
                print("IMPORT_THROUGHPUT mix=\(name) sample=\(sample + 1) files=\(urls.count) bytes=\(bytes) chunk=\(chunkSize) sequential_MBps=\(String(format: "%.2f", Double(bytes) / readSeconds / 1e6)) import_MBps=\(String(format: "%.2f", Double(bytes) / importSeconds / 1e6)) total_s=\(String(format: "%.4f", importSeconds)) index_s=\(String(format: "%.4f", indexSeconds)) \(phases)")
                try FileManager.default.removeItem(at: package.rootURL)
            }
        }
    }

    private func generate(name: String, sizes: [Int]) throws -> [URL] {
        try sizes.enumerated().map { ordinal, size in
            var data = Data(repeating: UInt8(truncatingIfNeeded: ordinal), count: size)
            data.replaceSubrange(0..<8, with: withUnsafeBytes(of: UInt64(ordinal).littleEndian) { Data($0) })
            let url = tempDirectory.appendingPathComponent("\(name)-\(ordinal).\(size < 4 << 20 ? "jpg" : "raw")")
            try data.write(to: url)
            return url
        }
    }

    private func sequentialRead(_ urls: [URL], chunkSize: Int) throws -> UInt64 {
        var bytes: UInt64 = 0
        for url in urls {
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            guard fcntl(input.fileDescriptor, F_NOCACHE, 1) == 0 else { throw CocoaError(.fileReadUnknown) }
            while let data = try input.read(upToCount: max(1, chunkSize)), !data.isEmpty {
                bytes += UInt64(data.count)
            }
        }
        return bytes
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
