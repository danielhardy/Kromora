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

    /// Runs a diagnostic tool against this process (pid is inserted after the executable, or before
    /// the first option for `malloc_history`, which wants it first) and returns merged output.
    nonisolated private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        var rest = Array(arguments.dropFirst())
        rest.insert(String(getpid()), at: arguments[0].hasSuffix("malloc_history") ? 0 : rest.count)
        process.arguments = rest
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        guard (try? process.run()) != nil else { return "launch failed" }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text
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

    /// KRMA-1140 — Foundation path standardization, URL resolution and ImageIO metadata return
    /// autoreleased temporaries, and the importer runs a whole batch in one worker job. Without a
    /// pool per source they stayed live until the job returned: about 330 KiB per imported file
    /// regardless of file size (about 40 MiB for this batch). Small files keep the test fast and
    /// show the retention is per item, not per byte.
    func testImportDoesNotRetainPerItemTemporariesAcrossABatch() throws {
        let count = 120
        func makeSources(_ range: Range<Int>) throws -> [PortablePackageImportSource] {
            try range.map { ordinal in
                let url = tempDirectory.appendingPathComponent("tiny-\(ordinal).arw")
                var bytes = withUnsafeBytes(of: UInt64(ordinal).littleEndian) { Data($0) }
                bytes.append(Data(count: 4096))
                try bytes.write(to: url)
                return .init(url: url)
            }
        }
        let package = try PortableLibraryPackage.create(
            at: tempDirectory.appendingPathComponent("tiny.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        // Warm one-time ImageIO, Foundation and file-system initialization out of the baseline.
        _ = try package.importSources(try makeSources(0..<5), lease: lease)

        let sources = try makeSources(5..<(5 + count))
        let baseline = Self.physFootprint()
        let result = try package.importSources(sources, lease: lease)
        let growth = Self.physFootprint().saturatingSubtract(baseline)
        XCTAssertEqual(result.imported.count, count)
        XCTAssertTrue(result.failures.isEmpty)
        // Pre-fix growth was ~40 MiB; the live per-item state that remains is a few KiB per file.
        XCTAssertLessThan(growth, 16 << 20, "retained \(growth >> 20) MiB for \(count) files")
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

    /// KRMA-1140 — attributes the residual per-file slope to one importer stage. Each stage runs the
    /// same unique-path clone of a RAW (so path-keyed ImageIO state cannot be reused) in its own
    /// process: `KROMORA_IMPORT_MEMORY_PHASE` is `clone`, `metadata`, `fingerprint`, `begin`, `stage`,
    /// `commit`, or `full`. Prints the footprint after every tenth file and a least-squares slope over the
    /// second half, which excludes one-time warm-up.
    func testAttributeResidualFootprintByStage() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KROMORA_IMPORT_MEMORY"] == "1", "opt-in measurement")
        let directory = try XCTUnwrap(environment["KROMORA_IMPORT_MEMORY_DIR"])
        let phase = environment["KROMORA_IMPORT_MEMORY_PHASE"] ?? "full"
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directory, isDirectory: true), includingPropertiesForKeys: nil
        ).filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(urls.isEmpty, "no files in KROMORA_IMPORT_MEMORY_DIR")
        let count = Int(environment["KROMORA_IMPORT_MEMORY_COUNT"] ?? "") ?? 240

        let clones = tempDirectory.appendingPathComponent("clones", isDirectory: true)
        try FileManager.default.createDirectory(at: clones, withIntermediateDirectories: true)
        let package = try PortableLibraryPackage.create(
            at: tempDirectory.appendingPathComponent("attribute.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }

        func clone(_ ordinal: Int) throws -> URL {
            let source = urls[ordinal % urls.count]
            let destination = clones.appendingPathComponent("\(ordinal)-\(source.lastPathComponent)")
            XCTAssertEqual(clonefile(source.path, destination.path, 0), 0, "clone \(ordinal)")
            return destination
        }

        let samples = OSAllocatedUnfairLock(initialState: [(files: Int, bytes: UInt64)]())
        @Sendable func sample(_ n: Int) {
            guard n % 10 == 0 else { return }
            let footprint = Self.physFootprint()
            samples.withLock { $0.append((n, footprint)) }
            print("IMPORT_MEMORY phase=\(phase) files=\(n) footprint_MB=\(footprint >> 20)")
        }

        let baseline = Self.physFootprint()
        if phase == "full" {
            let sources = try (0..<count).map { PortablePackageImportSource(url: try clone($0)) }
            let committed = OSAllocatedUnfairLock(initialState: 0)
            _ = try package.importSources(
                sources, lease: lease, options: .init(duplicatePolicy: .importAnyway),
                committed: { _ in sample(committed.withLock { value -> Int in value += 1; return value }) }
            )
        } else {
            for ordinal in 0..<count {
                let url = try clone(ordinal)
                switch phase {
                case "clone":
                    break
                case "metadata":
                    _ = autoreleasepool { ImageMetadata.read(from: url) }
                case "fingerprint":
                    _ = autoreleasepool { PhotoSourceFingerprint.file(at: url) }
                case "stage":
                    var transaction = try package.beginTransaction(lease: lease)
                    _ = try transaction.stage(fileAt: url, to: "Assets/00/stage-\(ordinal)/Original/a.arw")
                    try transaction.abort()
                case "commit":
                    var transaction = try package.beginTransaction(lease: lease)
                    _ = try transaction.stage(fileAt: url, to: "Assets/00/commit-\(ordinal)/Original/a.arw")
                    try transaction.commit()
                case "begin":
                    var transaction = try package.beginTransaction(lease: lease)
                    try transaction.abort()
                default:
                    XCTFail("unknown phase \(phase)")
                    return
                }
                sample(ordinal + 1)
            }
        }
        if environment["KROMORA_IMPORT_MEMORY_VMMAP"] == "1" {
            // Set MallocStackLogging=1 as well to get allocation stacks for the retained class.
            let retained = environment["KROMORA_IMPORT_MEMORY_CLASS"] ?? "NSPathStore2"
            for arguments in [["/usr/bin/vmmap", "-summary"], ["/usr/bin/heap", "-s"],
                              ["/usr/bin/malloc_history", "-callTree", "-collapseRecursion", retained]] {
                print("IMPORT_MEMORY_TOOL \(arguments[0])\n\(Self.run(arguments))")
            }
        }
        let all = samples.withLock { $0 }
        let tail = all.suffix(max(2, all.count / 2))
        if let first = tail.first, let last = tail.last, last.files > first.files {
            let slope = (Double(last.bytes) - Double(first.bytes)) / Double(last.files - first.files)
            print("IMPORT_MEMORY phase=\(phase) baseline_MB=\(baseline >> 20) final_MB=\(Self.physFootprint() >> 20) tail_slope_KiB_per_file=\(Int(slope / 1024))")
        }
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 { self > other ? self - other : 0 }
}
