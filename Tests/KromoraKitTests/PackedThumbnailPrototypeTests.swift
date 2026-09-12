import Foundation
import XCTest

final class PackedThumbnailPrototypeTests: XCTestCase {

    func testLookupHandlesMissingDuplicateAndStaleEntries() throws {
        let root = try Fixtures.makeTempDirectory("PackedThumbnailEdges")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PackedThumbnailStore(at: root.appendingPathComponent("packed"))
        try store.append(records: [
            .init(key: "00-live", data: Data("old".utf8)),
            .init(key: "01-deleted", data: Data("deleted".utf8)),
        ])

        XCTAssertEqual(try store.lookup("00-live"), .found(Data("old".utf8)))
        XCTAssertEqual(try store.lookup("ff-never-seen"), .missing)

        // A replacement is a deliberate duplicate physical entry. The newest index entry wins,
        // while the old bytes remain reclaimable by compaction.
        try store.append(.init(key: "00-live", data: Data("new".utf8)))
        XCTAssertEqual(try store.lookup("00-live"), .found(Data("new".utf8)))
        XCTAssertEqual(store.liveEntryCount, 2)

        try store.remove(keys: ["01-deleted"])
        XCTAssertEqual(try store.lookup("01-deleted"), .missing)
        try store.injectStaleEntryForTesting(key: "02-stale")
        XCTAssertEqual(try store.lookup("02-stale"), .stale)

        let scan = try store.coldScan()
        XCTAssertEqual(scan.indexedEntries, 2)
        XCTAssertEqual(scan.validEntries, 1)
        XCTAssertEqual(scan.staleEntries, 1)
    }

    func testCompactionReclaimsStaleAndDeletedBytesWithoutDanglingOffsets() throws {
        let root = try Fixtures.makeTempDirectory("PackedThumbnailCompaction")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PackedThumbnailStore(at: root.appendingPathComponent("packed"))
        let live = Data(repeating: 0x11, count: 17)
        let replacement = Data(repeating: 0x22, count: 31)
        try store.append(records: [
            .init(key: "10-first", data: live),
            .init(key: "20-second", data: live),
            .init(key: "30-third", data: live),
        ])
        try store.append(.init(key: "10-first", data: replacement))
        try store.remove(keys: ["20-second"])
        try store.injectStaleEntryForTesting(key: "40-corrupt")

        let before = store.physicalByteCount
        let result = try store.compact()

        XCTAssertEqual(result.indexedEntriesBefore, 3)
        XCTAssertEqual(result.indexedEntriesAfter, 2)
        XCTAssertEqual(result.staleEntriesRemoved, 1)
        XCTAssertLessThan(result.bytesAfter, before)
        XCTAssertEqual(try store.lookup("10-first"), .found(replacement))
        XCTAssertEqual(try store.lookup("30-third"), .found(live))
        XCTAssertEqual(try store.lookup("20-second"), .missing)
        XCTAssertEqual(try store.lookup("40-corrupt"), .missing)

        let after = try store.coldScan()
        XCTAssertEqual(after, .init(indexedEntries: 2, validEntries: 2, staleEntries: 0))
    }

    func testPerFileComparatorReclaimsDeletedThumbnailImmediately() throws {
        let root = try Fixtures.makeTempDirectory("PerFileThumbnail")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PerFileThumbnailStore(at: root)
        try store.append(records: [
            .init(key: "00-one", data: Data("one".utf8)),
            .init(key: "01-two", data: Data("two".utf8)),
        ])
        XCTAssertEqual(try store.coldScan(), 2)
        XCTAssertEqual(try store.lookup("00-one"), Data("one".utf8))
        try store.remove(keys: ["00-one"])
        XCTAssertNil(try store.lookup("00-one"))
        XCTAssertEqual(try store.coldScan(), 1)
    }
}

final class PackedThumbnailPerformanceTests: XCTestCase {

    private struct ScaleReport: Codable {
        let assetCount: Int
        let materializedThumbnailCount: Int
        let currentFileCount: Int
        let packedFileCount: Int
        let metricsMilliseconds: [String: Double]
        let metricsMicroseconds: [String: Double]
        let packedBytesBeforeCompaction: Int
        let packedBytesAfterCompaction: Int
        let currentBytesAfterDeletion: Int
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let benchmark: String
        let sampleCount: Int
        let regenerationDefinition: String
        let deletionDefinition: String
        let scales: [String: ScaleReport]
    }

