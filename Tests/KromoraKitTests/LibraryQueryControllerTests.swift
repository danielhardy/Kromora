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
}
