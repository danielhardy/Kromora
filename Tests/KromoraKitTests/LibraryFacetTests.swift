import Foundation
import XCTest
@testable import KromoraKit

final class LibraryFacetTests: XCTestCase {
    private struct Row {
        var make: String?
        var model: String?
        var lens: String?
        var rating: Int
    }

    private func controller(_ rows: [Row]) throws -> LibraryQueryController {
        let entries = rows.enumerated().map { index, row in
            let assetID = PortablePhotoAssetID()
            return LibraryIndexEntry(from: .init(
                assetID: assetID,
                recordPath: "Assets/" + PortableLibraryPackage.shard(for: assetID)
                    + "/" + assetID.raw + "/asset.json",
                summary: .init(
                    rating: row.rating, cameraMake: row.make, cameraModel: row.model,
                    lens: row.lens, displayName: "photo-\(index)")
            ))
        }
        return LibraryQueryController(
            index: try LibraryIndexProjection(libraryID: UUID(), entries: entries))
    }

    private let rows = [
        Row(make: "Sony", model: "A7", lens: "35mm", rating: 5),
        Row(make: "Sony", model: "A7", lens: "85mm", rating: 1),
        Row(make: "Fuji", model: "X100", lens: "23mm", rating: 5),
        Row(make: nil, model: nil, lens: nil, rating: 3),
    ]

    func testActiveFilterSummaryListsEveryDimensionInStableOrder() {
        var query = LibraryQuery(sort: .ratingDescending)
        XCTAssertFalse(query.hasActiveFilters)
        XCTAssertEqual(query.activeFilterDescriptions, [])

        query.filter = LibraryFilter(flag: .picks, rating: .minimum(4))
        query.facets.toggle("Sony A7", in: .camera)
        query.facets.toggle("85mm", in: .lens)
        query.searchText = "beach"
        XCTAssertTrue(query.hasActiveFilters)
        XCTAssertEqual(
            query.activeFilterDescriptions,
            ["Picks", "4+ stars", "Sony A7", "85mm", "“beach”"])
    }

    func testSortAloneIsNotAnActiveFilter() {
        XCTAssertFalse(LibraryQuery(sort: .captureDateDescending).hasActiveFilters)
        XCTAssertTrue(LibraryQuery(searchText: "x").hasActiveFilters)
        XCTAssertFalse(LibraryQuery(searchText: "   ").hasActiveFilters)
    }

    func testClearingFiltersKeepsSortAndMatchesAllRows() throws {
        let controller = try controller(rows)
        var query = LibraryQuery(sort: .ratingDescending)
        query.filter = LibraryFilter(flag: .picks)
        query.facets.toggle("Fuji X100", in: .camera)
        query.searchText = "photo"
        let cleared = query.clearingFilters()
        XCTAssertEqual(cleared, LibraryQuery(sort: .ratingDescending))
        XCTAssertEqual(controller.page(at: 0, query: cleared).totalCount, rows.count)
    }

    func testCameraFacetFiltersWithOROverValues() throws {
        let controller = try controller(rows)
        var query = LibraryQuery()
        query.facets.toggle("Sony A7", in: .camera)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 2)
        query.facets.toggle("Fuji X100", in: .camera)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 3)
        query.facets.toggle("Unknown", in: .camera)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 4)
    }

    func testFacetsCombineWithANDAndExistingFilters() throws {
        let controller = try controller(rows)
        var query = LibraryQuery(filter: .init(rating: .minimum(4)))
        query.facets.toggle("Sony A7", in: .camera)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 1)
        query.facets.toggle("85mm", in: .lens)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 0)
        query.filter = .all
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 1)
        query.searchText = "photo-0"
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 0)
    }

    func testCountsIgnoreOwnFacetButHonorOthers() throws {
        let controller = try controller(rows)
        var query = LibraryQuery()
        query.facets.toggle("Sony A7", in: .camera)
        let counts = controller.facetCounts(query: query)
        let cameras = Dictionary(
            uniqueKeysWithValues: counts.counts(for: .camera).map { ($0.value, $0.count) })
        XCTAssertEqual(cameras, ["Sony A7": 2, "Fuji X100": 1, "Unknown": 1])
        let lenses = Dictionary(
            uniqueKeysWithValues: counts.counts(for: .lens).map { ($0.value, $0.count) })
        XCTAssertEqual(lenses, ["35mm": 1, "85mm": 1])
    }

    func testSelectedValueWithNoMatchesStaysListedAtZero() throws {
        let controller = try controller(rows)
        var query = LibraryQuery(filter: .init(rating: .exact(3)))
        query.facets.toggle("Fuji X100", in: .camera)
        let fuji = controller.facetCounts(query: query).counts(for: .camera)
            .first { $0.value == "Fuji X100" }
        XCTAssertEqual(fuji?.count, 0)
    }

    func testQueryRoundTripsAndOlderPayloadsDecodeWithoutFacets() throws {
        var query = LibraryQuery(searchText: "x")
        query.facets.toggle("Sony A7", in: .camera)
        let data = try JSONEncoder().encode(query)
        XCTAssertEqual(try JSONDecoder().decode(LibraryQuery.self, from: data), query)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "facets")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(
            try JSONDecoder().decode(LibraryQuery.self, from: legacy).facets, .none)
    }

    func testSelectionSurvivesFacetChange() throws {
        var controller = try controller(rows)
        let id = try XCTUnwrap(controller.index.entries.first?.assetID)
        controller.select(id)
        var query = LibraryQuery()
        query.facets.toggle("Unknown", in: .camera)
        XCTAssertTrue(controller.selectedIDs.contains(id))
        XCTAssertTrue(controller.page(at: 0, query: LibraryQuery()).items.contains {
            $0.assetID == id && $0.isSelected
        })
    }
}
