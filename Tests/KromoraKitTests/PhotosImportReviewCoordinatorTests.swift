import XCTest

@testable import KromoraKit

@MainActor
private final class ReviewPhotosProvider: PhotosImportProviding {
    let payloads: [Int: Data]
    private(set) var transferred: [Int] = []

    init(payloads: [Int: Data]) { self.payloads = payloads }

    func originalFilename(for selection: PhotosImportSelection) -> String? {
        "IMG_\(selection.ordinal).HEIC"
    }

    func transferData(for selection: PhotosImportSelection) async throws -> Data? {
        transferred.append(selection.ordinal)
        return payloads[selection.ordinal]
    }
}

@MainActor
final class PhotosImportReviewCoordinatorTests: XCTestCase {
    private func selections(_ count: Int) -> [PhotosImportSelection] {
        (0..<count).map { PhotosImportSelection(ordinal: $0, localIdentifier: "id-\($0)") }
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for review state")
    }

    func testMatchesAreTaggedAndLeftOutOfTheDefaultSelection() async throws {
        let known = Data(repeating: 1, count: 128)
        let provider = ReviewPhotosProvider(payloads: [
            0: known, 1: Data(repeating: 2, count: 128), 2: known, 3: Data(repeating: 3, count: 8),
        ])
        let review = PhotosImportReviewCoordinator()
        let hash = LibraryMembershipMatcher.contentHash(of: known)
        review.libraryMatcherLoader = { LibraryMembershipMatcher(knownHashes: [hash]) }

        review.begin(selections: selections(4), provider: provider)
        XCTAssertTrue(review.isPresented)
        XCTAssertEqual(review.selection.count, 4, "everything starts selected until checks arrive")
        try await waitUntil { !review.isChecking }

        XCTAssertEqual(review.inLibrary, ["0", "2"])
        XCTAssertEqual(review.checked, 4)
        XCTAssertEqual(review.selectedItems.map(\.selection.ordinal), [1, 3])

        review.selectAll()
        XCTAssertEqual(review.selectedItems.map(\.selection.ordinal), [1, 3])

        // An explicit click re-selects a tagged item; Hide filters the grid without selecting.
        review.toggle(review.items[0])
        XCTAssertEqual(review.selectedItems.map(\.selection.ordinal), [0, 1, 3])
        review.hidesInLibrary = true
        XCTAssertEqual(review.visibleItems.map(\.selection.ordinal), [1, 3])
    }

    func testImportHandsOnlyConfirmedSelectionsToTheImporter() async throws {
        let known = Data(repeating: 1, count: 64)
        let provider = ReviewPhotosProvider(payloads: [0: known, 1: Data(repeating: 2, count: 64)])
        let review = PhotosImportReviewCoordinator()
        let hash = LibraryMembershipMatcher.contentHash(of: known)
        review.libraryMatcherLoader = { LibraryMembershipMatcher(knownHashes: [hash]) }
        var imported: [PhotosImportSelection] = []
        review.onImport = { selections, _ in imported = selections }

        review.begin(selections: selections(2), provider: provider)
        try await waitUntil { !review.isChecking }
        review.confirm()

        XCTAssertEqual(imported.map(\.ordinal), [1])
        XCTAssertFalse(review.isPresented)
    }

    func testLateResultsDoNotUndoAnExplicitChoice() async throws {
        let known = Data(repeating: 1, count: 64)
        let provider = ReviewPhotosProvider(payloads: [0: known])
        let review = PhotosImportReviewCoordinator()
        let hash = LibraryMembershipMatcher.contentHash(of: known)
        let gate = AsyncStream<Void>.makeStream()
        review.libraryMatcherLoader = {
            for await _ in gate.stream { break }
            return LibraryMembershipMatcher(knownHashes: [hash])
        }

        review.begin(selections: selections(1), provider: provider)
        review.toggle(review.items[0])   // off
        review.toggle(review.items[0])   // back on: now explicit
        gate.continuation.yield()
        try await waitUntil { !review.isChecking }

        XCTAssertEqual(review.inLibrary, ["0"])
        XCTAssertEqual(review.selection.count, 1)
    }

    func testCancelStopsCheckingAndNothingIsImported() async throws {
        let provider = ReviewPhotosProvider(payloads: [0: Data([1]), 1: Data([2])])
        let review = PhotosImportReviewCoordinator()
        let gate = AsyncStream<Void>.makeStream()
        review.libraryMatcherLoader = {
            for await _ in gate.stream { break }
            return LibraryMembershipMatcher(knownHashes: [LibraryMembershipMatcher.contentHash(of: Data([1]))])
        }
        var imported = false
        review.onImport = { _, _ in imported = true }

        review.begin(selections: selections(2), provider: provider)
        review.cancel()
        gate.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(review.isPresented)
        XCTAssertFalse(review.isChecking)
        XCTAssertTrue(review.inLibrary.isEmpty)
        XCTAssertTrue(provider.transferred.isEmpty)
        XCTAssertFalse(imported)
    }

    /// A tagged Photos item imports as a duplicate and an untagged one does not.
    func testDataDigestAgreesWithPackageImportDuplicateDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-photos-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let packageURL = root.appendingPathComponent("Library.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let existing = Data(repeating: 0x21, count: 3000)
        let fresh = Data(repeating: 0x22, count: 3000)
        let existingURL = root.appendingPathComponent("existing.raw")
        try existing.write(to: existingURL)
        _ = try package.importSources([.init(url: existingURL)], lease: lease)

        let matcher = try LibraryMembershipMatcher(package: package)
        XCTAssertTrue(matcher.contains(contentHash: LibraryMembershipMatcher.contentHash(of: existing)))
        XCTAssertFalse(matcher.contains(contentHash: LibraryMembershipMatcher.contentHash(of: fresh)))

        let renamedURL = root.appendingPathComponent("IMG_9999.raw")
        let freshURL = root.appendingPathComponent("fresh.raw")
        try existing.write(to: renamedURL)
        try fresh.write(to: freshURL)
        let result = try package.importSources(
            [.init(url: renamedURL), .init(url: freshURL)], lease: lease
        )
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertEqual(result.imported.count, 1)
        XCTAssertEqual(
            LibraryMembershipMatcher.contentHash(of: existing),
            try LibraryMembershipMatcher.contentHash(of: existingURL)
        )
    }

    func testCancellingTheCatalogLoadReleasesTheCaller() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-matcher-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try PortableLibraryPackage.create(
            at: root.appendingPathComponent("Library.kromoralibrary"))

        let task = Task { try await LibraryMembershipMatcher.load(from: package) }
        task.cancel()
        do {
            _ = try await task.value
        } catch is CancellationError {
            return
        }
        // The detached read may have won the race; either outcome returns control to the caller.
    }
}
