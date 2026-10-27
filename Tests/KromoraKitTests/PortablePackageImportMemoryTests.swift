import Darwin
import Foundation
import XCTest
import os.lock

@testable import KromoraKit

/// KRMA-1139 — process footprint while the real package importer copies a folder of full-size RAW
/// files. No window and no grid: this isolates the importer (copy, hash, metadata, commit) from the
/// presentation work that follows each commit.
final class PortablePackageImportMemoryTests: TempDirectoryTestCase {
    nonisolated private static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Sparse 48 MiB files (a unique header makes each hash distinct) stand in for camera RAW.
    /// Reading a source chunk by chunk used to leave every chunk of every file alive until the
    /// whole worker job returned, so footprint grew by about twice the batch size. Staging with
    /// either copy mode must now retain far less than one file's worth per file.
    func testStagingDoesNotRetainSourceChunksAcrossABatch() throws {
        let fileSize = 48 << 20
        let count = 16
        let sources = try (0..<count).map { ordinal -> PortablePackageImportSource in
            let url = tempDirectory.appendingPathComponent("source-\(ordinal).arw")
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
            let handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: withUnsafeBytes(of: UInt64(ordinal).littleEndian) { Data($0) })
            try handle.truncate(atOffset: UInt64(fileSize))
            try handle.close()
            return .init(url: url)
        }
        // Pre-fix growth was ~2x the batch (about 1.5 GiB here); legitimate growth is a few MiB.
        let ceiling = UInt64(fileSize * count / 4)

        for mode in [PortablePackageFileCopyMode.automatic, .streamed] {
            let package = try PortableLibraryPackage.create(
                at: tempDirectory.appendingPathComponent("\(mode).kromoralibrary"))
            let lease = try PortablePackageLease.acquire(at: package.rootURL)
            defer { try? lease.release() }
            let baseline = Self.physFootprint()
            let result = try package.importSources(
                sources, lease: lease, options: .init(copyMode: mode))
            let growth = Self.physFootprint().saturatingSubtract(baseline)
            XCTAssertEqual(result.imported.count, count, "\(mode)")
            XCTAssertTrue(result.failures.isEmpty, "\(mode)")
            XCTAssertLessThan(growth, ceiling, "\(mode) retained \(growth >> 20) MiB")
        }
    }

    /// Imports `KROMORA_IMPORT_MEMORY_COUNT` RAW files (cycling the files in
    /// `KROMORA_IMPORT_MEMORY_DIR`) and prints the footprint after every tenth commit. Run in its
    /// own process per count: `KROMORA_IMPORT_MEMORY=1 swift test --filter
    /// PortablePackageImportMemoryTests/testImportFootprintStaysFlatAcrossABatch`.
    func testImportFootprintStaysFlatAcrossABatch() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KROMORA_IMPORT_MEMORY"] == "1", "opt-in measurement")
        let directory = try XCTUnwrap(
            environment["KROMORA_IMPORT_MEMORY_DIR"], "set KROMORA_IMPORT_MEMORY_DIR to a folder of RAW files"
        )
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directory, isDirectory: true), includingPropertiesForKeys: nil
        ).filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(urls.isEmpty, "no files in KROMORA_IMPORT_MEMORY_DIR")
        let count = Int(environment["KROMORA_IMPORT_MEMORY_COUNT"] ?? "") ?? urls.count
        let sources = (0..<count).map { PortablePackageImportSource(url: urls[$0 % urls.count]) }

        let package = try PortableLibraryPackage.create(
            at: tempDirectory.appendingPathComponent("memory.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }

        let baseline = Self.physFootprint()
        let peak = OSAllocatedUnfairLock(initialState: baseline)
        let committed = OSAllocatedUnfairLock(initialState: 0)
        let result = try package.importSources(
            sources, lease: lease,
            options: .init(duplicatePolicy: .importAnyway),
            committed: { _ in
                let now = Self.physFootprint()
                peak.withLock { $0 = max($0, now) }
                let n = committed.withLock { value -> Int in value += 1; return value }
                if n % 10 == 0 {
                    print("IMPORT_MEMORY commits=\(n) footprint_MB=\(now >> 20)")
                }
            }
        )
        let final = Self.physFootprint()
        let peakValue = peak.withLock { $0 }
        print("IMPORT_MEMORY files=\(count) baseline_MB=\(baseline >> 20) peak_MB=\(peakValue >> 20) final_MB=\(final >> 20)")
        XCTAssertEqual(result.imported.count, count)
        XCTAssertTrue(result.failures.isEmpty)
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 { self > other ? self - other : 0 }
}
