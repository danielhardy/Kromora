import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-519 scope item 1: launch and reload must derive grid metadata from
/// `LibraryIndexEntry` summaries and resolve full records lazily. These tests attach a read
/// observer to the session and prove that the browsing projection opens zero asset records while
/// the legacy page materialization reads exactly the requested page.
@MainActor
final class LibraryBrowsingProjectionTests: TempDirectoryTestCase {
    private func makeSession(assetCount: Int = 3) throws -> PortableLibrarySession {
        let packageURL = tempDirectory.appendingPathComponent("Browsing.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("BrowsingIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        var sources: [URL] = []
        for ordinal in 0..<assetCount {
            // Distinct pixel extents keep the bytes (and content hashes) unique so the
            // package does not deduplicate the fixture imports.
            sources.append(try Fixtures.writeJPEG(
                width: 16 + ordinal * 2, height: 12 + ordinal * 2, orientation: 1,
                named: "browsing-\(ordinal).jpg", in: tempDirectory
            ))
        }
        let result = try session.importURLs(sources)
        XCTAssertEqual(result.imported.count, assetCount)
        let states: [(Int, PhotoFlag)] = [(5, .pick), (3, .none), (1, .reject)]
        for (ordinal, imported) in result.imported.enumerated() {
            let (rating, flag) = states[ordinal % states.count]
            try session.updateLibraryState(for: imported.assetID, rating: rating, flag: flag)
        }
        return session
    }

    func testBrowsingAssetsOpenNoRecords() throws {
        let session = try makeSession()
        var observedReads: [PortablePhotoAssetID] = []
        session.assetRecordReadObserver = { observedReads.append($0) }

        let assets = try session.browsingAssets()
        XCTAssertEqual(observedReads.count, 0, "browsing must not open any asset record")
        XCTAssertEqual(assets.count, 3)

        // Identity, naming, type, state, and geometry all come from the index summary.
        let byName = Dictionary(uniqueKeysWithValues: assets.map { ($0.filename, $0) })
        let top = try XCTUnwrap(byName["browsing-0.jpg"])
        let topEntry = try XCTUnwrap(
            session.page(at: 0).items.first(where: { $0.displayName == top.filename })
        )
        XCTAssertEqual(top.id.raw, "portable:\(topEntry.assetID.raw)")
        XCTAssertEqual(top.fileType, "jpg")
        XCTAssertEqual(top.rating, 5)
        XCTAssertEqual(top.flag, .pick)
        // Geometry parity with the record path is covered by
        // testBrowsingPageMatchesMaterializedPageWithBoundedReads; import summaries carry
        // whatever the writer stored, and browsing must mirror it exactly.

        // The derived embedded URL matches the writer layout and points at a real file.
        let url = try XCTUnwrap(top.url)
        XCTAssertTrue(url.path.hasPrefix(session.package.rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let recordURL = try session.package.embeddedSourceURL(
            for: session.package.readAssetRecord(for: top.source.portableIdentity.assetID)
        )
        XCTAssertEqual(url.standardizedFileURL, recordURL.standardizedFileURL)

        XCTAssertEqual(observedReads.count, 0, "URL verification must use the derived path")
    }

    func testBrowsingPageMatchesMaterializedPageWithBoundedReads() throws {
        let session = try makeSession()
        var observedReads: [PortablePhotoAssetID] = []
        session.assetRecordReadObserver = { observedReads.append($0) }

        let query = LibraryQuery(sort: .init(key: .rating, direction: .descending))
        let browsing = try session.browsingAssets(pageIndex: 0, query: query)
        XCTAssertEqual(observedReads.count, 0)
        XCTAssertEqual(browsing.map(\.rating), [5, 3, 1])

        let materialized = try session.materializedAssets(pageIndex: 0, query: query)
        XCTAssertEqual(observedReads.count, browsing.count)
        XCTAssertEqual(materialized.map(\.id), browsing.map(\.id))
        XCTAssertEqual(materialized.map(\.filename), browsing.map(\.filename))
        XCTAssertEqual(materialized.map(\.fileType), browsing.map(\.fileType))
        XCTAssertEqual(materialized.map(\.rating), browsing.map(\.rating))
        XCTAssertEqual(materialized.map(\.flag), browsing.map(\.flag))
        XCTAssertEqual(materialized.map(\.dimensions), browsing.map(\.dimensions))
    }

    func testFilteredSortedQueriesReadNoRecords() throws {
        let session = try makeSession()
        var observedReads: [PortablePhotoAssetID] = []
        session.assetRecordReadObserver = { observedReads.append($0) }

        let query = LibraryQuery(
            filter: LibraryFilter(flag: .all, rating: .minimum(2)),
            sort: LibraryQuerySort(key: .rating, direction: .descending)
        )
        let page = session.page(at: 0, query: query)
        XCTAssertEqual(page.items.map { $0.summary.rating ?? 0 }, [5, 3])
        let browsing = try session.browsingAssets(pageIndex: 0, query: query)
        XCTAssertEqual(browsing.count, 2)
        XCTAssertEqual(observedReads.count, 0, "filter/sort/page must stay on summaries")
    }

    func testResolveEmbeddedSourceURLReadsAtMostOneRecord() throws {
        let session = try makeSession()
        var observedReads: [PortablePhotoAssetID] = []
        session.assetRecordReadObserver = { observedReads.append($0) }

        let target = try XCTUnwrap(session.page(at: 0).items.first?.assetID)
        let url = try session.resolveEmbeddedSourceURL(for: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Current-writer layout resolves through the derived path with no record read.
        XCTAssertLessThanOrEqual(observedReads.count, 1)

        XCTAssertThrowsError(
            try session.resolveEmbeddedSourceURL(for: PortablePhotoAssetID())
        )
    }

    func testBrowsingIdentitiesNeverAliasAcrossAssets() throws {
        let session = try makeSession()
        session.assetRecordReadObserver = { _ in
            XCTFail("browsing must not open any asset record")
        }
        let assets = try session.browsingAssets()
        let cacheKeys = Set(assets.map(\.cacheKey))
        XCTAssertEqual(cacheKeys.count, assets.count)
        let fingerprints = assets.map(\.source.fingerprint)
        for left in fingerprints {
            for right in fingerprints where left != right {
                XCTAssertFalse(left.matches(right))
            }
        }
    }
}
