import XCTest
@testable import KromoraKit

final class ReviewPromptPolicyTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "KromoraKitTests.ReviewPrompt-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    func testOutcomeQualification() {
        typealias Outcome = ExportCoordinator.BatchOutcome
        XCTAssertTrue(ReviewPromptPolicy.qualifies(Outcome(exported: 1, failed: 0, total: 1, editedExportCount: 1)))
        XCTAssertFalse(ReviewPromptPolicy.qualifies(Outcome(exported: 1, failed: 0, total: 1)))
        XCTAssertFalse(ReviewPromptPolicy.qualifies(Outcome(exported: 1, failed: 1, total: 2, editedExportCount: 1)))
        XCTAssertFalse(ReviewPromptPolicy.qualifies(Outcome(exported: 1, failed: 0, total: 2, cancelled: true, editedExportCount: 1)))
        XCTAssertFalse(ReviewPromptPolicy.qualifies(Outcome(exported: 1, failed: 0, total: 1, photosFailed: 1, editedExportCount: 1)))
        XCTAssertFalse(ReviewPromptPolicy.qualifies(Outcome(exported: 0, failed: 0, total: 0, editedExportCount: 0)))
    }

    func testFirstAndSameLaunchFinishesStaySilent() {
        let policy = ReviewPromptPolicy(defaults: makeDefaults())
        policy.recordLaunch()
        XCTAssertFalse(policy.recordQualifyingFinish())
        XCTAssertFalse(policy.recordQualifyingFinish())
    }

    func testSecondFinishOnLaterLaunchMayAsk() {
        let defaults = makeDefaults()
        let first = ReviewPromptPolicy(defaults: defaults)
        first.recordLaunch()
        XCTAssertFalse(first.recordQualifyingFinish())
        let second = ReviewPromptPolicy(defaults: defaults)
        second.recordLaunch()
        XCTAssertTrue(second.recordQualifyingFinish())
    }

    func testRequestSpacingIs120Days() {
        let defaults = makeDefaults()
        var date = Date(timeIntervalSince1970: 1_000_000)
        let policy = ReviewPromptPolicy(defaults: defaults, now: { date })
        policy.recordLaunch()
        _ = policy.recordQualifyingFinish()
        policy.recordLaunch()
        XCTAssertTrue(policy.recordQualifyingFinish())
        policy.recordRequest()
        date.addTimeInterval(119 * 86_400)
        XCTAssertFalse(policy.recordQualifyingFinish())
        date.addTimeInterval(2 * 86_400)
        XCTAssertTrue(policy.recordQualifyingFinish())
    }
}

@MainActor
final class ReviewPromptWiringTests: TempDirectoryTestCase {
    private let edited = ExportCoordinator.BatchOutcome(
        exported: 1, failed: 0, total: 1, editedExportCount: 1)

    private func defaultsWithPriorFinish() -> UserDefaults {
        let defaults = makeTestUserDefaults()
        FirstRunOnboarding.markWelcomeSeen(in: defaults)
        let prior = ReviewPromptPolicy(defaults: defaults)
        prior.recordLaunch()
        _ = prior.recordQualifyingFinish()
        return defaults
    }

    func testSettledEditedExportOnLaterLaunchAsksOnce() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter)
        viewModel.exportBatchSettled(edited)
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(500))
        XCTAssertEqual(presenter.requestCount, 1)
        viewModel.exportBatchSettled(edited)
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(500))
        XCTAssertEqual(presenter.requestCount, 1, "within 120 days")
    }

    func testCoveredAppCountsButDoesNotAsk() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter,
            isCoveredByUI: true)
        viewModel.exportBatchSettled(edited)
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(500))
        XCTAssertEqual(presenter.requestCount, 0)
    }

    func testErrorCancelsPendingAsk() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter)
        viewModel.exportBatchSettled(edited)
        viewModel.presentError("boom")
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(500))
        XCTAssertEqual(presenter.requestCount, 0)
    }

    func testSheetPresentationCancelsPendingAsk() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter)
        viewModel.exportBatchSettled(edited)
        viewModel.cancelPendingReviewPrompt()
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(100))
        XCTAssertEqual(presenter.requestCount, 0)
    }

    func testNewExportCancelsPendingAsk() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter)
        viewModel.exportBatchSettled(edited)
        viewModel.export.onActivityChanged?(true)
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(100))
        XCTAssertEqual(presenter.requestCount, 0)
    }

    func testShutdownCancelsPendingAsk() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter)
        viewModel.exportBatchSettled(edited)
        await viewModel.shutdown()
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(100))
        XCTAssertEqual(presenter.requestCount, 0)
    }

    func testExternalEditorCompletionDoesNotAsk() async throws {
        let presenter = FakeReviewPresenter()
        let viewModel = makeAppViewModel(
            preferences: defaultsWithPriorFinish(), reviewPresenter: presenter)
        viewModel.export.onExportCompleted?(tempDirectory.appendingPathComponent("x.tiff"))
        try await Task.sleep(for: AppViewModel.reviewPromptDelay + .milliseconds(500))
        XCTAssertEqual(presenter.requestCount, 0)
    }
}
