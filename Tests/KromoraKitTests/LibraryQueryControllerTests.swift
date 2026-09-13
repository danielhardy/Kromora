import Foundation
import XCTest
@testable import KromoraKit

final class LibraryQueryControllerTests: TempDirectoryTestCase {

    func testProjectionReadsMembershipSummariesWithoutAssetRecordsAndPagesAt500() throws {
        let packageURL = tempDirectory.appendingPathComponent("IndexOnly.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        var entriesByShard = Dictionary(
            uniqueKeysWithValues: PortableLibraryPackage.allShards.map {
                ($0, [PortablePackageMembershipEntry]())
            }
        )

        for index in 0..<1_200 {
            let assetID = PortablePhotoAssetID()
            let shard = PortableLibraryPackage.shard(for: assetID)
            entriesByShard[shard, default: []].append(.init(
                assetID: assetID,
                recordPath: "Assets/" + shard + "/" + assetID.raw + "/asset.json",
                summary: .init(
                    rating: index % 6,
                    flag: index % 3 == 0 ? PhotoFlag.pick.rawValue : PhotoFlag.none.rawValue,
                    displayName: String(format: "Photo-%04d.jpg", index)
                )
            ))
        }
        for shard in PortableLibraryPackage.allShards {
            var membership = try package.readMembershipShard(shard)
            membership.entries = entriesByShard[shard, default: []]
            try package.writeMembershipShard(membership)
        }

        let projection = try LibraryIndexProjection(package: package)
        XCTAssertEqual(projection.count, 1_200)
        let controller = LibraryQueryController(index: projection)
        let firstPage = controller.page(at: 0)
        let thirdPage = controller.page(at: 2)
        XCTAssertEqual(firstPage.items.count, 500)
        XCTAssertEqual(thirdPage.items.count, 200)
        XCTAssertEqual(firstPage.totalCount, 1_200)
        XCTAssertTrue(firstPage.hasNextPage)
        XCTAssertFalse(thirdPage.hasNextPage)
    }

    func testFilteringAndSortingUseSummaryValuesAndSelectionStaysUUIDKeyed() throws {
        let ids = (0..<6).map { _ in PortablePhotoAssetID() }
        let names = ["Zeta", "Alpha", "Echo", "Bravo", "Delta", "Charlie"]
        let entries = ids.enumerated().map { index, assetID in
            LibraryIndexEntry(from: .init(
                assetID: assetID,
                recordPath: "Assets/" + PortableLibraryPackage.shard(for: assetID)
                    + "/" + assetID.raw + "/asset.json",
                summary: .init(
                    rating: index,
                    flag: index.isMultiple(of: 2) ? PhotoFlag.pick.rawValue : PhotoFlag.none.rawValue,
                    cameraModel: index.isMultiple(of: 2) ? "Camera A" : "Camera B",
                    displayName: names[index]
                )
            ))
        }
        let projection = try LibraryIndexProjection(libraryID: UUID(), entries: entries)
        var controller = LibraryQueryController(index: projection, pageSize: 2)
        let selectedID = ids[4]
        controller.select(selectedID)

        let picks = controller.page(
            at: 0,
            query: .init(
                filter: .init(flag: .picks),
                sort: .init(key: .rating, direction: .descending)
            )
        )
        XCTAssertEqual(picks.items.map(\.summary.rating), [4, 2])
        XCTAssertEqual(picks.items.map(\.assetID), [ids[4], ids[2]])
        XCTAssertTrue(picks.items[0].isSelected)

        let resorted = controller.page(
            at: 0,
            query: .init(sort: .init(key: .displayName, direction: .ascending))
        )
        XCTAssertEqual(resorted.items.map(\.displayName), ["Alpha", "Bravo"])
        XCTAssertFalse(resorted.items.contains { $0.assetID == selectedID })
        XCTAssertEqual(controller.selectedAssetIDs, [selectedID])

        let selectedPage = controller.page(
            at: 1,
            query: .init(sort: .init(key: .displayName, direction: .ascending))
        )
        XCTAssertTrue(selectedPage.items.contains { $0.assetID == selectedID && $0.isSelected })
    }

    func testProjectionRoundTripsAsARebuildableLocalIndex() throws {
        let assetID = PortablePhotoAssetID()
        let entry = LibraryIndexEntry(from: .init(
            assetID: assetID,
            recordPath: "Assets/" + PortableLibraryPackage.shard(for: assetID)
                + "/" + assetID.raw + "/asset.json",
            summary: .init(displayName: "Indexed")
        ))
        let projection = try LibraryIndexProjection(libraryID: UUID(), entries: [entry])
        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        try projection.write(to: indexURL)

        XCTAssertEqual(try LibraryIndexProjection.load(from: indexURL), projection)
    }

