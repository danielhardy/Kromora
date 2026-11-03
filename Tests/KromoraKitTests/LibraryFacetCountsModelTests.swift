import XCTest
@testable import KromoraKit

@MainActor
final class LibraryFacetCountsModelTests: XCTestCase {
    private func counts(_ unread: Int) -> LibraryFacetCounts {
        var result = LibraryFacetCounts()
        result.unreadCaptureSettingsCount = unread
        result.ranges[.aperture] = 1.4...8
        result.values[.camera] = [LibraryFacetValueCount(value: "Cam", count: unread)]
        return result
    }

    private func key(_ revision: UInt64) -> LibraryFacetCountsModel.Key {
        .init(query: .all, indexRevision: revision)
    }

    func testPublishesOneCoherentSnapshot() async {
        let model = LibraryFacetCountsModel()
        await model.refresh(for: key(1), debounce: .zero) { _ in self.counts(3) }
        XCTAssertEqual(model.counts, counts(3))
    }

    func testIndexRevisionChangeWithEqualQueryRecomputes() async {
        let model = LibraryFacetCountsModel()
        var current = 2
        await model.refresh(for: key(1), debounce: .zero) { _ in self.counts(current) }
        XCTAssertEqual(model.counts.unreadCaptureSettingsCount, 2)
        current = 0  // a metadata backfill completed with no filter change
        await model.refresh(for: key(2), debounce: .zero) { _ in self.counts(current) }
        XCTAssertEqual(model.counts.unreadCaptureSettingsCount, 0)
    }

    func testSupersededRequestCompletingLastIsIgnored() async {
        let model = LibraryFacetCountsModel()
        var releaseOld: CheckedContinuation<Void, Never>?
        let oldStarted = expectation(description: "old compute started")
        let old = Task { @MainActor in
            await model.refresh(for: self.key(1), debounce: .zero) { _ in
                oldStarted.fulfill()
                await withCheckedContinuation { releaseOld = $0 }
                return self.counts(1)
            }
        }
        await fulfillment(of: [oldStarted], timeout: 5)
        await model.refresh(for: key(2), debounce: .zero) { _ in self.counts(2) }
        XCTAssertEqual(model.counts.unreadCaptureSettingsCount, 2)
        releaseOld?.resume()
        await old.value
        XCTAssertEqual(model.counts.unreadCaptureSettingsCount, 2)
    }

    func testCancelledRequestDoesNotPublish() async {
        let model = LibraryFacetCountsModel()
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "compute started")
        let task = Task { @MainActor in
            await model.refresh(for: self.key(1), debounce: .zero) { _ in
                started.fulfill()
                await withCheckedContinuation { release = $0 }
                return self.counts(9)
            }
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        release?.resume()
        await task.value
        XCTAssertEqual(model.counts, LibraryFacetCounts())
    }

    func testBurstOfIndexChangesCoalescesIntoOneComputation() async {
        let model = LibraryFacetCountsModel()
        var computations = 0
        let tasks = (1...5).map { revision in
            Task { @MainActor in
                await model.refresh(for: self.key(UInt64(revision)), debounce: .milliseconds(100)) { _ in
                    computations += 1
                    return self.counts(revision)
                }
            }
        }
        for task in tasks { await task.value }
        XCTAssertEqual(computations, 1)
        XCTAssertEqual(model.counts.unreadCaptureSettingsCount, 5)
    }

    func testPresentationIndexRevisionAdvances() {
        let presentation = LibraryPresentationState()
        let start = presentation.indexRevision
        presentation.noteIndexChanged()
        XCTAssertEqual(presentation.indexRevision, start &+ 1)
    }
}
