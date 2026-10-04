import AppKit

/// Shared application lifecycle behavior for each Kromora launcher.
@MainActor
public final class KromoraAppDelegate: NSObject, NSApplicationDelegate {
    public let viewModel: AppViewModel
    private let appearanceController: KromoraWindowAppearanceController
    private var terminationFlushInProgress = false

    public override init() {
        // Kromora is a single-window editor. Automatic window tabbing inserts
        // Hide Tab Bar / Show All Tabs into the View menu before scenes build.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Unbundled `swift run` starts as a background process. AppViewModel init can present a
        // lease-recovery NSAlert before applicationDidFinishLaunching, and that alert is otherwise
        // invisible — the terminal prints "Build complete!" and appears hung.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let viewModel = AppViewModel(includeBundledLooks: true)
        self.viewModel = viewModel
        self.appearanceController = KromoraWindowAppearanceController(settings: viewModel.settings)
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
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // AppKit routes the last-window close through applicationShouldTerminate below, where
        // `.terminateLater` remains pending until the edit and frame-store flushes finish.
        true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationFlushInProgress else { return .terminateLater }
        terminationFlushInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await viewModel.flushPendingWrites()
            await handleTerminationFlushResult(result, sender: sender)
        }
        return .terminateLater
    }

    private func handleTerminationFlushResult(
        _ result: PersistenceFlushResult,
        sender: NSApplication
    ) async {
        guard case .success = result else {
            let alert = NSAlert()
            alert.messageText = "Couldn’t save edits before quitting"
            alert.informativeText = terminationFailureMessage(for: result)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Retry Saving")
            alert.addButton(withTitle: "Quit Without Saving")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                terminationFlushInProgress = false
                startTerminationFlush(sender)
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

    private func startTerminationFlush(_ sender: NSApplication) {
        terminationFlushInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await viewModel.flushPendingWrites()
            await handleTerminationFlushResult(result, sender: sender)
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