    func testWarmSessionReadsOnlyTheIndexAndDoesNotRequireAssetRecords() async throws {
        let package = try packageWithMembership(count: 1_200)
        let expected = try LibraryIndexProjection(package: package)
        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        try expected.write(to: indexURL)

        // There are intentionally no Assets/**/asset.json files in this fixture. The query-safe
        // package open and warm session must not try to validate or materialise them.
        let openedPackage = try PortableLibraryPackage.openForQuery(at: package.rootURL)
        let session = try await LibraryIndexSession.open(
            package: openedPackage, indexURL: indexURL
        )

        let source = await session.source
        let firstPage = await session.page(at: 0)
        let thirdPage = await session.page(at: 2)
        let publishedFirstPage = try await session.firstPage()
        XCTAssertEqual(source, .warm)
        XCTAssertEqual(firstPage.items, LibraryQueryController(index: expected).page(at: 0).items)
        XCTAssertEqual(publishedFirstPage.items, firstPage.items)
        XCTAssertEqual(thirdPage.items.count, 200)
    }

    func testMissingIndexRebuildsFromShardsPublishesFirstPageAndPreservesContent() async throws {
        let package = try packageWithMembership(count: 1_200)
        let expected = try LibraryIndexProjection(package: package)
        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        let openedPackage = try PortableLibraryPackage.openForQuery(at: package.rootURL)

        let session = try await LibraryIndexSession.open(
            package: openedPackage, indexURL: indexURL
        )
        let source = await session.source
        let rebuilt = try await session.waitForRebuild()
        XCTAssertEqual(source, .rebuilt)
        XCTAssertEqual(rebuilt, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
        let rebuiltPage = await session.page(at: 0)
        XCTAssertEqual(rebuiltPage.items.count, 500)

        // Deleting the projection is safe: opening again reconstructs the same values from the
        // canonical membership shards, not from the previous local index.
        try FileManager.default.removeItem(at: indexURL)
        let reopened = try await LibraryIndexSession.open(
            package: openedPackage, indexURL: indexURL
        )
        let reopenedProjection = try await reopened.waitForRebuild()
        XCTAssertEqual(reopenedProjection, expected)
    }

    func testCorruptIndexAutomaticallyFallsBackToShardRebuild() async throws {
        let package = try packageWithMembership(count: 12)
        let expected = try LibraryIndexProjection(package: package)
        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not an index".utf8).write(to: indexURL)

        let session = try await LibraryIndexSession.open(
            package: try PortableLibraryPackage.openForQuery(at: package.rootURL),
            indexURL: indexURL
        )
        let source = await session.source
        let rebuilt = try await session.waitForRebuild()
        XCTAssertEqual(source, .rebuilt)
        XCTAssertEqual(rebuilt, expected)
    }

    func testRebuildProgressPublishesACompletePageBeforeCompletion() async throws {
        let package = try packageWithMembership(count: 1_200)
        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        let (stream, continuation) = AsyncStream<LibraryIndexRebuildProgress>.makeStream()
        let rebuild = Task {
            try await LibraryIndexProjection.rebuild(
                from: package,
                to: indexURL,
                progress: { progress in continuation.yield(progress) }
            )
        }

        var iterator = stream.makeAsyncIterator()
        let firstProgress = await iterator.next()
        let first = try XCTUnwrap(firstProgress)
        XCTAssertFalse(first.isComplete)
        XCTAssertEqual(first.page.items.count, 500)
        XCTAssertLessThan(first.shardsRead, first.totalShards)

        let finalProgress = await iterator.next()
        let final = try XCTUnwrap(finalProgress)
        XCTAssertTrue(final.isComplete)
        XCTAssertEqual(final.projection.count, 1_200)
        continuation.finish()
        let rebuilt = try await rebuild.value
        XCTAssertEqual(rebuilt.count, 1_200)
    }

    private func packageWithMembership(count: Int) throws -> PortableLibraryPackage {
        let packageURL = tempDirectory.appendingPathComponent("Rebuild-\(count).kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        var entriesByShard = Dictionary(
            uniqueKeysWithValues: PortableLibraryPackage.allShards.map { ($0, [PortablePackageMembershipEntry]()) }
        )
        for index in 0..<count {
            let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: String(
                format: "%08x-0000-4000-8000-%012x", index, index
            ))!)
            let shard = PortableLibraryPackage.shard(for: assetID)
            entriesByShard[shard, default: []].append(.init(
                assetID: assetID,
                recordPath: "Assets/\(shard)/\(assetID.raw)/asset.json",
                summary: .init(
                    captureDate: String(format: "2026-01-%02d", (index % 28) + 1),
                    rating: index % 6,
                    flag: index.isMultiple(of: 3) ? PhotoFlag.pick.rawValue : PhotoFlag.none.rawValue,
                    cameraModel: "Camera \(index % 4)",
                    displayName: String(format: "Photo-%04d.jpg", index),
                    assetRevision: UInt64(index)
                )
            ))
        }
        for shard in PortableLibraryPackage.allShards {
            var membership = try package.readMembershipShard(shard)
            membership.entries = entriesByShard[shard, default: []]
            try package.writeMembershipShard(membership)
        }
        return package
    }
}
