import AppKit

/// Shared application lifecycle behavior for each Kromora launcher.
@MainActor
public final class KromoraAppDelegate: NSObject, NSApplicationDelegate {
    let launch: AppLaunch
    private let appearanceController: KromoraWindowAppearanceController
    private var terminationFlushInProgress = false
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
            let alert = NSAlert()
            alert.messageText = "Couldn’t save edits before quitting"
            alert.informativeText = terminationFailureMessage(for: result)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Retry Saving")
            alert.addButton(withTitle: "Quit Without Saving")
            alert.addButton(withTitle: "Cancel")

            // App-modal on purpose: this runs while the app is quitting, when the window may already
            // be gone, and the answer decides whether termination proceeds.
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                terminationFlushInProgress = false
                startTerminationFlush(sender, viewModel: viewModel)
            case .alertSecondButtonReturn:
                await viewModel.discardPendingWrites()
                await viewModel.shutdown()
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: true)
            default:
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: false)
            }
            return
        }

        await viewModel.shutdown()
        sender.reply(toApplicationShouldTerminate: true)
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
