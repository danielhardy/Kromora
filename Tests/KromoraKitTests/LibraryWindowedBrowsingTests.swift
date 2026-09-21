import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-519 scope items 2-3: grid and filmstrip consume a windowed page-backed data source keyed
/// by PortablePhotoAssetID, with LibraryQueryController as the single filter/sort/selection
/// authority and ImageCollection as a thin visible-window adapter.
@MainActor
final class LibraryWindowedBrowsingTests: TempDirectoryTestCase {
    private func makeSession(assetCount: Int = 5, pageSize: Int = 2) throws -> PortableLibrarySession {
        let packageURL = tempDirectory.appendingPathComponent("Windowed-\(UUID().uuidString).kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("WindowedIndex-\(UUID().uuidString)/LibraryIndex.store")
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL, pageSize: pageSize)
        var sources: [URL] = []
        for ordinal in 0..<assetCount {
            sources.append(try Fixtures.writeJPEG(
                width: 16 + ordinal * 2, height: 12 + ordinal * 2, orientation: 1,
                named: "windowed-\(ordinal).jpg", in: tempDirectory
            ))
        }
        let result = try session.importURLs(sources)
        XCTAssertEqual(result.imported.count, assetCount)
        let states: [(Int, PhotoFlag)] = [(5, .pick), (3, .none), (1, .reject), (4, .pick), (2, .none)]
        for (ordinal, imported) in result.imported.enumerated() {
            let (rating, flag) = states[ordinal % states.count]
            try session.updateLibraryState(for: imported.assetID, rating: rating, flag: flag)
        }
        return session
    }

    func testWindowedLaunchBoundsRetainedItems() throws {
        let session = try makeSession(assetCount: 5, pageSize: 2)
        var reads = 0
        session.assetRecordReadObserver = { _ in reads += 1 }
        let window = try session.browsingWindow(pageIndex: 0, query: .all)
        XCTAssertEqual(reads, 0, "window must not open records")
        XCTAssertEqual(window.totalCount, 5)
        XCTAssertEqual(window.pageSize, 2)
        XCTAssertEqual(window.assets.count, 2)

        let collection = makeTestCollection()
        collection.loadPortableWindow(
            assets: window.assets, totalCount: window.totalCount,
            pageIndex: 0, pageSize: window.pageSize, query: .all
        )
        XCTAssertTrue(collection.isPortableWindowed)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(collection.portableTotalCount, 5)
        XCTAssertTrue(collection.portableHasMorePages)
    }

    func testWindowedPagesPreserveStableIdentity() throws {
        let session = try makeSession(assetCount: 5, pageSize: 2)
        session.assetRecordReadObserver = { _ in
            XCTFail("paging must stay on summaries")
        }
        let first = try session.browsingWindow(pageIndex: 0, query: .all)
        let second = try session.browsingWindow(pageIndex: 1, query: .all)
        let third = try session.browsingWindow(pageIndex: 2, query: .all)
        let firstIDs = Set(first.assets.map(\.id))
        let secondIDs = Set(second.assets.map(\.id))
        let thirdIDs = Set(third.assets.map(\.id))
        XCTAssertTrue(firstIDs.intersection(secondIDs).isEmpty)
        XCTAssertTrue(firstIDs.intersection(thirdIDs).isEmpty)
        XCTAssertTrue(secondIDs.intersection(thirdIDs).isEmpty)
        XCTAssertEqual(firstIDs.count + secondIDs.count + thirdIDs.count, 5)

        // Reloading the same page yields the same stable IDs.
        let firstAgain = try session.browsingWindow(pageIndex: 0, query: .all)
        XCTAssertEqual(Set(firstAgain.assets.map(\.id)), firstIDs)
    }

    func testAppendWindowPreservesSelectionAndIdentity() throws {
        let session = try makeSession(assetCount: 5, pageSize: 2)
        let window = try session.browsingWindow(pageIndex: 0, query: .all)
        let collection = makeTestCollection()
        collection.loadPortableWindow(
            assets: window.assets, totalCount: window.totalCount,
            pageIndex: 0, pageSize: window.pageSize, query: .all
        )
        // Select the first window item through the single authority, mirror into the adapter.
        let firstID = try XCTUnwrap(session.page(at: 0).items.first?.assetID)
        session.select(firstID)
        collection.syncPortableSelection(
            selectedIDs: session.portableSelectedIDs, activeID: session.portableActiveID
        )
        XCTAssertEqual(collection.selection.activeID, collection.items.first?.id)

        let next = try session.browsingWindow(pageIndex: 1, query: .all)
        XCTAssertTrue(collection.appendPortableWindow(assets: next.assets, pageIndex: 1))
        XCTAssertEqual(collection.items.count, 4)
        // Stable identity: no duplicates, selection survives the append.
        XCTAssertEqual(Set(collection.items.map(\.id)).count, 4)
        XCTAssertEqual(collection.selection.activeID, collection.items.first?.id)
        XCTAssertEqual(collection.portablePageIndex, 1)
        XCTAssertTrue(collection.portableHasMorePages)
    }

    func testPortableFilterSortWithoutMaterialization() throws {
        let session = try makeSession(assetCount: 5, pageSize: 10)
        var reads = 0
        session.assetRecordReadObserver = { _ in reads += 1 }
        let query = LibraryQuery(
            filter: LibraryFilter(flag: .all, rating: .minimum(3)),
            sort: LibraryQuerySort(key: .rating, direction: .descending)
        )
        let window = try session.browsingWindow(pageIndex: 0, query: query)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(window.assets.map(\.rating), [5, 4, 3])
        XCTAssertEqual(window.totalCount, 3)

        let collection = makeTestCollection()
        collection.loadPortableWindow(
            assets: window.assets, totalCount: window.totalCount,
            pageIndex: 0, pageSize: window.pageSize, query: query
        )
        XCTAssertEqual(collection.items.count, 3)
        XCTAssertEqual(collection.portableQuery.filter, query.filter)
    }

    func testSingleSelectionAuthority() throws {
        let session = try makeSession(assetCount: 3, pageSize: 10)
        let window = try session.browsingWindow(pageIndex: 0, query: .all)
        let collection = makeTestCollection()
        collection.loadPortableWindow(
            assets: window.assets, totalCount: window.totalCount,
            pageIndex: 0, pageSize: window.pageSize, query: .all
        )
        // Authority starts empty; mirror keeps adapter empty too.
        collection.syncPortableSelection(
            selectedIDs: session.portableSelectedIDs, activeID: session.portableActiveID
        )
        XCTAssertTrue(collection.selection.isEmpty)

        // Select via the controller (keyboard/culling/open path), mirror to the adapter.
        let target = try XCTUnwrap(session.page(at: 0).items.first?.assetID)
        session.select(target)
        collection.syncPortableSelection(
            selectedIDs: session.portableSelectedIDs, activeID: session.portableActiveID
        )
        XCTAssertEqual(
            collection.selection.activeID?.raw, "portable:\(target.raw)"
        )
        XCTAssertEqual(session.portableActiveID, target)

        // Toggle via the controller clears both.
        session.togglePortableSelection(target)
        collection.syncPortableSelection(
            selectedIDs: session.portableSelectedIDs, activeID: session.portableActiveID
        )
        XCTAssertTrue(collection.selection.isEmpty)
        XCTAssertNil(session.portableActiveID)
    }
}
