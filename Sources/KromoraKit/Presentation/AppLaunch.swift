import Foundation
import Observation

/// Opens the library at launch. Whether to take over an expired writer lease is asked through the
/// sheet seam once the first window exists, so the scene shows a placeholder until ``open()``
/// returns the composition root.
@MainActor
@Observable
final class AppLaunch {
    /// Shared with the commands, appearance controller and the view model so they exist before the
    /// library does.
    @ObservationIgnored let settings: KromoraSettings
    private(set) var viewModel: AppViewModel?

    @ObservationIgnored private let packageURL: URL
    @ObservationIgnored private let sheets: any SheetPresenting
    @ObservationIgnored private let makeViewModel:
        (KromoraSettings, URL, (any PortablePackageLeaseRecoveryConfirming)?) -> AppViewModel
    @ObservationIgnored private var openTask: Task<AppViewModel, Never>?

    init(
        settings: KromoraSettings = KromoraSettings(),
        packageURL: URL = KromoraStorage.defaultPortableLibraryPackageURL,
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        makeViewModel: @escaping (
            KromoraSettings, URL, (any PortablePackageLeaseRecoveryConfirming)?
        ) -> AppViewModel = { settings, packageURL, confirmer in
            AppViewModel(
                engine: RenderEngine.shared,
                includeBundledLooks: true,
                portablePackageURL: packageURL,
                leaseRecoveryConfirmer: confirmer,
                settings: settings,
                asynchronousPortableLibraryIndexLoading: true
            )
        }
    ) {
        self.settings = settings
        self.packageURL = packageURL
        self.sheets = sheets
        self.makeViewModel = makeViewModel
    }

    /// Opens the library once; concurrent callers share the same result.
    @discardableResult
    func open() async -> AppViewModel {
        if let openTask { return await openTask.value }
        let task = Task { @MainActor [self] in
            let decision = await PortablePackageLeaseRecoveryPrompt(sheets: sheets)
                .decision(for: packageURL)
            let model = makeViewModel(settings, packageURL, decision)
            viewModel = model
            return model
        }
        openTask = task
        return await task.value
    }
}
