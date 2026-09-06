import Foundation
import XCTest

@testable import LumoKit

final class EditDocumentStoreTests: TempDirectoryTestCase {

    private func makeStore(named name: String = "EditStore.store") -> (EditDocumentStore, URL) {
        let url = tempDirectory.appendingPathComponent(name)
        return (EditDocumentStore(fileURL: url), url)
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

    func testRoundTripUsesSwiftDataStoreAndLeavesSourceUntouched() async throws {
        let (store, fileURL) = makeStore()
        let photo = source()
        let original = Data("source bytes stay source bytes".utf8)
        try original.write(to: try XCTUnwrap(photo.url))

        try await store.save(editedDocument, for: photo)
        let result = await store.load(for: photo)

        XCTAssertTrue(result.found)
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(photo.url)), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(
            String(decoding: try Data(contentsOf: fileURL).prefix(15), as: UTF8.self)
                .hasPrefix("SQLite format 3")
        )
    }

    func testEachPhotoIsAnIndependentSwiftDataRecord() async throws {
        let (store, _) = makeStore()
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
        let (store, _) = makeStore()
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

        let relaunch = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("EditStore.store"))
        let relaunched = await relaunch.load(
            for: EditSourceReference(assetID: .file(newURL), url: newURL)
        )
        XCTAssertEqual(relaunched.document, editedDocument)
    }

    func testPersistenceIORunsOffTheMainActor() async throws {
        let (store, _) = makeStore()
        _ = await store.load(for: source())
        let lastIOWasMainThread = await store.lastIOWasMainThread
        XCTAssertFalse(lastIOWasMainThread)
    }

    func testFailingStoreCanRetryTheCompleteSnapshot() async throws {
        let url = tempDirectory.appendingPathComponent("failing.store")
        let store = EditDocumentStore(fileURL: url, failuresBeforeSuccess: 1)
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
        let restored = EditDocumentStore(fileURL: url)
        let result = await restored.load(for: photo)
        XCTAssertEqual(result.document, editedDocument)
    }

    func testDefaultStoreUsesEditStoreStore() {
        XCTAssertEqual(EditDocumentStore.defaultFileURL.lastPathComponent, "EditStore.store")
    }
}
