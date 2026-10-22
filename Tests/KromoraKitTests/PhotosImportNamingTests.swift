import XCTest

@testable import KromoraKit

@MainActor
private final class NamingProvider: PhotosImportProviding {
    var filenames: [Int: String] = [:]
    var dates: [Int: Date] = [:]
    /// Filenames that only become visible once `prepareForNaming` runs (access granted).
    var filenamesAfterAuthorization: [Int: String] = [:]
    private var authorized = false
    private(set) var captureDateLookups = 0

    func prepareForNaming() async { authorized = true }
    func originalFilename(for selection: PhotosImportSelection) -> String? {
        filenames[selection.ordinal] ?? (authorized ? filenamesAfterAuthorization[selection.ordinal] : nil)
    }
    func captureDate(for selection: PhotosImportSelection) -> Date? {
        captureDateLookups += 1
        return dates[selection.ordinal]
    }
    func transferData(for selection: PhotosImportSelection) async throws -> Data? { nil }
}

@MainActor
final class PhotosImportNamingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func selections(_ count: Int) -> [PhotosImportSelection] {
        (0..<count).map { PhotosImportSelection(ordinal: $0, localIdentifier: "id-\($0)") }
    }

    private func names(_ provider: NamingProvider, count: Int, batch: Date = Date(timeIntervalSince1970: 0)) -> [String?] {
        PhotosImportNaming.resolve(
            selections(count),
            provider: provider,
            batchDate: batch,
            calendar: calendar,
            batchID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
            .map(\.name)
    }

    func testRealFilenameIsUsed() {
        let provider = NamingProvider()
        provider.filenames = [0: "IMG_0001.CR3"]
        provider.dates = [0: Date(timeIntervalSince1970: 1_000)]
        XCTAssertEqual(names(provider, count: 1), ["IMG_0001.CR3"])
        XCTAssertEqual(provider.captureDateLookups, 0)
    }

    func testMetadataDateNamesItem() {
        let provider = NamingProvider()
        provider.dates = [0: Date(timeIntervalSince1970: 1_760_538_727)]
        XCTAssertEqual(
            names(provider, count: 1),
            ["Photo 2025-10-15 143207 00000000-0000-0000-0000-000000000001"]
        )
    }

    func testSameSecondCollisionIsDisambiguatedDeterministically() {
        let provider = NamingProvider()
        let date = Date(timeIntervalSince1970: 1_760_538_727)
        provider.dates = [0: date, 1: date, 2: date]
        XCTAssertEqual(names(provider, count: 3), [
            "Photo 2025-10-15 143207 00000000-0000-0000-0000-000000000001",
            "Photo 2025-10-15 143207 00000000-0000-0000-0000-000000000001 2",
            "Photo 2025-10-15 143207 00000000-0000-0000-0000-000000000001 3",
        ])
    }

    func testSameCaptureSecondAcrossImportsGetsDifferentNames() {
        let provider = NamingProvider()
        let date = Date(timeIntervalSince1970: 1_760_538_727)
        provider.dates = [0: date]
        let selection = selections(1)
        let first = PhotosImportNaming.resolve(
            selection,
            provider: provider,
            batchDate: date,
            calendar: calendar,
            batchID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let second = PhotosImportNaming.resolve(
            selection,
            provider: provider,
            batchDate: date,
            calendar: calendar,
            batchID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        XCTAssertNotEqual(first.first?.name, second.first?.name)
    }

    func testNoMetadataUsesBatchTimeAndDiffersAcrossImports() {
        let provider = NamingProvider()
        let firstDate = Date(timeIntervalSince1970: 1_760_538_727)
        let first = PhotosImportNaming.resolve(
            selections(2),
            provider: provider,
            batchDate: firstDate,
            calendar: calendar,
            batchID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ).map(\.name)
        let second = PhotosImportNaming.resolve(
            selections(2),
            provider: provider,
            batchDate: firstDate,
            calendar: calendar,
            batchID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        ).map(\.name)
        XCTAssertEqual(first, [
            "Photo 2025-10-15 143207 00000000-0000-0000-0000-000000000001",
            "Photo 2025-10-15 143207 00000000-0000-0000-0000-000000000001 2",
        ])
        XCTAssertTrue(Set(first.compactMap { $0 }).isDisjoint(with: Set(second.compactMap { $0 })))
    }

    func testResolvedNamesSurviveSubsetImport() {
        let provider = NamingProvider()
        let date = Date(timeIntervalSince1970: 1_760_538_727)
        provider.dates = [0: date, 1: date]
        let resolved = PhotosImportNaming.resolve(selections(2), provider: provider, calendar: calendar)
        let again = PhotosImportNaming.resolve([resolved[1]], provider: provider, calendar: calendar)
        XCTAssertEqual(again.map(\.name), [resolved[1].name])
    }

    func testReviewItemsCarryTheResolvedNames() {
        let provider = NamingProvider()
        provider.filenames = [1: "IMG_2.HEIC"]
        let review = PhotosImportReviewCoordinator()
        review.begin(selections: selections(2), provider: provider)
        XCTAssertEqual(review.items.map(\.name), review.items.map(\.selection.name))
        XCTAssertEqual(review.items[1].name, "IMG_2.HEIC")
        XCTAssertTrue(review.items[0].name.hasPrefix("Photo "))
        review.cancel()
    }

    func testOriginalFilenameIsUsedWhenAccessIsGrantedAfterAnUnauthorizedLookup() async {
        let provider = NamingProvider()
        provider.filenamesAfterAuthorization = [0: "IMG_9.ARW"]
        XCTAssertNil(provider.originalFilename(for: selections(1)[0]))

        let review = PhotosImportReviewCoordinator()
        await review.beginAfterAuthorization(selections: selections(1), provider: provider)
        XCTAssertEqual(review.items.map(\.name), ["IMG_9.ARW"])
        XCTAssertEqual(review.items.map(\.selection.name), ["IMG_9.ARW"])
        review.cancel()
    }

    func testUnavailableOriginalKeepsDeterministicFallbackAfterAuthorization() async {
        let provider = NamingProvider()
        provider.dates = [0: Date(timeIntervalSince1970: 1_760_538_727)]
        let review = PhotosImportReviewCoordinator()
        await review.beginAfterAuthorization(selections: selections(1), provider: provider)
        XCTAssertTrue(review.items[0].name.hasPrefix("Photo 20"))
        review.cancel()
    }
}
