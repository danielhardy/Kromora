import Foundation
import XCTest
@testable import LumoKit

@MainActor
final class ImportedPhotoDurabilityTests: TempDirectoryTestCase {

    func testURLImportsAppendCopyAndDeduplicate() throws {
        let sourceFolder = try Fixtures.makeTempDirectory("LumoImportSource")
        let libraryFolder = tempDirectory.appendingPathComponent(
            "managed-library", isDirectory: true
        )
        let first = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "first.png", in: sourceFolder
        )
        let second = try Fixtures.writeGradientPNG(
            width: 12, height: 20, named: "second.png", in: sourceFolder
        )
        let originalFirst = try Data(contentsOf: first)
        let defaults = makeTestUserDefaults()
        let collection = makeTestCollection(
            defaults: defaults, libraryFolderURL: libraryFolder
        )

        XCTAssertEqual(collection.addFromURLs([first]).count, 1)
        XCTAssertEqual(collection.addFromURLs([second]).count, 1)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(collection.addFromURLs([first]).count, 1)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(try Data(contentsOf: first), originalFirst)
        XCTAssertEqual(
            collection.items.filter { $0.url?.path.hasPrefix(libraryFolder.path + "/") == true }.count,
            2
        )
    }

    func testImportedCopyIsFoundAfterCollectionRebuild() async throws {
        let libraryFolder = tempDirectory.appendingPathComponent(
            "managed-library", isDirectory: true
        )
        let source = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "relaunch.png", in: tempDirectory
        )
        let defaults = makeTestUserDefaults()
        let first = makeTestCollection(
            defaults: defaults, libraryFolderURL: libraryFolder
        )
        _ = first.addFromURLs([source])

        let relaunched = makeTestCollection(
            defaults: defaults, libraryFolderURL: libraryFolder
        )
        XCTAssertTrue(relaunched.restoreLibrary())
        await relaunched.scanCompletion()

        XCTAssertEqual(relaunched.items.count, 1)
        XCTAssertEqual(relaunched.items[0].displayName, "relaunch")
        XCTAssertEqual(
            relaunched.items[0].url?.deletingLastPathComponent().standardizedFileURL,
            libraryFolder.standardizedFileURL
        )
    }

    func testEditsFollowImportedCopyAcrossRelaunch() async throws {
        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let container = makeInMemoryEditContainer()
        let defaults = UserDefaults(suiteName: "LumoImportedPhotoDurability-\(UUID().uuidString)")!
        let source = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "edited.png", in: tempDirectory
        )
        let first = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container),
            preferences: defaults,
            libraryFolderURL: libraryFolder
        )
        first.openImage(url: source)
        let firstDeadline = Date().addingTimeInterval(2)
        while first.sourceImage == nil && Date() < firstDeadline {
            await Task.yield()
        }
        first.updateDocument { $0.adjustments = [.exposure(ev: 0.8)] }
        _ = await first.flushPendingWrites()

        let relaunched = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container),
            preferences: defaults,
            libraryFolderURL: libraryFolder
        )
        await relaunched.collection.scanCompletion()
        XCTAssertEqual(relaunched.collection.items.count, 1)
        relaunched.openActiveCollectionImage()

        let deadline = Date().addingTimeInterval(2)
        while relaunched.document.adjustments.isEmpty && Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(relaunched.document.adjustments, [.exposure(ev: 0.8)])
    }

    func testDataImportsRemainSelectableAfterAnIncrementalAppend() throws {
        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let firstURL = try Fixtures.writeGradientPNG(width: 12, height: 8, named: "one.png", in: tempDirectory)
        let secondURL = try Fixtures.writeGradientPNG(width: 12, height: 8, named: "two.png", in: tempDirectory)
        let defaults = UserDefaults(suiteName: "LumoImportedPhotoDurability-\(UUID().uuidString)")!
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), preferences: defaults, libraryFolderURL: libraryFolder
        )
        viewModel.importPhotosData([
            (name: "one.png", data: try Data(contentsOf: firstURL)),
            (name: "two.png", data: try Data(contentsOf: secondURL))
        ])

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["one.png", "two.png"])
        viewModel.collection.setSelection(at: 1)
        viewModel.collection.setSelection(at: 0, additive: true)
        XCTAssertEqual(viewModel.collection.selectedIndices, [0, 1])
    }
}
