import Foundation
import SwiftData
import XCTest

@testable import LumoKit

final class EditDocumentStoreTests: TempDirectoryTestCase {

    private func makeStore() -> EditDocumentStore {
        makeInMemoryEditStore()
    }

    private func source(named name: String = "photo.jpg") -> EditSourceReference {
        let url = tempDirectory.appendingPathComponent(name)
        return EditSourceReference(assetID: .file(url), url: url)
    }

    private var editedDocument: EditDocument {
        EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.75),
            adjustments: [.exposure(ev: 0.4)],
            lut: .none
        )
    }

    func testRoundTripUsesInMemorySwiftDataStoreAndLeavesSourceUntouched() async throws {
        let store = makeStore()
        let photo = source()
        let original = Data("source bytes stay source bytes".utf8)
        try original.write(to: try XCTUnwrap(photo.url))

        try await store.save(editedDocument, for: photo)
        let result = await store.load(for: photo)

        XCTAssertTrue(result.found)
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(photo.url)), original)
    }

    func testEachPhotoIsAnIndependentSwiftDataRecord() async throws {
        let store = makeStore()
        let first = source(named: "first.jpg")
        let second = source(named: "second.jpg")
        let firstDocument = EditDocument(adjustments: [.exposure(ev: 0.1)])
        let secondDocument = EditDocument(adjustments: [.exposure(ev: 0.9)])

        try await store.save(firstDocument, for: first)
        try await store.save(secondDocument, for: second)
        try await store.save(EditDocument(adjustments: [.exposure(ev: 0.2)]), for: first)

        let restoredFirst = await store.load(for: first)
        let restoredSecond = await store.load(for: second)
        let writeCount = await store.writeCount
        XCTAssertEqual(restoredFirst.document.adjustments, [.exposure(ev: 0.2)])
        XCTAssertEqual(restoredSecond.document, secondDocument)
        XCTAssertEqual(writeCount, 3)
    }

    func testMovedFileRelinksByBookmarkAndRekeysTheRecord() async throws {
        let container = makeInMemoryEditContainer()
        let store = EditDocumentStore(modelContainer: container)
        let oldURL = tempDirectory.appendingPathComponent("old.jpg")
        let newURL = tempDirectory.appendingPathComponent("new.jpg")
        try Data("photo".utf8).write(to: oldURL)
        let oldSource = EditSourceReference(assetID: .file(oldURL), url: oldURL)
        try await store.save(editedDocument, for: oldSource)
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let result = await store.load(
            for: EditSourceReference(assetID: .file(newURL), url: newURL)
        )
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(result.status, .relinked)

        let relaunch = EditDocumentStore(modelContainer: container)
        let relaunched = await relaunch.load(
            for: EditSourceReference(assetID: .file(newURL), url: newURL)
        )
        XCTAssertEqual(relaunched.document, editedDocument)
    }

    func testPathRelinkUsesPredicateBeforeBookmarkFallbackScan() async throws {
        let store = makeStore()
        let url = tempDirectory.appendingPathComponent("path-match.jpg")
        let savedSource = EditSourceReference(
            assetID: .photos(localIdentifier: "saved-under-a-different-key"), url: url)
        try await store.save(editedDocument, for: savedSource)

        let result = await store.load(
            for: EditSourceReference(assetID: .file(url), url: url))

        XCTAssertTrue(result.found)
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(result.status, .relinked)
        let fallbackScanCount = await store.relinkFallbackScanCount
        XCTAssertEqual(
            fallbackScanCount,
            0,
            "an exact source-path match must be resolved by the predicate phase"
        )
    }

    func testRelinkOntoOccupiedAssetIDKeepsNewestRecordAndSubsequentLoadsSucceed() async throws {
        let container = makeInMemoryEditContainer()
        let store = EditDocumentStore(modelContainer: container)
        let oldURL = tempDirectory.appendingPathComponent("relink-old.jpg")
        let occupiedURL = tempDirectory.appendingPathComponent("relink-occupied.jpg")
        try Data("old source".utf8).write(to: oldURL)

        let occupiedDocument = EditDocument(adjustments: [.exposure(ev: 0.1)])
        let relinkedDocument = EditDocument(adjustments: [.exposure(ev: 0.9)])
        let occupiedSource = EditSourceReference(
            assetID: .file(occupiedURL), url: occupiedURL)
        let oldSource = EditSourceReference(assetID: .file(oldURL), url: oldURL)

        try await store.save(occupiedDocument, for: occupiedSource)
        try await store.save(relinkedDocument, for: oldSource)

        // The direct key is occupied by an older/stale record, while the URL identifies the
        // record being reopened. The relinked record is the newest observation and wins.
        let result = await store.load(
            for: EditSourceReference(assetID: occupiedSource.assetID, url: oldURL))
        XCTAssertEqual(result.document, relinkedDocument)
        XCTAssertEqual(result.status, .relinked)

        let sameStoreRetry = await store.load(
            for: EditSourceReference(assetID: occupiedSource.assetID, url: oldURL))
        XCTAssertEqual(sameStoreRetry.document, relinkedDocument)
        XCTAssertTrue(sameStoreRetry.found)

        let relaunched = EditDocumentStore(modelContainer: container)
        let persistedRetry = await relaunched.load(
            for: EditSourceReference(assetID: occupiedSource.assetID, url: oldURL))
        XCTAssertEqual(persistedRetry.document, relinkedDocument)
        XCTAssertTrue(persistedRetry.found)
    }

    func testRelinkCollisionRollsBackOnPersistFailureSoRetrySucceeds() async throws {
        let container = makeInMemoryEditContainer()
        let setupStore = EditDocumentStore(modelContainer: container)
        let oldURL = tempDirectory.appendingPathComponent("collision-fail-old.jpg")
        let occupiedURL = tempDirectory.appendingPathComponent("collision-fail-occupied.jpg")
        try Data("old source".utf8).write(to: oldURL)

        let occupiedDocument = EditDocument(adjustments: [.exposure(ev: 0.1)])
        let relinkedDocument = EditDocument(adjustments: [.exposure(ev: 0.9)])
        let occupiedSource = EditSourceReference(assetID: .file(occupiedURL), url: occupiedURL)
        let oldSource = EditSourceReference(assetID: .file(oldURL), url: oldURL)

        try await setupStore.save(occupiedDocument, for: occupiedSource)
        try await setupStore.save(relinkedDocument, for: oldSource)

        // A persist failure mid-relink must roll back both the delete of the occupant and the
        // rekey of the winner, so a retry sees the same collision (not a half-applied state)
        // and resolves it cleanly.
        let failingStore = EditDocumentStore(modelContainer: container, failuresBeforeSuccess: 1)
        let failedLoad = await failingStore.load(
            for: EditSourceReference(assetID: occupiedSource.assetID, url: oldURL))
        guard case .writeFailure = failedLoad.status else {
            return XCTFail(
                "expected the injected failure to surface as writeFailure, got \(failedLoad.status)"
            )
        }
        let attemptsAfterFailure = await failingStore.saveAttemptCount
        let writesAfterFailure = await failingStore.writeCount
        XCTAssertEqual(attemptsAfterFailure, 1, "expected exactly one persist attempt so far")
        XCTAssertEqual(writesAfterFailure, 0, "the injected failure must not have written")

        let retry = await failingStore.load(
            for: EditSourceReference(assetID: occupiedSource.assetID, url: oldURL))
        XCTAssertTrue(retry.found)
        XCTAssertEqual(retry.document, relinkedDocument)
        // A load reports the outcome of this relink attempt. The prior failed attempt remains a
        // store-level diagnostic, but it must not overwrite this successful retry's `.relinked`
        // result.
        XCTAssertEqual(retry.status, .relinked)

        let relaunched = EditDocumentStore(modelContainer: container)
        let persistedRetry = await relaunched.load(
            for: EditSourceReference(assetID: occupiedSource.assetID, url: oldURL))
        XCTAssertEqual(persistedRetry.document, relinkedDocument)
        XCTAssertTrue(persistedRetry.found)
    }

    func testPlainRelinkRetryReportsItsSuccessfulOutcomeAfterPersistFailure() async throws {
        let container = makeInMemoryEditContainer()
        let setupStore = EditDocumentStore(modelContainer: container)
        let oldURL = tempDirectory.appendingPathComponent("plain-retry-old.jpg")
        let newURL = tempDirectory.appendingPathComponent("plain-retry-new.jpg")
        try Data("source".utf8).write(to: oldURL)

        let document = EditDocument(adjustments: [.exposure(ev: 0.6)])
        let oldSource = EditSourceReference(assetID: .file(oldURL), url: oldURL)
        try await setupStore.save(document, for: oldSource)
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let failingStore = EditDocumentStore(modelContainer: container, failuresBeforeSuccess: 1)
        let newSource = EditSourceReference(assetID: .file(newURL), url: newURL)
        let failedLoad = await failingStore.load(for: newSource)
        guard case .writeFailure = failedLoad.status else {
            return XCTFail(
                "expected the injected failure to surface as writeFailure, got \(failedLoad.status)"
            )
        }

        let retry = await failingStore.load(for: newSource)
        XCTAssertTrue(retry.found)
        XCTAssertEqual(retry.document, document)
        XCTAssertEqual(retry.status, .relinked)
    }

    func testPersistenceIORunsOffTheMainActor() async throws {
        let store = makeStore()
        _ = await store.load(for: source())
        let lastIOWasMainThread = await store.lastIOWasMainThread
        XCTAssertFalse(lastIOWasMainThread)
    }

    func testFailingStoreCanRetryTheCompleteSnapshot() async throws {
        let container = makeInMemoryEditContainer()
        let store = makeInMemoryEditStore(container: container, failuresBeforeSuccess: 1)
        let photo = source()

        do {
            try await store.save(editedDocument, for: photo)
            XCTFail("the injected failure should be surfaced")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("injected persistence failure"))
        }
        let failedWriteCount = await store.writeCount
        let failedAttemptCount = await store.saveAttemptCount
        XCTAssertEqual(failedWriteCount, 0)
        XCTAssertEqual(failedAttemptCount, 1)

        try await store.save(editedDocument, for: photo)
        let restored = EditDocumentStore(modelContainer: container)
        let result = await restored.load(for: photo)
        XCTAssertEqual(result.document, editedDocument)
    }

    func testCorruptRecordSurfacesActionableStatusWithoutInventingEdits() async throws {
        let schema = Schema([EditRecord.self])
        let configuration = ModelConfiguration(
            "LumoKitTests.CorruptEditStore",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let photo = source()
        let context = ModelContext(container)
        let record = try EditRecord(assetID: photo.assetID.description, document: editedDocument)
        record.documentData = Data("partially written".utf8)
        context.insert(record)
        try context.save()

        let store = EditDocumentStore(modelContainer: container)
        let result = await store.load(for: photo)

        XCTAssertTrue(result.found)
        XCTAssertTrue(result.document.isIdentity)
        guard case .corrupt(let detail) = result.status else {
            return XCTFail("expected an undecodable record to be reported as corrupt")
        }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertTrue(result.status.isActionable)
        XCTAssertTrue(result.status.message?.contains("neutral edits") == true)
        let storeStatus = await store.status
        XCTAssertEqual(storeStatus, result.status)
    }

    func testLoadStatusBelongsToThePhotoBeingLoaded() async throws {
        let schema = Schema([EditRecord.self])
        let configuration = ModelConfiguration(
            "LumoKitTests.PerPhotoLoadStatus",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let corruptPhoto = source(named: "corrupt.jpg")
        let healthyPhoto = source(named: "healthy.jpg")
        let context = ModelContext(container)
        let corruptRecord = try EditRecord(
            assetID: corruptPhoto.assetID.description, document: editedDocument
        )
        corruptRecord.documentData = Data("partially written".utf8)
        context.insert(corruptRecord)
        try context.save()

        let store = EditDocumentStore(modelContainer: container)
        try await store.save(editedDocument, for: healthyPhoto)

        let corruptResult = await store.load(for: corruptPhoto)
        let healthyResult = await store.load(for: healthyPhoto)
        let corruptRetry = await store.load(for: corruptPhoto)

        guard case .corrupt = corruptResult.status else {
            return XCTFail("the corrupt photo must report its own corrupt status")
        }
        XCTAssertEqual(healthyResult.status, .ready)
        guard case .corrupt = corruptRetry.status else {
            return XCTFail("loading the corrupt photo again must still report corrupt")
        }
        guard case .corrupt = await store.worstActionableStatus else {
            return XCTFail("the store-level worst actionable status should retain the corrupt warning")
        }
    }

    func testEncodingFailureIsReportedWithoutPersistingAnEmptyRecord() async throws {
        let store = makeStore()
        let photo = source()
        let unencodableDocument = EditDocument(adjustments: [.exposure(ev: .nan)])

        do {
            try await store.save(unencodableDocument, for: photo)
            XCTFail("a non-conforming floating-point value must not be saved")
        } catch {
            XCTAssertTrue(error is EncodingError)
        }

        let status = await store.status
        guard case .writeFailure(let detail) = status else {
            return XCTFail("expected an encoding failure status, got \(status)")
        }
        XCTAssertFalse(detail.isEmpty)
        let writeCount = await store.writeCount
        let saveAttemptCount = await store.saveAttemptCount
        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(saveAttemptCount, 0)

        let result = await store.load(for: photo)
        XCTAssertFalse(result.found)
        XCTAssertEqual(result.status, .ready)
    }

    func testConcurrentSavesSerializeModelContextAccess() async throws {
        let store = makeStore()
        let entries = (0..<8).map { index in
            (
                source: source(named: "concurrent-\(index).jpg"),
                document: EditDocument(adjustments: [.exposure(ev: Double(index) / 10)])
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for entry in entries {
                group.addTask {
                    try await store.save(entry.document, for: entry.source)
                }
            }
            try await group.waitForAll()
        }

        for entry in entries {
            let result = await store.load(for: entry.source)
            XCTAssertTrue(result.found)
            XCTAssertEqual(result.document, entry.document)
        }
        let saveAttemptCount = await store.saveAttemptCount
        let writeCount = await store.writeCount
        XCTAssertEqual(saveAttemptCount, entries.count)
        XCTAssertEqual(writeCount, entries.count)
    }

    func testDefaultStoreUsesEditStoreStore() {
        XCTAssertEqual(EditDocumentStore.defaultFileURL.lastPathComponent, "EditStore.store")
    }

    func testPersistentStoreExposesItsOnDiskFileURL() async throws {
        let fileURL = tempDirectory.appendingPathComponent("EditStore.store")
        let store = try EditDocumentStore.makePersistentStore(fileURL: fileURL)
        let exposedURL = await store.onDiskFileURL

        XCTAssertEqual(exposedURL, fileURL)
    }

    func testStoreThatFallsBackToMemoryDoesNotExposeAnOnDiskFileURL() async throws {
        let parentFile = tempDirectory.appendingPathComponent("not-a-directory")
        try Data("not a directory".utf8).write(to: parentFile)
        let requestedURL = parentFile.appendingPathComponent("EditStore.store")
        let store = EditDocumentStore(fileURL: requestedURL)
        let exposedURL = await store.onDiskFileURL

        XCTAssertNil(exposedURL)
    }
}
