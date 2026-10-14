import AppKit
import Observation

/// Restarts the app so a new library choice takes effect.
@MainActor
protocol AppRelaunching {
    /// Starts the replacement process and, once it has launched, quits this one. Throws, leaving
    /// this process running, when the replacement cannot be launched.
    func relaunch() async throws
}

struct AppKitRelauncher: AppRelaunching {
    func relaunch() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
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
    /// Neutral outcome shown when no relaunch was needed; empty otherwise.
    private(set) var statusMessage = ""
    /// The chosen package, or `nil` while the default is in use.
    private(set) var chosenURL: URL?

    /// The package this session has open. The stored choice only applies on the next launch, so
    /// later choices in the same session still compare against this.
    @ObservationIgnored private let launchURL: URL
    @ObservationIgnored private let selection: ActiveLibrarySelection
    @ObservationIgnored private let fileDialog: any FileDialogProviding
    @ObservationIgnored private let sheets: any SheetPresenting
    @ObservationIgnored private let relauncher: any AppRelaunching
    /// Flushes pending edits and culling state and releases the open package lease. Returns `false`
    /// when the user cancels or declines after a failed flush, in which case nothing is relaunched.
    @ObservationIgnored private let releaseLibrary: @MainActor () async -> Bool

    init(
        selection: ActiveLibrarySelection,
        fileDialog: any FileDialogProviding,
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        relauncher: any AppRelaunching = AppKitRelauncher(),
        releaseLibrary: @escaping @MainActor () async -> Bool = { true }
    ) {
        self.selection = selection
        self.fileDialog = fileDialog
        self.sheets = sheets
        self.relauncher = relauncher
        self.releaseLibrary = releaseLibrary
        chosenURL = selection.chosenURL
        launchURL = (selection.chosenURL ?? selection.defaultURL).resolvingSymlinksInPath()
    }

    var displayPath: String {
        (chosenURL ?? selection.defaultURL).path(percentEncoded: false)
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var isUsingDefault: Bool { chosenURL == nil }

    func choose() async {
        errorMessage = ""
        statusMessage = ""
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
        await offerRelaunch(alreadyOpen: launchURL == (chosenURL ?? selection.defaultURL).resolvingSymlinksInPath())
    }

    func useDefault() async {
        errorMessage = ""
        statusMessage = ""
        selection.useDefault()
        chosenURL = nil
        await offerRelaunch(alreadyOpen: launchURL == selection.defaultURL.resolvingSymlinksInPath())
    }

    private func offerRelaunch(alreadyOpen: Bool) async {
        guard !alreadyOpen else {
            statusMessage = "This library is already open. No relaunch is needed."
            return
        }
        let relaunch = await sheets.confirm(
            message: "Kromora needs to relaunch to use this library",
            informativeText: "Your photos and edits in the current library are not changed.",
            style: .informational,
            buttons: ["Relaunch", "Later"]
        )
        guard relaunch else { return }
        // The replacement must not start while this process still holds the writer lease.
        guard await releaseLibrary() else {
            statusMessage = "Relaunch canceled. The library choice applies the next time Kromora starts."
            return
        }
        do {
            try await relauncher.relaunch()
        } catch {
            errorMessage = "Kromora couldn’t relaunch: \(error.localizedDescription) "
                + "Your edits are saved and the library is closed. Quit and reopen Kromora to use the new library."
        }
    }
}
