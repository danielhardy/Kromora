import Foundation
import XCTest

@testable import KromoraKit

final class LaunchHintsTests: XCTestCase {
    func testHintsAreVersionedDeduplicatedAndBounded() {
        let libraryID = UUID()
        let ids = (0..<80).map { _ in PortablePhotoAssetID() }
        let hints = LaunchHints(
            libraryID: libraryID, activeAssetID: ids[0], visibleAssetIDs: ids + [ids[0]]
        )

        XCTAssertEqual(hints.schemaVersion, LaunchHints.currentSchemaVersion)
        XCTAssertEqual(hints.visibleAssetIDs.count, LaunchHintReadPolicy.maximumHintedIDs)
        XCTAssertEqual(Set(hints.visibleAssetIDs).count, hints.visibleAssetIDs.count)
        XCTAssertTrue(hints.isValid)
        XCTAssertEqual(LaunchHintReadPolicy.maxConcurrentReads, 2)
        XCTAssertLessThanOrEqual(
            LaunchHintReadPolicy.maximumHintedIDs, LaunchHints.maximumVisibleIDs
        )

        var metrics = LaunchHydrationMetrics()
        XCTAssertFalse(metrics.hasRequiredMeasurements)
        metrics.validation = "valid"
        metrics.usefulHits = 1
        metrics.superseded = 2
        metrics.bytesRead = 1_024
        metrics.readCount = 2
        metrics.timeToVisibleWindowMilliseconds = 18
        metrics.timeToFirstIndexPageMilliseconds = 42
        XCTAssertTrue(metrics.hasRequiredMeasurements)
        XCTAssertEqual(metrics.usefulHits, 1)
        XCTAssertEqual(metrics.superseded, 2)
        XCTAssertEqual(metrics.bytesRead, 1_024)
        XCTAssertEqual(metrics.readCount, 2)
        XCTAssertEqual(metrics.timeToVisibleWindowMilliseconds, 18)
        XCTAssertEqual(metrics.timeToFirstIndexPageMilliseconds, 42)
    }

    func testStoreAtomicallyPersistsAndRejectsDifferentLibraryAndCorruptRecords() async throws {
        let root = try Fixtures.makeTempDirectory("LaunchHints")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("LaunchHints.json")
        let store = LaunchHintsStore(url: url)
        let libraryID = UUID()
        let hints = LaunchHints(
            libraryID: libraryID, activeAssetID: nil, visibleAssetIDs: [PortablePhotoAssetID()]
        )

        await store.scheduleWrite(hints)
        await store.flush()

        let loaded = await store.load(for: libraryID)
        let otherLibrary = await store.load(for: UUID())
        XCTAssertEqual(loaded, .valid(hints))
        XCTAssertEqual(otherLibrary, .invalid)
        let backupValues = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(backupValues.isExcludedFromBackup, true)
        try Data("{".utf8).write(to: url, options: .atomic)
        let corrupt = await store.load(for: libraryID)
        XCTAssertEqual(corrupt, .invalid)
    }

    func testOversizedAndUnsupportedRecordsAreIgnored() throws {
        let ids = (0..<65).map { _ in PortablePhotoAssetID().raw }
        let oversized: [String: Any] = [
            "schemaVersion": LaunchHints.currentSchemaVersion,
            "libraryID": UUID().uuidString,
            "activeAssetID": NSNull(),
            "visibleAssetIDs": ids.map { ["uuid": $0] },
        ]
        let oversizedHints = try JSONDecoder().decode(
            LaunchHints.self, from: JSONSerialization.data(withJSONObject: oversized)
        )
        XCTAssertFalse(oversizedHints.isValid)

        let unsupported: [String: Any] = [
            "schemaVersion": LaunchHints.currentSchemaVersion + 1,
            "libraryID": UUID().uuidString,
            "activeAssetID": NSNull(),
            "visibleAssetIDs": [],
        ]
        let unsupportedHints = try JSONDecoder().decode(
            LaunchHints.self, from: JSONSerialization.data(withJSONObject: unsupported)
        )
        XCTAssertFalse(unsupportedHints.isValid)
    }
}
