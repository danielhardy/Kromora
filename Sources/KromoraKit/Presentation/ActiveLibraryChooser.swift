import AppKit
import Observation

/// Restarts the app so a new library choice takes effect.
@MainActor
protocol AppRelaunching {
    func relaunch()
}

struct AppKitRelauncher: AppRelaunching {
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        NSApp.terminate(nil)
    }
}

/// The Settings > Library flow: pick a package, validate it, store the bookmark, offer a relaunch.
/// There is no runtime swap; the choice applies the next time the app launches.
@MainActor
@Observable
final class ActiveLibraryChooser {
    /// Shown under the button; empty when there is nothing to report.
    private(set) var errorMessage = ""
    /// The chosen package, or `nil` while the default is in use.
    private(set) var chosenURL: URL?

    @ObservationIgnored private let selection: ActiveLibrarySelection
    @ObservationIgnored private let fileDialog: any FileDialogProviding
    @ObservationIgnored private let sheets: any SheetPresenting
    @ObservationIgnored private let relauncher: any AppRelaunching

    init(
        selection: ActiveLibrarySelection,
        fileDialog: any FileDialogProviding,
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        relauncher: any AppRelaunching = AppKitRelauncher()
    ) {
        self.selection = selection
        self.fileDialog = fileDialog
        self.sheets = sheets
        self.relauncher = relauncher
        chosenURL = selection.chosenURL
    }

    var displayPath: String {
        (chosenURL ?? selection.defaultURL).path(percentEncoded: false)
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var isUsingDefault: Bool { chosenURL == nil }

    func choose() async {
        errorMessage = ""
        guard let url = await fileDialog.chooseFolder(
            title: "Choose Library",
            prompt: "Use Library",
            startingAt: chosenURL?.deletingLastPathComponent() ?? selection.defaultURL.deletingLastPathComponent(),
            canCreateDirectories: false
        ) else { return }
        do {
            try selection.choose(url, access: .systemGranted(for: url))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        chosenURL = selection.chosenURL
        await offerRelaunch()
    }

    func useDefault() async {
        errorMessage = ""
        selection.useDefault()
        chosenURL = nil
        await offerRelaunch()
    }

    private func offerRelaunch() async {
        let relaunch = await sheets.confirm(
            message: "Kromora needs to relaunch to use this library",
            informativeText: "Your photos and edits in the current library are not changed.",
            style: .informational,
            buttons: ["Relaunch", "Later"]
        )
        if relaunch { relauncher.relaunch() }
    }
}
