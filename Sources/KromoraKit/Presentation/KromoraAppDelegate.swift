import AppKit

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
        // Unbundled `swift run` starts as a background process. The launch lease-recovery sheet
        // would otherwise stay invisible — the terminal prints "Build complete!" and appears hung.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate()
        let launch = AppLaunch()
        self.launch = launch
        self.appearanceController = KromoraWindowAppearanceController(settings: launch.settings)
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit adds Hide Tab Bar and Show All Tabs while building the main menu.
        // The flag has to be false by then, not only before the first window exists.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        appearanceController.start()
        NSApp.setActivationPolicy(.regular)
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

    private enum SaveFailureChoice { case retry, discard, cancel }

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
    /// lease is released, for a relaunch. Returns `false`, leaving the app running, when the user
    /// declines or cancels. After `true` the model is closed and the next quit proceeds directly.
    func flushAndReleaseLibrary() async -> Bool {
        if libraryReleased { return true }
        guard !terminationFlushInProgress else { return false }
        guard let viewModel else {
            libraryReleased = true
            return true
        }
        terminationFlushInProgress = true
        defer { terminationFlushInProgress = false }
        guard await viewModel.terminationGuard.shouldQuit(presenter: quitConfirmation) else { return false }
        while true {
            let result = await viewModel.flushPendingWrites()
            if case .success = result { break }
            switch askSaveFailure(for: result) {
            case .retry: continue
            case .discard: await viewModel.discardPendingWrites()
            case .cancel: return false
            }
            break
        }
        await viewModel.shutdown()
        libraryReleased = true
        return true
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
