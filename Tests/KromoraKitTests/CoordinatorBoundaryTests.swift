import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class CoordinatorBoundaryTests: TempDirectoryTestCase {
    func testSourceImportPlanKeepsURLAndDataIdentityRulesTogether() throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 12, height: 8, named: "source-plan.png", in: tempDirectory
        )
        let data = try Data(contentsOf: imageURL)

        let filePlan = SourceImportPlan(name: "File", url: imageURL, data: nil)
        XCTAssertEqual(filePlan.assetID, .file(imageURL))
        XCTAssertEqual(filePlan.sourceReference.url, imageURL)
        XCTAssertEqual(filePlan.source.backing, .url(imageURL))

        let dataPlan = SourceImportPlan(
            name: "Photos", url: nil, data: data, assetID: .photos(localIdentifier: "photos-1"),
            dataFingerprint: "precomputed-digest", traceQuality: "photosImport"
        )
        XCTAssertEqual(dataPlan.assetID, .photos(localIdentifier: "photos-1"))
        XCTAssertEqual(dataPlan.sourceReference.url, nil)
        XCTAssertEqual(dataPlan.source.backing, .data(data))
        XCTAssertEqual(dataPlan.traceQuality, "photosImport")
    }

    func testCollectionProjectionSeparatesSelectionAndFilteringFromMutation() throws {
        let firstURL = try Fixtures.writeGradientPNG(
            width: 12, height: 8, named: "first.png", in: tempDirectory
        )
        let secondURL = try Fixtures.writeGradientPNG(
            width: 8, height: 12, named: "second.png", in: tempDirectory
        )
        let items = [
            ImageCollection.Item(url: firstURL, displayName: "First", imageData: nil),
            ImageCollection.Item(url: secondURL, displayName: "Second", imageData: nil),
        ]
        var selection = LibrarySelectionModel()
        selection.click(items[1].id, in: items.map(\.id))

        XCTAssertEqual(
            CollectionProjection.selectedIndices(items: items, selection: selection), [1]
        )
        XCTAssertEqual(
            CollectionProjection.filteredIndices(
                items: items, filter: LibraryFilter(flag: .all, rating: .any)
            ), [0, 1]
        )
    }

    func testPersistenceCoordinatorCoalescesSnapshotsAndPreservesFlushCompatibility() async throws {
        let package = makeEditPackageFixture()
        let store = package.store()
        let coordinator = EditPersistenceCoordinator(store: store)
        let sourceURL = tempDirectory.appendingPathComponent("photo.png")
        try package.register(sourceURL)
        let reference = EditSourceReference(assetID: .file(sourceURL), url: sourceURL)

        coordinator.enqueue(
            EditDocument(adjustments: [.exposure(ev: 0.1)]),
            for: reference,
            reportsStatus: false
        )
        coordinator.enqueue(
            EditDocument(adjustments: [.exposure(ev: 0.9)]),
            for: reference,
            reportsStatus: false
        )

        XCTAssertEqual(coordinator.pendingCount, 1)
        let flushResult = await coordinator.flush()
        XCTAssertEqual(flushResult, .success)
        XCTAssertEqual(coordinator.pendingCount, 0)
        let restored = await store.load(for: reference)
        XCTAssertEqual(restored.document.adjustments, [.exposure(ev: 0.9)])
        let writeCount = await store.writeCount
        XCTAssertEqual(writeCount, 1)
    }

    func testEditorDocumentCoordinatorOwnsHistoryAndClipboardWithoutAppViewModel() {
        let coordinator = EditorDocumentCoordinator()
        let original = EditDocument()
        var edited = original
        edited.adjustments = [.exposure(ev: 0.6)]

        coordinator.recordChange(from: original, to: edited)
        XCTAssertTrue(coordinator.canUndo)
        XCTAssertEqual(coordinator.undo(current: edited), original)
        XCTAssertTrue(coordinator.canRedo)
        XCTAssertEqual(coordinator.redo(current: original), edited)

        coordinator.copy(document: edited)
        XCTAssertEqual(
            coordinator.clipboard?.applying(to: original, destinationIsRAW: false), edited
        )
        XCTAssertTrue(coordinator.canPaste)
    }

    func testEditorDocumentCoordinatorKeepsPerPhotoSessionAndRevisionBoundaries() {
        let coordinator = EditorDocumentCoordinator()
        let assetID = PhotoAssetID.file(tempDirectory.appendingPathComponent("editor.png"))
        var document = EditDocument()
        document.adjustments = [.exposure(ev: 0.25)]

        let firstRevision = coordinator.commit(document: document, for: assetID)
        XCTAssertEqual(coordinator.session(for: assetID)?.document, document)
        XCTAssertEqual(coordinator.revision(for: assetID), firstRevision)

        var pasted = document
        pasted.adjustments = [.exposure(ev: 0.9)]
        XCTAssertTrue(coordinator.apply(pasted, to: assetID))
        XCTAssertEqual(coordinator.session(for: assetID)?.document, pasted)
        XCTAssertGreaterThan(coordinator.revision(for: assetID), firstRevision)

        coordinator.removeSession(for: assetID)
        XCTAssertNil(coordinator.session(for: assetID))
        XCTAssertEqual(coordinator.revision(for: assetID), 0)
    }

    func testComparisonFramePolicyKeepsWhiteBalanceOnTheCurrentBaseline() {
        var whiteBalanceOnly = EditDocument()
        whiteBalanceOnly.rawDevelop.neutralTemperature = 5600
        whiteBalanceOnly.rawDevelop.neutralTint = 8
        XCTAssertFalse(
            ComparisonFramePolicy.changesBaseline(from: EditDocument(), to: whiteBalanceOnly))

        var developChanged = whiteBalanceOnly
        developChanged.rawDevelop.exposure = 0.5
        XCTAssertTrue(
            ComparisonFramePolicy.changesBaseline(from: whiteBalanceOnly, to: developChanged))
    }
}
