import Foundation
import XCTest
@testable import KromoraKit

final class LibraryFacetTests: XCTestCase {
    private struct Row {
        var make: String?
        var model: String?
        var lens: String?
        var rating: Int
        var location: String?
        var settings: PortablePackageCaptureSettings?
        var dateISO: String? = ""
    }

    private func controller(_ rows: [Row]) throws -> LibraryQueryController {
        let entries = rows.enumerated().map { index, row in
            let assetID = PortablePhotoAssetID()
            return LibraryIndexEntry(from: .init(
                assetID: assetID,
                recordPath: "Assets/" + PortableLibraryPackage.shard(for: assetID)
                    + "/" + assetID.raw + "/asset.json",
                summary: .init(
                    captureDateISO: row.dateISO, rating: row.rating, cameraMake: row.make, cameraModel: row.model,
                    lens: row.lens, coarseLocation: row.location,
                    captureSettings: row.settings, displayName: "photo-\(index)")
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

    func testLocationFacetSeparatesNoLocationFromUnreadAssets() throws {
        let controller = try controller([
            Row(make: nil, model: nil, lens: nil, rating: 1, location: "≈38° N, 122° W"),
            Row(make: nil, model: nil, lens: nil, rating: 1, location: "≈38° N, 122° W"),
            Row(make: nil, model: nil, lens: nil, rating: 1, location: ""),
            Row(make: nil, model: nil, lens: nil, rating: 1, location: nil),
        ])
        var query = LibraryQuery()
        let counts = Dictionary(
            uniqueKeysWithValues: controller.facetCounts(query: query).counts(for: .location)
                .map { ($0.value, $0.count) })
        XCTAssertEqual(counts, ["≈38° N, 122° W": 2, "No location": 1, "Unknown": 1])

        query.facets.toggle("No location", in: .location)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 1)
        query.facets.toggle("≈38° N, 122° W", in: .location)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 3)
        XCTAssertEqual(
            query.activeFilterDescriptions, ["No location", "≈38° N, 122° W"].sorted())
    }

    func testLegacyFacetPayloadDecodesWithoutLocations() throws {
        let json = #"{"cameras":["Sony A7"],"lenses":[]}"#
        let facets = try JSONDecoder().decode(LibraryFacetSelection.self, from: Data(json.utf8))
        XCTAssertEqual(facets.cameras, ["Sony A7"])
        XCTAssertTrue(facets.locations.isEmpty)
    }

    func testLegacySummaryDecodesWithUnreadLocation() throws {
        let json = #"{"displayName":"a.dng","assetRevision":0}"#
        let summary = try JSONDecoder().decode(
            PortablePackageAssetSummary.self, from: Data(json.utf8))
        XCTAssertNil(summary.coarseLocation)
    }

    private func rangeController() throws -> LibraryQueryController {
        func row(_ settings: PortablePackageCaptureSettings?) -> Row {
            Row(make: nil, model: nil, lens: nil, rating: 0, location: nil, settings: settings)
        }
        return try controller([
            row(.init(focalLength: 24, iso: 100, aperture: 1.8)),
            row(.init(focalLength: 50, iso: 800, aperture: 2.8)),
            row(.init(focalLength: 200, iso: 3200, aperture: nil)),
            row(.init()),  // read, no values
            row(nil),      // not read yet
        ])
    }

    func testRangeFacetFiltersAndExcludesPhotosWithoutAValue() throws {
        let controller = try rangeController()
        var query = LibraryQuery()
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 5)

        query.facets.setRange(.init(lower: 30, upper: 250), for: .focalLength)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 2)
        query.facets.setRange(.init(lower: 100, upper: 1000), for: .iso)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 1)
        XCTAssertEqual(query.facets.activeCount, 2)
        XCTAssertEqual(
            query.activeFilterDescriptions,
            ["30–250 mm", "ISO 100–1000"])
    }

    func testRangeBoundsIgnoreOwnRangeButHonorOtherFilters() throws {
        let controller = try rangeController()
        var query = LibraryQuery()
        var counts = controller.facetCounts(query: query)
        XCTAssertEqual(counts.bounds(for: .focalLength), 24...200)
        XCTAssertEqual(counts.bounds(for: .aperture), 1.8...2.8)
        XCTAssertEqual(counts.unreadCaptureSettingsCount, 1)

        query.facets.setRange(.init(lower: 100, upper: 3200), for: .iso)
        query.facets.setRange(.init(lower: 40, upper: 60), for: .focalLength)
        counts = controller.facetCounts(query: query)
        // Focal bounds reflect the ISO range but not the focal range itself.
        XCTAssertEqual(counts.bounds(for: .focalLength), 24...200)
        // Aperture bounds reflect both other ranges.
        XCTAssertEqual(counts.bounds(for: .aperture), 2.8...2.8)
    }

    func testRangeSelectionNormalizesAndRoundTrips() throws {
        let range = LibraryRangeSelection(lower: 9, upper: 3)
        XCTAssertEqual(range, LibraryRangeSelection(lower: 3, upper: 9))
        var facets = LibraryFacetSelection()
        facets.setRange(range, for: .aperture)
        let decoded = try JSONDecoder().decode(
            LibraryFacetSelection.self, from: JSONEncoder().encode(facets))
        XCTAssertEqual(decoded, facets)
        XCTAssertTrue(decoded.isActive)
    }

    func testLegacySummaryDecodesWithUnreadCaptureSettings() throws {
        let json = #"{"displayName":"a.dng","assetRevision":0}"#
        let summary = try JSONDecoder().decode(
            PortablePackageAssetSummary.self, from: Data(json.utf8))
        XCTAssertNil(summary.captureSettings)
    }

    func testSortableDateParsingRejectsMalformedValues() {
        XCTAssertEqual(ImageMetadata.sortableDate("2024:03:09 14:05:59"), "2024-03-09T14:05:59")
        XCTAssertEqual(ImageMetadata.sortableDate("2024:02:29 14:05:59"), "2024-02-29T14:05:59")
        XCTAssertNil(ImageMetadata.sortableDate("0000:00:00 00:00:00"))
        XCTAssertNil(ImageMetadata.sortableDate("2023:02:29 14:05:59"))
        XCTAssertNil(ImageMetadata.sortableDate("2024:02:31 14:05:59"))
        XCTAssertNil(ImageMetadata.sortableDate("2024::03 09 14:05:59"))
        XCTAssertNil(ImageMetadata.sortableDate("garbage"))
        XCTAssertNil(ImageMetadata.sortableDate(nil))
    }

    func testDayNumberMatchesCalendar() throws {
        XCTAssertEqual(LibraryRangeFacet.dayNumber("1970-01-01T00:00:00"), 0)
        XCTAssertEqual(LibraryRangeFacet.dayNumber("2024-02-29T10:00:00"), 19_782)
        XCTAssertEqual(LibraryRangeFacet.dayNumber("2024-03-01"), 19_783)
        XCTAssertEqual(LibraryRangeFacet.dayNumber("1969-12-31"), -1)
        XCTAssertNil(LibraryRangeFacet.dayNumber("2023-02-29"))
        XCTAssertNil(LibraryRangeFacet.dayNumber("2024-13-01"))
    }

    func testCaptureDateRangeFacet() throws {
        let controller = try controller([
            "2024-01-10T09:00:00", "2024-06-15T23:59:59", "2025-01-01T00:00:00", "", nil,
        ].map {
            Row(make: nil, model: nil, lens: nil, rating: 0, settings: .init(), dateISO: $0)
        })
        var query = LibraryQuery()
        let counts = controller.facetCounts(query: query)
        XCTAssertEqual(
            counts.bounds(for: .captureDate),
            LibraryRangeFacet.dayNumber("2024-01-10")!...LibraryRangeFacet.dayNumber("2025-01-01")!)
        XCTAssertEqual(counts.unreadCaptureSettingsCount, 1)

        // Inclusive on both whole days; empty and unread dates never match.
        query.facets.setRange(
            .init(
                lower: LibraryRangeFacet.dayNumber("2024-01-10")!,
                upper: LibraryRangeFacet.dayNumber("2024-06-15")!),
            for: .captureDate)
        XCTAssertEqual(controller.page(at: 0, query: query).totalCount, 2)
    }

    func testLegacySummaryDecodesWithUnreadCaptureDate() throws {
        let json = #"{"displayName":"a.dng","assetRevision":0}"#
        let summary = try JSONDecoder().decode(
            PortablePackageAssetSummary.self, from: Data(json.utf8))
        XCTAssertNil(summary.captureDateISO)
    }

    func testCameraNameDoesNotRepeatTheMakeAlreadyInTheModel() {
        XCTAssertEqual(LibraryFacet.cameraName(make: "Canon", model: "Canon EOS R5"), "Canon EOS R5")
        XCTAssertEqual(LibraryFacet.cameraName(make: "SONY", model: "ILCE-7M4"), "SONY ILCE-7M4")
        XCTAssertEqual(LibraryFacet.cameraName(make: "NIKON CORPORATION", model: "NIKON Z 6"), "NIKON Z 6")
        XCTAssertEqual(LibraryFacet.cameraName(make: " ", model: "X100V"), "X100V")
        XCTAssertEqual(LibraryFacet.cameraName(make: "FUJIFILM", model: nil), "FUJIFILM")
        XCTAssertEqual(LibraryFacet.cameraName(make: nil, model: nil), "")
    }
}
