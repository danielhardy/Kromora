import XCTest

@testable import KromoraKit

@MainActor
final class PhotosReviewTransferCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotosReviewCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Simulates the Photos resource transfer: counts fetches per ordinal and writes `size` bytes.
    private final class Origin {
        var fetches: [Int: Int] = [:]
        func fetch(_ ordinal: Int, size: Int) -> (URL) async throws -> Void {
            { [self] url in
                fetches[ordinal, default: 0] += 1
                try Data(repeating: UInt8(ordinal), count: size).write(to: url)
            }
        }
    }

    func testConfirmedItemsWithinTheBoundAreTransferredOnce() async throws {
        let cache = PhotosReviewTransferCache(byteLimit: 100, directory: directory)
        let origin = Origin()
        for ordinal in 0..<2 {
            let data = try await cache.inspect(ordinal: ordinal, fetch: origin.fetch(ordinal, size: 40))
            XCTAssertEqual(data?.count, 40)
        }
        cache.discard(keeping: [0, 1])
        XCTAssertEqual(cache.consume(ordinal: 0)?.count, 40)
        XCTAssertEqual(cache.consume(ordinal: 1)?.count, 40)
        XCTAssertEqual(origin.fetches, [0: 1, 1: 1])
        XCTAssertEqual(cache.retainedBytes, 0)
    }

    func testReviewStopsTransferringAtTheBoundSoLaterItemsAreFetchedOnlyAtImport() async throws {
        let cache = PhotosReviewTransferCache(byteLimit: 100, directory: directory)
        let origin = Origin()
        // 60 + 60 crosses the bound; the crossing item is kept, the third is never transferred.
        for ordinal in 0..<2 {
            let data = try await cache.inspect(ordinal: ordinal, fetch: origin.fetch(ordinal, size: 60))
            XCTAssertNotNil(data)
        }
        XCTAssertEqual(cache.retainedBytes, 120)
        let beyond = try await cache.inspect(ordinal: 2, fetch: origin.fetch(2, size: 60))
        XCTAssertNil(beyond)
        XCTAssertNil(origin.fetches[2])

        // Import: retained items come from the cache, the uninspected one is the single fetch.
        XCTAssertNotNil(cache.consume(ordinal: 0))
        XCTAssertNotNil(cache.consume(ordinal: 1))
        XCTAssertNil(cache.consume(ordinal: 2))
        try await origin.fetch(2, size: 60)(directory.appendingPathComponent("import"))
        XCTAssertEqual(origin.fetches, [0: 1, 1: 1, 2: 1])
    }

    func testExactlyAtTheBoundStopsFurtherTransfers() async throws {
        let cache = PhotosReviewTransferCache(byteLimit: 100, directory: directory)
        let origin = Origin()
        _ = try await cache.inspect(ordinal: 0, fetch: origin.fetch(0, size: 100))
        let next = try await cache.inspect(ordinal: 1, fetch: origin.fetch(1, size: 1))
        XCTAssertNil(next)
        XCTAssertNil(origin.fetches[1])
    }

    func testRepeatedInspectionReusesTheRetainedTransfer() async throws {
        let cache = PhotosReviewTransferCache(byteLimit: 100, directory: directory)
        let origin = Origin()
        _ = try await cache.inspect(ordinal: 0, fetch: origin.fetch(0, size: 10))
        _ = try await cache.inspect(ordinal: 0, fetch: origin.fetch(0, size: 10))
        XCTAssertEqual(origin.fetches[0], 1)
        XCTAssertEqual(cache.retainedBytes, 10)
    }

    func testDeselectedAndCancelledItemsLeaveNoFiles() async throws {
        let cache = PhotosReviewTransferCache(byteLimit: 1000, directory: directory)
        let origin = Origin()
        for ordinal in 0..<3 { _ = try await cache.inspect(ordinal: ordinal, fetch: origin.fetch(ordinal, size: 10)) }
        cache.discard(keeping: [1])
        XCTAssertEqual(cache.retainedOrdinals, [1])
        XCTAssertEqual(cache.retainedBytes, 10)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["1"])
        cache.discard(keeping: [])
        XCTAssertEqual(cache.retainedBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testFailedTransferLeavesNoFileAndIsNotCounted() async throws {
        let cache = PhotosReviewTransferCache(byteLimit: 100, directory: directory)
        struct Boom: Error {}
        do {
            _ = try await cache.inspect(ordinal: 0) { url in
                try Data([1]).write(to: url)
                throw Boom()
            }
            XCTFail("expected failure")
        } catch is Boom {}
        XCTAssertEqual(cache.retainedBytes, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }
}
