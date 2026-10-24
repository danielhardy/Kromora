import AppKit
import Foundation
import StoreKit

/// The system call behind the policy, so tests never present the real sheet.
@MainActor
protocol ReviewPromptPresenting {
    /// Returns whether a request was actually made.
    func requestReview() -> Bool
}

@MainActor
struct SystemReviewPromptPresenter: ReviewPromptPresenting {
    func requestReview() -> Bool {
        // On macOS the API is scoped to a view controller, not a scene.
        guard let controller = NSApp.keyWindow?.contentViewController else { return false }
        AppStore.requestReview(in: controller)
        return true
    }
}

/// Counts clean edited exports and, when the policy and quiet-app gates allow, asks the system for
/// a review about a second later. A busy app is never retried later.
@MainActor
final class ReviewPromptCoordinator {
    static let delay: Duration = .seconds(1)

    /// Whether a sheet, modal, or inactive app is covering the window.
    static let isWindowCovered: () -> Bool = {
        !NSApp.isActive || NSApp.keyWindow == nil
            || NSApp.windows.contains { $0.attachedSheet != nil }
            || NSApp.modalWindow != nil
    }

    private let policy: ReviewPromptPolicy
    private let presenter: any ReviewPromptPresenting
    private let canRequestNow: () -> Bool
    private var task: Task<Void, Never>?

    init(
        policy: ReviewPromptPolicy,
        presenter: any ReviewPromptPresenting,
        canRequestNow: @escaping () -> Bool
    ) {
        self.policy = policy
        self.presenter = presenter
        self.canRequestNow = canRequestNow
    }

    func batchSettled(_ outcome: ExportCoordinator.BatchOutcome) {
        guard ReviewPromptPolicy.qualifies(outcome), policy.recordQualifyingFinish(),
              canRequestNow() else { return }
        cancelPending()
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let self else { return }
            self.task = nil
            guard self.canRequestNow() else { return }
            if self.presenter.requestReview() { self.policy.recordRequest() }
        }
    }

    /// A presentation that starts during the settling delay makes this finish ineligible. Do not
    /// retain the task so dismissing that presentation cannot trigger a delayed request.
    func cancelPending() {
        task?.cancel()
        task = nil
    }
}
