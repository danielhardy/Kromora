import Foundation

/// Where the library package is in its open: not started, opening off the main actor, bound, or
/// failed. Library-dependent commands are available only in `.ready`.
enum LibraryOpenState: Equatable, Sendable {
    case idle
    case opening
    case ready
    case failed(String)
}

/// Owns the asynchronous open of the library package after the first window exists: the optional
/// takeover question, the off-main-actor open, binding on the main actor, and cancellation.
@MainActor
final class LibraryOpenCoordinator {
    private(set) var state: LibraryOpenState
    /// Called after every change of ``state``.
    var onStateChange: (@MainActor (LibraryOpenState) -> Void)?

    private let opener: any PackageOpening
    private var task: Task<Void, Never>?
    /// True while the task waits on the takeover question. No lease exists yet, and the question
    /// is a sheet that cannot be cancelled from here, so shutdown does not wait for it.
    private var isAwaitingDecision = false

    init(opener: any PackageOpening, state: LibraryOpenState = .idle) {
        self.opener = opener
        self.state = state
    }

    private func set(_ newState: LibraryOpenState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }

    /// Starts the open. `takeOver` answers the expired-lease question and `bind` turns the opened
    /// package into the finished library state; it runs on the main actor and owns the lease from
    /// then on (including releasing it when it fails). Repeated calls while opening share the task.
    @discardableResult
    func start(
        at url: URL,
        takeOver: @escaping @MainActor () async -> Bool,
        bind: @escaping @MainActor (OpenedPackage) async -> LibraryOpenState
    ) -> Task<Void, Never> {
        if let task, state == .opening { return task }
        set(.opening)
        isAwaitingDecision = true
        let opener = opener
        let task = Task { @MainActor [weak self] in
            let allowed = await takeOver()
            self?.isAwaitingDecision = false
            guard !Task.isCancelled else { return }
            let opened: OpenedPackage
            do {
                opened = try await opener.open(at: url, allowsExpiredLeaseTakeover: allowed)
            } catch {
                guard !Task.isCancelled else { return }
                self?.set(
                    .failed(
                        "Kromora could not open its library package at \(url.path): "
                            + error.localizedDescription))
                return
            }
            // The blocking open could not observe cancellation, so a cancelled open lands here
            // with a lease it must give back rather than bind.
            guard !Task.isCancelled, let self else {
                opened.releaseUnbound()
                return
            }
            self.set(await bind(opened))
        }
        self.task = task
        return task
    }

    /// Cancels an in-flight open and waits until it has bound or released its lease. After this
    /// returns, no unbound lease is held on behalf of this coordinator.
    func cancelAndWait() async {
        guard let task else { return }
        task.cancel()
        if isAwaitingDecision { return }
        await task.value
    }
}
