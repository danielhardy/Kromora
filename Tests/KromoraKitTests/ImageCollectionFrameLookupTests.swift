import XCTest
@testable import KromoraKit

@MainActor
final class ImageCollectionFrameLookupTests: TempDirectoryTestCase {
    func testApplyingStoredFramesRecordsOneLaunchHintEntryPerFrameLookup() async throws {
        let ledger = FrameLookupLedger()
        let collection = ImageCollection(frameLookupLedger: ledger)
        let asset = PhotoAsset(data: Data("collection-frame-source".utf8), filename: "photo.jpg")
        let identity = asset.source.portableIdentity
        collection.loadPortableAssets([asset])
        let itemID = try XCTUnwrap(collection.items.first?.id)

        collection.applyLaunchFrames([itemID: (
            identity,
            ThumbnailFrameStore.StoredFrames(
                original: nil, edited: nil,
                originalCorrupt: true, editedCorrupt: false
            )
        )])
        try await waitForLedgerCount(2, ledger: ledger)
        var records = await ledger.snapshot()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.surface), [.launchHint, .launchHint])
        XCTAssertEqual(records.map { $0.outcome.label }.sorted(), ["corrupt", "missingFile"])

        collection.applyLaunchFrames([itemID: (
            identity,
            ThumbnailFrameStore.StoredFrames(
                original: nil, edited: nil,
                originalCorrupt: false, editedCorrupt: true
            )
        )])
        try await waitForLedgerCount(4, ledger: ledger)
        records = await ledger.snapshot()
        XCTAssertEqual(records.count, 4)
        XCTAssertEqual(records.suffix(2).map(\.surface), [.launchHint, .launchHint])
        XCTAssertEqual(
            records.suffix(2).map { $0.outcome.label }.sorted(), ["corrupt", "missingFile"]
        )
    }

    private func waitForLedgerCount(_ count: Int, ledger: FrameLookupLedger) async throws {
        let deadline = Date().addingTimeInterval(3)
        while await ledger.snapshot().count < count {
            if Date() > deadline { return XCTFail("timed out waiting for ledger entries") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
