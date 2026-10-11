import Foundation
import XCTest

@testable import KromoraKit

final class LibraryMembershipMatcherTests: TempDirectoryTestCase {
    private func makeSource(_ name: String, _ contents: Data) throws -> MediaVolumeFile {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url)
        return MediaVolumeFile(url: url)
    }

    /// The tag must agree with import: tagged files import as duplicates, untagged files do not.
    func testMatcherAgreesWithImportTimeDuplicateDetection() throws {
        let packageURL = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let existing = try makeSource("existing.raw", Data(repeating: 0x21, count: 3000))
        _ = try package.importSources([.init(url: existing.url)], lease: lease)

        // Same bytes under a different name and folder: still a member. Different bytes: not.
        let renamed = try makeSource("IMG_0001-copy.raw", Data(repeating: 0x21, count: 3000))
        let fresh = try makeSource("fresh.raw", Data(repeating: 0x22, count: 3000))
        let sameSizeOtherBytes = try makeSource("near.raw", Data(repeating: 0x21, count: 2999))

        let matcher = try LibraryMembershipMatcher(package: package)
        let members = matcher.memberIDs(in: [renamed, fresh, sameSizeOtherBytes])
        XCTAssertEqual(members, [renamed.id])

        let result = try package.importSources(
            [renamed, fresh, sameSizeOtherBytes].map { .init(url: $0.url) }, lease: lease
        )
        XCTAssertEqual(Set(result.duplicates.map { $0.source.url.standardizedFileURL.path }), members)
        XCTAssertEqual(result.imported.count, 2)
    }

    func testEmptyLibraryAndUnreadableFilesAreNeverTagged() throws {
        let package = try PortableLibraryPackage.create(
            at: tempDirectory.appendingPathComponent("Empty.kromoralibrary"))
        let file = try makeSource("a.raw", Data([1, 2, 3]))
        XCTAssertTrue(try LibraryMembershipMatcher(package: package).memberIDs(in: [file]).isEmpty)

        let hash = try XCTUnwrap(LibraryMembershipMatcher.contentHash(of: file.url))
        let matcher = LibraryMembershipMatcher(knownHashes: [hash])
        let missing = MediaVolumeFile(url: tempDirectory.appendingPathComponent("gone.raw"))
        XCTAssertEqual(matcher.memberIDs(in: [file, missing]), [file.id])
    }

    func testCancellationStopsHashing() throws {
        let file = try makeSource("a.raw", Data([1, 2, 3]))
        let matcher = LibraryMembershipMatcher(knownHashes: [try XCTUnwrap(LibraryMembershipMatcher.contentHash(of: file.url))])
        XCTAssertTrue(matcher.memberIDs(in: [file], isCancelled: { true }).isEmpty)
    }

    func testDefaultSelectionExcludesLibraryItemsButKeepsExplicitChoices() {
        let files = ["a", "b", "c"].map { MediaVolumeFile(url: URL(fileURLWithPath: "/Volumes/C/\($0).jpg")) }
        var selection = MediaVolumeSelectionModel()
        selection.selectAll(in: files, excluding: [files[1].id])
        XCTAssertEqual(selection.selectedIDs, [files[0].id, files[2].id])

        // A late tag deselects an untouched default but not a file the user clicked.
        selection.selectAll(in: files)
        selection.toggle(files[0])   // off
        selection.toggle(files[0])   // back on, now explicit
        selection.deselectDefaults([files[0].id, files[1].id])
        XCTAssertEqual(selection.selectedIDs, [files[0].id, files[2].id])
    }
}
