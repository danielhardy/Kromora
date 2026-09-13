import Foundation
import XCTest
@testable import KromoraKit

final class LibraryQueryControllerTests: TempDirectoryTestCase {

    func testGeneratedPackageQueriesAtOneAndTenThousandNeverOpenAssetRecordCanaries() async throws {
        for scale in [SyntheticLibraryGenerator.Scale.oneThousand, .tenThousand] {
            let generated = try await SyntheticLibraryGenerator.generate(
                scale: scale,
                seed: SyntheticLibraryGenerator.defaultSeed,
                in: tempDirectory,
                yieldEvery: 256
            )
            defer { try? generated.cleanup() }

            let fixture = try generated.makePortableLibraryPackage(
                at: tempDirectory.appendingPathComponent(
                    "QueryScale-\(scale.assetCount).kromoralibrary"
                ),
                addAssetRecordCanaries: true
            )
            XCTAssertEqual(fixture.assetIDs.count, scale.assetCount)
            XCTAssertEqual(fixture.assetRecordCanaryURLs.count, scale.assetCount)
            XCTAssertTrue(fixture.assetRecordCanaryURLs.allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            })

            let projection = try LibraryIndexProjection(package: fixture.package)
            XCTAssertEqual(projection.count, scale.assetCount)
            let indexURL = tempDirectory.appendingPathComponent(
                "QueryScale-\(scale.assetCount)-index/LibraryIndex.store"
            )
            try projection.write(to: indexURL)

            // The canaries are deliberately not valid asset records. Opening any one of them
            // would throw, so a successful package-backed query is an executable no-record-read
            // assertion rather than a source inspection or an object-count estimate.
            let package = try PortableLibraryPackage.openForQuery(at: fixture.package.rootURL)
            let session = try await LibraryIndexSession.open(
                package: package,
                indexURL: indexURL,
                pageSize: 500,
                query: .init(sort: .init(key: .assetID, direction: .ascending))
            )
            let source = await session.source
            XCTAssertEqual(source, .warm)

            let firstPage = try await session.firstPage()
            XCTAssertEqual(firstPage.items.count, 500)
            XCTAssertEqual(firstPage.totalCount, scale.assetCount)

            let query = LibraryQuery(
                filter: .init(flag: .picks, rating: .minimum(3)),
                searchText: "photo",
                sort: .init(key: .rating, direction: .descending)
            )
            let filteredPage = await session.page(at: 0, query: query)
            let nextFilteredPage = await session.page(at: 1, query: query)
            XCTAssertEqual(
                filteredPage.totalCount,
                (0..<scale.assetCount).filter { $0.isMultiple(of: 3) && $0 % 6 >= 3 }.count
            )
            XCTAssertEqual(filteredPage.items.count, min(500, filteredPage.totalCount))
            if !nextFilteredPage.items.isEmpty {
                XCTAssertTrue(
                    Set(filteredPage.items.map(\.assetID))
                        .intersection(nextFilteredPage.items.map(\.assetID)).isEmpty
                )
            }
            let nextPage = await session.page(at: 1)
            XCTAssertEqual(nextPage.items.count, 500)
            XCTAssertTrue(
                Set(firstPage.items.map(\.assetID)).intersection(nextPage.items.map(\.assetID)).isEmpty
            )
            XCTAssertTrue(
                zip(filteredPage.items, filteredPage.items.dropFirst()).allSatisfy {
                    ($0.summary.rating ?? 0) >= ($1.summary.rating ?? 0)
                }
            )

            var controller = await session.currentController()
            controller.selectAll(query: query)
            XCTAssertEqual(controller.selectedIDs.count, filteredPage.totalCount)
            XCTAssertTrue(controller.selectedIDs.isSubset(of: Set(fixture.assetIDs)))

            // Reaching this point means filtering, sorting, paging, and select-all all ran while
            // every full-record path was an invalid canary. Originals are likewise never needed:
            // the query projection contains only the generated membership summaries.
            XCTAssertTrue(fixture.assetRecordCanaryURLs.allSatisfy {
                (try? Data(contentsOf: $0)) == Data("asset-record-canary".utf8)
            })
        }
    }

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

    func testIndexProjectionExcludesTombstonesAndKeepsSelectionUUIDBased() throws {
        let packageURL = tempDirectory.appendingPathComponent("DeletionProjection.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let liveID = PortablePhotoAssetID(uuid: UUID(uuidString: "00000001-0000-4000-8000-000000000001")!)
        let deletedID = PortablePhotoAssetID(uuid: UUID(uuidString: "00000002-0000-4000-8000-000000000002")!)
        var membership = try package.readMembershipShard("00")
        membership.entries = [
            .init(
                assetID: liveID,
                recordPath: "Assets/00/\(liveID.raw)/asset.json",
                summary: .init(displayName: "live.jpg")
            ),
            .init(
                assetID: deletedID,
                recordPath: "Assets/00/\(deletedID.raw)/asset.json",
                deletedRevision: 4,
                isTombstone: true,
                summary: .init(displayName: "deleted.jpg")
            ),
        ]
        try package.writeMembershipShard(membership)

        let projection = try LibraryIndexProjection(package: package)
        var controller = LibraryQueryController(index: projection, pageSize: 60)
        controller.select(deletedID)
        XCTAssertEqual(projection.count, 1)
        XCTAssertFalse(controller.contains(deletedID))
        XCTAssertTrue(controller.selectedIDs.isEmpty)
        XCTAssertEqual(controller.page(at: 0).items.map(\.assetID), [liveID])
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

    func testFailedRebuildClearsIsRebuilding() async throws {
        // 1,200 entries publish a first page well before the last shard is read, so the session
        // opens successfully; corrupting the last shard fails the background rebuild afterward.
        let package = try packageWithMembership(count: 1_200)
        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        let lastShard = PortableLibraryPackage.allShards.last!
        try Data("not json".utf8).write(to: package.membershipURL(for: lastShard))

        let session = try await LibraryIndexSession.open(
            package: try PortableLibraryPackage.openForQuery(at: package.rootURL),
            indexURL: indexURL
        )
        do {
            _ = try await session.waitForRebuild()
            XCTFail("expected the rebuild to throw for a corrupt membership shard")
        } catch {
            // expected
        }
        let stillRebuilding = await session.isRebuilding
        XCTAssertFalse(stillRebuilding)
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
