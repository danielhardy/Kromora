import XCTest

@testable import KromoraKit

@MainActor
final class LUTLibraryTests: TempDirectoryTestCase {
    private func makeLibrary() -> LUTLibrary { makeLUTLibrary() }

    private func scan(_ library: LUTLibrary, _ folder: URL) async throws -> LookLibraryDelta {
        var delivered: LookLibraryDelta?
        library.onScanned = { delivered = $0 }
        library.scan(folder)
        let deadline = Date().addingTimeInterval(5)
        while delivered == nil {
            if Date() > deadline { throw TestSynchronizationError.timedOut("scan", "no delta") }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(delivered)
    }

    private func lookFolder() throws -> URL {
        let folder = tempDirectory.appendingPathComponent("looks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Pure snapshot delta

    func testDeltaClassifiesChangedAppearedAndDisappeared() {
        let a = LUTID(raw: "/a"), b = LUTID(raw: "/b"), c = LUTID(raw: "/c"), d = LUTID(raw: "/d")
        let before = LookLibrarySnapshot(contentHashes: [a: "1", b: "1", c: "1"])
        let after = LookLibrarySnapshot(contentHashes: [a: "1", b: "2", d: "1"])

        let delta = after.delta(from: before)
        XCTAssertEqual(delta.changed, [b])
        XCTAssertEqual(delta.appeared, [d])
        XCTAssertEqual(delta.disappeared, [c])
        XCTAssertEqual(delta.affected, [b, c, d])
        XCTAssertFalse(delta.isEmpty)
    }

    func testIdenticalSnapshotsProduceAnEmptyDelta() {
        let snapshot = LookLibrarySnapshot(contentHashes: [LUTID(raw: "/a"): "1"])
        XCTAssertTrue(snapshot.delta(from: snapshot).isEmpty)
        XCTAssertTrue(LookLibrarySnapshot.empty.delta(from: .empty).isEmpty)
    }

    // MARK: - Library scans

    func testACompletedScanPublishesAContentHashSnapshot() async throws {
        let folder = try lookFolder()
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "A.cube", in: folder)
        let library = makeLibrary()

        let delta = try await scan(library, folder)

        let lut = try CubeLUT(url: url)
        XCTAssertEqual(library.snapshot.contentHashes, [lut.lutID: lut.contentHash])
        XCTAssertEqual(delta.appeared, [lut.lutID])
        XCTAssertTrue(delta.changed.isEmpty)
        XCTAssertTrue(delta.disappeared.isEmpty)
    }

    func testAnUnchangedRescanReportsAnEmptyDelta() async throws {
        let folder = try lookFolder()
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "A.cube", in: folder)
        let library = makeLibrary()
        _ = try await scan(library, folder)
        let snapshot = library.snapshot

        let second = try await scan(library, folder)

        XCTAssertTrue(second.isEmpty, "identical bytes must not look like a change")
        XCTAssertEqual(library.snapshot, snapshot)
    }

    func testReplacingBytesAtTheSamePathIsAChangeNotANewLook() async throws {
        let folder = try lookFolder()
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "A.cube", in: folder)
        let library = makeLibrary()
        _ = try await scan(library, folder)
        let id = try CubeLUT(url: url).lutID

        try Fixtures.writeCube(Fixtures.identityCubeText(size: 3), named: "A.cube", in: folder)
        let delta = try await scan(library, folder)

        XCTAssertEqual(delta.changed, [id])
        XCTAssertTrue(delta.appeared.isEmpty)
        XCTAssertTrue(delta.disappeared.isEmpty)
        XCTAssertEqual(library.snapshot.contentHashes[id], try CubeLUT(url: url).contentHash)
    }

    func testAnAddedAndARemovedLookAreReportedByID() async throws {
        let folder = try lookFolder()
        let keptURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Kept.cube", in: folder)
        let goneURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Gone.cube", in: folder)
        let library = makeLibrary()
        _ = try await scan(library, folder)
        let goneID = try CubeLUT(url: goneURL).lutID

        try FileManager.default.removeItem(at: goneURL)
        let newURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2, title: "new"), named: "New.cube", in: folder)
        let delta = try await scan(library, folder)

        XCTAssertEqual(delta.disappeared, [goneID])
        XCTAssertEqual(delta.appeared, [try CubeLUT(url: newURL).lutID])
        XCTAssertFalse(delta.affected.contains(try CubeLUT(url: keptURL).lutID),
                       "an untouched Look must stay out of the delta")
    }

    func testAFailedScanReportsEveryPreviouslyKnownLookAsDisappeared() async throws {
        let folder = try lookFolder()
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "A.cube", in: folder)
        let library = makeLibrary()
        _ = try await scan(library, folder)
        let id = try CubeLUT(url: url).lutID

        try FileManager.default.removeItem(at: folder)
        let delta = try await scan(library, folder)

        XCTAssertEqual(delta.disappeared, [id])
        XCTAssertTrue(library.snapshot.contentHashes.isEmpty)
    }
}
