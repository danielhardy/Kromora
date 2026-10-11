import XCTest

@testable import KromoraKit

@MainActor
final class StoredEditAdoptionCoordinatorTests: XCTestCase {
    private func context(
        request: UInt64 = 1, current: UInt64 = 1, hadSession: Bool = false,
        changed: Bool = false, differs: Bool = true, scheduled: Bool = false
    ) -> StoredEditAdoptionCoordinator.Context {
        .init(
            requestSourceRevision: request, currentSourceRevision: current,
            hadInMemorySession: hadSession, changedInMemory: changed,
            storedDocumentDiffers: differs, speculativeRenderScheduled: scheduled)
    }

    func testEarlyAdoptionThenLateOwesCorrectiveRenderWhenSpeculativeRenderScheduled() {
        let sut = StoredEditAdoptionCoordinator()
        XCTAssertEqual(sut.decideEarlyAdoption(context(scheduled: true)), .adopt)
        XCTAssertTrue(sut.isResolved(for: 1))
        let late = sut.decideLateAdoption(context(), hasDeferredSettledPreview: false)
        XCTAssertTrue(late.adoptedEarly)
        XCTAssertTrue(late.shouldAdopt)
        XCTAssertTrue(late.documentChanged)
        XCTAssertEqual(late.followUp, .correctivePreview)
    }

    func testEarlyAdoptionBeforeAnyRenderOwesNoCorrectiveRender() {
        let sut = StoredEditAdoptionCoordinator()
        XCTAssertEqual(sut.decideEarlyAdoption(context(scheduled: false)), .adopt)
        let late = sut.decideLateAdoption(context(), hasDeferredSettledPreview: true)
        XCTAssertTrue(late.shouldAdopt)
        XCTAssertFalse(late.documentChanged)
        XCTAssertEqual(late.followUp, .resumeDeferredSettledPreview)
    }

    func testEditAfterEarlyAdoptionOwnsTheDocument() {
        let sut = StoredEditAdoptionCoordinator()
        _ = sut.decideEarlyAdoption(context(scheduled: true))
        let late = sut.decideLateAdoption(context(changed: true), hasDeferredSettledPreview: false)
        XCTAssertTrue(late.shouldAdopt)
        XCTAssertFalse(late.documentChanged)
        XCTAssertEqual(late.followUp, .reconcilePresentedFrame)
    }

    func testEarlyAdoptionIsSkippedOnceReconciled() {
        let sut = StoredEditAdoptionCoordinator()
        _ = sut.decideLateAdoption(context(), hasDeferredSettledPreview: false)
        XCTAssertEqual(sut.decideEarlyAdoption(context()), .skip)
    }

    func testInMemorySessionWinsInBothStages() {
        let sut = StoredEditAdoptionCoordinator()
        XCTAssertEqual(sut.decideEarlyAdoption(context(hadSession: true)), .skip)
        XCTAssertFalse(sut.isResolved(for: 1))
        let late = sut.decideLateAdoption(context(hadSession: true), hasDeferredSettledPreview: false)
        XCTAssertFalse(late.shouldAdopt)
        XCTAssertFalse(late.documentChanged)
        XCTAssertEqual(late.followUp, .reconcilePresentedFrame)
        XCTAssertTrue(sut.isResolved(for: 1))
    }

    func testMutationWhileLoadingWinsInBothStages() {
        let sut = StoredEditAdoptionCoordinator()
        XCTAssertEqual(sut.decideEarlyAdoption(context(changed: true)), .skip)
        let late = sut.decideLateAdoption(context(changed: true), hasDeferredSettledPreview: true)
        XCTAssertFalse(late.shouldAdopt)
        XCTAssertEqual(late.followUp, .resumeDeferredSettledPreview)
    }

    func testLateAdoptionWithoutEarlyAdoptsDifferingDocument() {
        let sut = StoredEditAdoptionCoordinator()
        let late = sut.decideLateAdoption(context(), hasDeferredSettledPreview: true)
        XCTAssertFalse(late.adoptedEarly)
        XCTAssertTrue(late.shouldAdopt)
        XCTAssertTrue(late.documentChanged)
        XCTAssertEqual(late.followUp, .correctivePreview)
        let same = StoredEditAdoptionCoordinator().decideLateAdoption(
            context(differs: false), hasDeferredSettledPreview: false)
        XCTAssertTrue(same.shouldAdopt)
        XCTAssertFalse(same.documentChanged)
    }

    func testEarlyRecordForStaleSourceIsNotConsumed() {
        let sut = StoredEditAdoptionCoordinator()
        _ = sut.decideEarlyAdoption(context(request: 1, current: 1, scheduled: true))
        let late = sut.decideLateAdoption(
            context(request: 2, current: 2, hadSession: true), hasDeferredSettledPreview: false)
        XCTAssertFalse(late.adoptedEarly)
        XCTAssertFalse(late.shouldAdopt)
    }

    func testResetClearsResolvedRevision() {
        let sut = StoredEditAdoptionCoordinator()
        _ = sut.decideLateAdoption(context(), hasDeferredSettledPreview: false)
        sut.reset()
        XCTAssertNil(sut.resolvedSourceRevision)
    }
}
