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
        let record = EditRecord(assetID: photo.assetID.description, document: editedDocument)
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
