import AppKit

enum SaveFailureChoice {
    case retry
    case discard
    case cancel
}

/// Flushes and releases a library after a relaunch confirmation. The injected operations keep the
/// failed-save decision path testable without presenting a real AppKit alert.
@MainActor
enum LibraryReleaseFlow {
    static func flushAndRelease(
        flush: @MainActor () async -> PersistenceFlushResult,
        chooseAfterFailure: @MainActor (PersistenceFlushResult) -> SaveFailureChoice,
        discard: @MainActor () async -> Void,
        shutdown: @MainActor () async -> Void
    ) async -> LibraryReleaseOutcome {
        var outcome = LibraryReleaseOutcome.released
        while true {
            let result = await flush()
            if case .success = result { break }
            switch chooseAfterFailure(result) {
            case .retry:
                continue
            case .discard:
                await discard()
                outcome = .releasedWithoutSaving
            case .cancel:
                return .declined
            }
            break
        }
        await shutdown()
        return outcome
    }
}

/// Shared application lifecycle behavior for each Kromora launcher.
@MainActor
public final class KromoraAppDelegate: NSObject, NSApplicationDelegate {
    let launch: AppLaunch
    private let appearanceController: KromoraWindowAppearanceController
    private var terminationFlushInProgress = false
    /// Set once the library has been flushed and shut down for a relaunch, so the quit that follows
    /// does not repeat the confirmation and flush against a closed model.
    private var libraryReleased = false
    var quitConfirmation: any QuitConfirmationPresenting = AppKitQuitConfirmation()
    private var viewModel: AppViewModel? { launch.viewModel }

    public override init() {
        // Kromora is a single-window editor. Automatic window tabbing inserts
        // Hide Tab Bar / Show All Tabs into the View menu before scenes build.
        NSWindow.allowsAutomaticWindowTabbing = false
        Self.promoteUnbundledLaunchIfNeeded()
        let launch = AppLaunch()
        self.launch = launch
        self.appearanceController = KromoraWindowAppearanceController(settings: launch.settings)
        super.init()
    }

    /// Whether the process needs to promote itself to a regular, frontmost app. Only an unbundled
    /// launch (`swift run`) does: it has no `Info.plist`, so it starts as a background process.
    nonisolated static func needsUnbundledActivation(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == nil
    }

    /// Makes an unbundled `swift run` process a regular app before `AppLaunch` can raise the launch
    /// lease-recovery sheet. Without it the sheet stays invisible and the terminal, after printing
    /// "Build complete!", appears hung. A bundled app is already regular through its `Info.plist`.
    private static func promoteUnbundledLaunchIfNeeded(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard needsUnbundledActivation(bundleIdentifier: bundleIdentifier) else { return }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit adds Hide Tab Bar and Show All Tabs while building the main menu.
        // The flag has to be false by then, not only before the first window exists.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        appearanceController.start()
        NSApp.activate()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the single-window editor's close behavior. AppKit then routes the close through
        // applicationShouldTerminate below, where the asynchronous confirmation and flush finish.
        true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if libraryReleased { return .terminateNow }
        guard !terminationFlushInProgress else { return .terminateLater }
        // The model is created by the first frame's `.task`, so a quit before that has nothing to
        // flush and no lease to release. Once it exists, `shutdown()` also cancels an open still in
        // flight and releases its lease, so quitting mid-open goes through the same path.
        guard let viewModel else { return .terminateNow }
        terminationFlushInProgress = true
        // Confirmation is a sheet, so the reply is deferred until it is answered.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await viewModel.terminationGuard.shouldQuit(presenter: quitConfirmation) else {
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            let result = await viewModel.flushPendingWrites()
            await handleTerminationFlushResult(result, sender: sender, viewModel: viewModel)
        }
        return .terminateLater
    }

    private func handleTerminationFlushResult(
        _ result: PersistenceFlushResult,
        sender: NSApplication,
        viewModel: AppViewModel
    ) async {
        guard case .success = result else {
            switch askSaveFailure(for: result) {
            case .retry:
                terminationFlushInProgress = false
                startTerminationFlush(sender, viewModel: viewModel)
            case .discard:
                await viewModel.discardPendingWrites()
                await viewModel.shutdown()
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: true)
            case .cancel:
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: false)
            }
            return
        }

        await viewModel.shutdown()
        sender.reply(toApplicationShouldTerminate: true)
    }

    /// App-modal on purpose: this runs while the app is quitting or relaunching, when the window may
    /// already be gone, and the answer decides whether the process goes on.
    private func askSaveFailure(for result: PersistenceFlushResult) -> SaveFailureChoice {
        let alert = NSAlert()
        alert.messageText = "Couldn’t save edits before quitting"
        alert.informativeText = terminationFailureMessage(for: result)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry Saving")
        alert.addButton(withTitle: "Quit Without Saving")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Confirms, flushes pending edits and culling state, and shuts the model down so the package
    /// lease is released, for a relaunch. Returns `.declined`, leaving the app running, when the user
    /// declines or cancels. Quit Without Saving after a failed flush closes the library but returns
    /// `.releasedWithoutSaving`, which never authorizes a replacement. After either release the model
    /// is closed and the next quit proceeds directly.
    func flushAndReleaseLibrary() async -> LibraryReleaseOutcome {
        if libraryReleased { return .released }
        guard !terminationFlushInProgress else { return .declined }
        guard let viewModel else {
            libraryReleased = true
            return .released
        }
        terminationFlushInProgress = true
        defer { terminationFlushInProgress = false }
        guard await viewModel.terminationGuard.shouldQuit(presenter: quitConfirmation) else { return .declined }
        let outcome = await LibraryReleaseFlow.flushAndRelease(
            flush: { await viewModel.flushPendingWrites() },
            chooseAfterFailure: { self.askSaveFailure(for: $0) },
            discard: { await viewModel.discardPendingWrites() },
            shutdown: { await viewModel.shutdown() }
        )
        if outcome != .declined { libraryReleased = true }
        return outcome
    }

    private func startTerminationFlush(_ sender: NSApplication, viewModel: AppViewModel) {
        terminationFlushInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await viewModel.flushPendingWrites()
            await handleTerminationFlushResult(result, sender: sender, viewModel: viewModel)
        }
    }

    private func terminationFailureMessage(for result: PersistenceFlushResult) -> String {
        switch result {
        case .failure(let detail):
            return "\(detail)\n\nRetry saving, quit without saving these edits, or cancel quitting."
        case .cancelled:
            return "Saving edits was cancelled before all changes were written.\n\nRetry saving, quit without saving these edits, or cancel quitting."
        case .success:
            return "All edits were saved."
        }
    }
}
