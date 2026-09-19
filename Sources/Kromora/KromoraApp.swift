import SwiftUI
import AppKit
import KromoraKit

// The whole app lives in KromoraKit; this target is only the entry point, so the
// code can be unit-tested (`@testable` cannot import an executable target).

/// Forces normal foreground-app activation. When Kromora is launched as a bare
/// Swift Package executable (e.g. `swift run`, or running the SPM target from
/// Xcode), there is no app bundle / Info.plist, so macOS starts it as a
/// background process: no Dock icon, not in ⌘-Tab, and the window never comes
/// to the front. Setting `.regular` + activating makes the window appear
/// reliably. This is a no-op once Kromora runs as a properly bundled `.app`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: AppViewModel
    private let appearanceController: KromoraWindowAppearanceController
    private var terminationFlushInProgress = false

    override init() {
        let viewModel = AppViewModel(includeBundledLooks: true)
        self.viewModel = viewModel
        self.appearanceController = KromoraWindowAppearanceController(settings: viewModel.settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearanceController.start()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
#if KROMORA_DIRECT_DISTRIBUTION
        viewModel.updateCoordinator.checkAutomaticallyIfDue()
#endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: true)
            default:
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: false)
            }
            return
        }

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

@main
struct KromoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            KromoraRootView(viewModel: appDelegate.viewModel)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
#if KROMORA_DIRECT_DISTRIBUTION
            KromoraCommands(
                settings: appDelegate.viewModel.settings,
                updateCoordinator: appDelegate.viewModel.updateCoordinator
            )
#else
            KromoraCommands(settings: appDelegate.viewModel.settings)
#endif
        }

        Settings {
            KromoraSettingsScene(viewModel: appDelegate.viewModel)
        }
    }
}

@MainActor
private struct KromoraRootView: View {
    let viewModel: AppViewModel
#if KROMORA_DIRECT_DISTRIBUTION
    @ObservedObject private var updateCoordinator: UpdateCoordinator
#endif

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
#if KROMORA_DIRECT_DISTRIBUTION
        self._updateCoordinator = ObservedObject(wrappedValue: viewModel.updateCoordinator)
#endif
    }

    var body: some View {
#if KROMORA_DIRECT_DISTRIBUTION
        ContentView(viewModel: viewModel)
            .sheet(isPresented: $updateCoordinator.isSheetPresented) {
                UpdateSheet(coordinator: updateCoordinator)
            }
#else
        ContentView(viewModel: viewModel)
#endif
    }
}

@MainActor
private struct KromoraSettingsScene: View {
    let viewModel: AppViewModel
    @State private var editDatabaseURL: URL?

    var body: some View {
        KromoraSettingsView(
            settings: viewModel.settings,
            editDatabaseURL: editDatabaseURL
        )
        .task {
            editDatabaseURL = await viewModel.editDatabaseURL
        }
    }
}
