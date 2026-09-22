import Foundation
import XCTest
@testable import KromoraKit

@MainActor
final class ImportedPhotoDurabilityTests: TempDirectoryTestCase {

    func testURLImportsAppendCopyAndDeduplicate() throws {
        let sourceFolder = try Fixtures.makeTempDirectory("KromoraImportSource")
        let packageURL = tempDirectory.appendingPathComponent(
            "Library.kromoralibrary", isDirectory: true
        )
        let first = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "first.png", in: sourceFolder
        )
        let second = try Fixtures.writeGradientPNG(
            width: 12, height: 20, named: "second.png", in: sourceFolder
        )
        let originalFirst = try Data(contentsOf: first)
        let session = try PortableLibrarySession(at: packageURL)
        let firstResult = try session.importURLs([first])
        let secondResult = try session.importURLs([second])
        let duplicateResult = try session.importURLs([first])

        XCTAssertEqual(firstResult.imported.count, 1)
        XCTAssertEqual(secondResult.imported.count, 1)
        XCTAssertEqual(session.assetCount, 2)
        XCTAssertEqual(duplicateResult.duplicates.count, 1)
        XCTAssertEqual(session.assetCount, 2)
        XCTAssertEqual(try Data(contentsOf: first), originalFirst)
        let assets = try session.materializedAssets()
        XCTAssertEqual(assets.count, 2)
        XCTAssertTrue(assets.allSatisfy { $0.url?.path.hasPrefix(packageURL.path + "/") == true })
    }

    func testImportedCopyIsFoundAfterCollectionRebuild() async throws {
        let packageURL = tempDirectory.appendingPathComponent(
            "Library.kromoralibrary", isDirectory: true
        )
        let source = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "relaunch.png", in: tempDirectory
        )

        do {
            let first = try PortableLibrarySession(at: packageURL)
            _ = try first.importURLs([source])
            try first.lease.release()
        }

        let relaunched = try PortableLibrarySession(at: packageURL)
        let collection = ImageCollection()
        collection.loadPortableAssets(try relaunched.materializedAssets())
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.count, 1)
        XCTAssertEqual(collection.items[0].displayName, "relaunch.png")
        XCTAssertEqual(
            collection.items[0].url?.path.hasPrefix(packageURL.path + "/"), true
        )
    }

    func testEditsFollowImportedCopyAcrossRelaunch() async throws {
        let packageURL = tempDirectory.appendingPathComponent(
            "Library.kromoralibrary", isDirectory: true
        )
        let container = makeInMemoryEditContainer()
        let defaults = UserDefaults(suiteName: "KromoraImportedPhotoDurability-\(UUID().uuidString)")!
        let source = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "edited.png", in: tempDirectory
        )
        let first = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container),
            preferences: defaults,
            portablePackageURL: packageURL
        )
        first.openImage(url: source)
        try await waitUntil("the imported image") {
            first.collection.items.count == 1 && first.sourceImage != nil
        }
        first.updateDocument { $0.adjustments = [.exposure(ev: 0.8)] }
        _ = await first.flushPendingWrites()
        await first.shutdown()

        let relaunched = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container),
            preferences: defaults,
            portablePackageURL: packageURL
        )
        try await waitUntil("the relaunched collection") {
            relaunched.collection.items.count == 1
        }
        relaunched.collection.setSelection(at: 0)
        XCTAssertEqual(relaunched.collection.items.count, 1)
        relaunched.openActiveCollectionImage()

        try await waitUntil("the relaunched edits") {
            !relaunched.document.adjustments.isEmpty
        }
        XCTAssertEqual(relaunched.document.adjustments, [.exposure(ev: 0.8)])
    }

    func testDataImportsRemainSelectableAfterAnIncrementalAppend() async throws {
        let packageURL = tempDirectory.appendingPathComponent(
            "Library.kromoralibrary", isDirectory: true
        )
        let firstURL = try Fixtures.writeGradientPNG(width: 12, height: 8, named: "one.png", in: tempDirectory)
        let secondURL = try Fixtures.writeGradientPNG(width: 13, height: 8, named: "two.png", in: tempDirectory)
        let defaults = UserDefaults(suiteName: "KromoraImportedPhotoDurability-\(UUID().uuidString)")!
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), preferences: defaults, portablePackageURL: packageURL
        )
        viewModel.importPhotosData([
            (name: "one.png", data: try Data(contentsOf: firstURL)),
            (name: "two.png", data: try Data(contentsOf: secondURL))
        ])

        try await waitUntil("the imported data") {
            viewModel.collection.items.count == 2
        }
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["one.png", "two.png"])
        viewModel.collection.setSelection(at: 1)
        viewModel.collection.setSelection(at: 0, additive: true)
        XCTAssertEqual(viewModel.collection.selectedIndices, [0, 1])
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(
                    description, "published state did not settle"
                )
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
