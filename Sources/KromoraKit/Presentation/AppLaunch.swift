import Foundation
import Observation

/// Builds the composition root immediately and opens the library behind the first window. The
/// package opens off the main actor with an explicit "Opening library…" state; whether to take
/// over an expired writer lease is asked through the sheet seam once that open is under way.
@MainActor
@Observable
final class AppLaunch {
    /// Shared with the commands, appearance controller and the view model so they exist before the
    /// library does.
    @ObservationIgnored let settings: KromoraSettings
    private(set) var viewModel: AppViewModel?

    @ObservationIgnored private let packageURL: URL?
    /// Held for the session so a chosen library's security scope outlives every package read.
    @ObservationIgnored private var libraryAccess: SecurityScopedResourceAccess?
    @ObservationIgnored private let sheets: any SheetPresenting
    @ObservationIgnored private let makeViewModel: (KromoraSettings, URL) -> AppViewModel
    @ObservationIgnored private var libraryOpenTask: Task<Void, Never>?

    init(
        settings: KromoraSettings = KromoraSettings(),
        packageURL: URL? = nil,
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        makeViewModel: @escaping (KromoraSettings, URL) -> AppViewModel = { settings, packageURL in
            AppViewModel(
                engine: RenderEngine.shared,
                includeBundledLooks: true,
                portablePackageURL: packageURL,
                settings: settings,
                asynchronousPortableLibraryIndexLoading: true,
                defersLibraryOpen: true
            )
        }
    ) {
        self.settings = settings
        self.packageURL = packageURL
        self.sheets = sheets
        self.makeViewModel = makeViewModel
    }

    /// Returns the composition root, creating it and starting the library open on first call.
    /// Nothing here blocks: the package opens in the background.
    @discardableResult
    func open() -> AppViewModel {
        if let viewModel { return viewModel }
        let packageURL: URL
        var notice: String?
        if let injected = self.packageURL {
            packageURL = injected
        } else {
            let resolution = settings.activeLibrary.resolve()
            packageURL = resolution.url
            libraryAccess = resolution.access
            notice = resolution.notice
        }
        let model = makeViewModel(settings, packageURL)
        viewModel = model
        libraryOpenTask = model.beginOpeningLibrary { [sheets] in
            if let notice {
                _ = await sheets.confirm(
                    message: "Opened the default library",
                    informativeText: notice, style: .warning, buttons: ["OK"])
            }
            return await PortablePackageLeaseRecoveryPrompt(sheets: sheets)
                .decision(for: packageURL)?.allowBreak == true
        }
        return model
    }

    /// Returns once the library open started by ``open()`` has bound or failed.
    func waitForLibraryOpen() async { await libraryOpenTask?.value }
}