    func testPackedByShardComparisonAtAllSupportedScales() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_PACKED_THUMBNAIL_BENCHMARK"] != nil,
            "set KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 to run packed-thumbnail benchmarks"
        )

        let parent = try Fixtures.makeTempDirectory("PackedThumbnailBenchmark")
        defer { try? FileManager.default.removeItem(at: parent) }
        var reports: [String: ScaleReport] = [:]

        for scale in SyntheticLibraryGenerator.Scale.allCases {
            print("PACKED_THUMBNAIL_SCALE_BEGIN items=\(scale.assetCount)")
            let library = try await SyntheticLibraryGenerator.generate(
                scale: scale,
                seed: SyntheticLibraryGenerator.defaultSeed,
                in: parent,
                yieldEvery: 256
            )
            defer { try? library.cleanup() }

            let thumbnailData = try XCTUnwrap(Data(contentsOf: library.assets[0].url))
            let records = library.assets.map {
                PackedThumbnailStore.Record(key: key(for: $0.index), data: thumbnailData)
            }
            let regenerationRecords = library.assets.filter(\.needsThumbnailGeneration).map {
                PackedThumbnailStore.Record(key: key(for: $0.index), data: thumbnailData)
            }
            let deletedKeys = stride(from: 0, to: scale.assetCount, by: 10).map {
                key(for: $0)
            }

            let currentRoot = parent.appendingPathComponent("current-\(scale.assetCount)")
            let packedRoot = parent.appendingPathComponent("packed-\(scale.assetCount)")
            let current = try PerFileThumbnailStore(at: currentRoot)
            let packed = try PackedThumbnailStore(at: packedRoot)
            try current.append(records: records)
            try packed.append(records: records)
            let currentFileCount = current.physicalFileCount
            let packedFileCount = packed.physicalFileCount

            let currentScanMilliseconds = try timed {
                let reopened = try PerFileThumbnailStore(at: currentRoot)
                XCTAssertEqual(try reopened.coldScan(), scale.assetCount)
            }
            let packedScanMilliseconds = try timed {
                let reopened = try PackedThumbnailStore(at: packedRoot)
                let scan = try reopened.coldScan()
                XCTAssertEqual(scan, .init(
                    indexedEntries: scale.assetCount,
                    validEntries: scale.assetCount,
                    staleEntries: 0
                ))
            }

            let lookupIndices = stride(from: 0, to: scale.assetCount, by: max(1, scale.assetCount / 128))
                .map { $0 }
            let currentLookupMicroseconds = try averageLookupMicroseconds(
                keys: lookupIndices.map { key(for: $0) }, lookup: current.lookup
            )
            let packedLookupMicroseconds = try averageLookupMicroseconds(
                keys: lookupIndices.map { key(for: $0) }, lookup: { key in
                    let result = try packed.lookup(key)
                    guard case .found(let data) = result else {
                        XCTFail("packed lookup did not return a thumbnail")
                        return nil
                    }
                    return data
                }
            )

            let currentRegenerationMilliseconds = try timed {
                try current.append(records: regenerationRecords)
            }
            let packedRegenerationMilliseconds = try timed {
                try packed.append(records: regenerationRecords)
            }

            try current.remove(keys: deletedKeys)
            try packed.remove(keys: deletedKeys)
            let packedBytesBeforeCompaction = packed.physicalByteCount
            let currentCompactionMilliseconds = try timed {
                XCTAssertEqual(try current.coldScan(), scale.assetCount - deletedKeys.count)
            }
            let packedCompactionMilliseconds = try timed {
                _ = try packed.compact()
            }

            let packedAfterScan = try packed.coldScan()
            XCTAssertEqual(packedAfterScan.validEntries, scale.assetCount - deletedKeys.count)
            XCTAssertEqual(packedAfterScan.staleEntries, 0)
            XCTAssertEqual(try current.coldScan(), scale.assetCount - deletedKeys.count)

            reports[String(scale.assetCount)] = ScaleReport(
                assetCount: scale.assetCount,
                materializedThumbnailCount: records.count,
                currentFileCount: currentFileCount,
                packedFileCount: packedFileCount,
                metricsMilliseconds: [
                    "cold-scan-current": currentScanMilliseconds,
                    "cold-scan-packed": packedScanMilliseconds,
                    "regeneration-current": currentRegenerationMilliseconds,
                    "regeneration-packed": packedRegenerationMilliseconds,
                    "compaction-current": currentCompactionMilliseconds,
                    "compaction-packed": packedCompactionMilliseconds,
                ],
                metricsMicroseconds: [
                    "lookup-current": currentLookupMicroseconds,
                    "lookup-packed": packedLookupMicroseconds,
                ],
                packedBytesBeforeCompaction: packedBytesBeforeCompaction,
                packedBytesAfterCompaction: packed.physicalByteCount,
                currentBytesAfterDeletion: current.physicalByteCount
            )
            print("PACKED_THUMBNAIL_SCALE_END items=\(scale.assetCount)")
        }

        let report = Report(
            schemaVersion: 1,
            benchmark: "packed-thumbnail-by-shard-vs-per-file",
            sampleCount: 1,
            regenerationDefinition: "all synthetic assets flagged needsThumbnailGeneration",
            deletionDefinition: "every tenth asset, deleted before compaction measurement",
            scales: reports
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print("PACKED_THUMBNAIL_REPORT_BEGIN")
        print(String(decoding: data, as: UTF8.self))
        print("PACKED_THUMBNAIL_REPORT_END")
        if let path = ProcessInfo.processInfo.environment["KROMORA_PACKED_THUMBNAIL_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private func key(for index: Int) -> String {
        String(format: "%02x%030x", index % 256, index)
    }

    private func timed(_ operation: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func averageLookupMicroseconds(
        keys: [String],
        lookup: (String) throws -> Data?
    ) throws -> Double {
        let repetitions = 8
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<repetitions {
            for key in keys { XCTAssertNotNil(try lookup(key)) }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000
        return elapsed / Double(keys.count * repetitions)
    }
}

private extension PackedThumbnailStore.LookupResult {
    var dataValue: Data? {
        guard case .found(let data) = self else { return nil }
        return data
    }
}
