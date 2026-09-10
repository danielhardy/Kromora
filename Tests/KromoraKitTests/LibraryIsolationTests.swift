import XCTest
@testable import KromoraKit

@MainActor
final class LibraryIsolationTests: TempDirectoryTestCase {
    func testTestCollectionUsesAnIsolatedManagedLibrary() {
        let collection = makeTestCollection()

        XCTAssertNotEqual(
            collection.libraryFolderURL.standardizedFileURL,
            ImageCollection.defaultLibraryFolderURL.standardizedFileURL
        )
    }
}
