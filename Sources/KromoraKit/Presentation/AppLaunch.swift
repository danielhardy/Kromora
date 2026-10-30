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
        if let injected = self.packageURL ?? Self.libraryPackageOverride() {
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

    /// Whether this bundle was built for verification. `Kromora/Info.plist` substitutes the
    /// `KROMORA_ALLOW_LIBRARY_OVERRIDE` build setting, which is empty unless
    /// `scripts/app-store-build.sh` is run with `KROMORA_VERIFICATION_BUILD=1`.
    static let allowsLibraryOverride: Bool =
        Bundle.main.object(forInfoDictionaryKey: "KromoraAllowLibraryOverride") as? String == "YES"

    /// The package named by `KROMORA_LIBRARY_PACKAGE`, for live verification against a disposable
    /// library (`scripts/disposable-app.sh`). It replaces the stored choice and the default for that
    /// launch only: nothing is written to preferences, so a normal launch is unaffected. Unset,
    /// empty and relative values are ignored. The override is honored only when the bundle opts in
    /// through `KromoraAllowLibraryOverride` (``allowsLibraryOverride``), which the App Store
    /// configuration leaves off, so an inherited environment variable cannot redirect that build.
    static func libraryPackageOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowed: Bool = allowsLibraryOverride
    ) -> URL? {
        guard allowed, let path = environment["KROMORA_LIBRARY_PACKAGE"], path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Returns once the library open started by ``open()`` has bound or failed.
    func waitForLibraryOpen() async { await libraryOpenTask?.value }
}
