import Foundation
import UniformTypeIdentifiers
import Darwin

/// Owns the "Derive Look from JPG" flow: the sheet's presentation, the
/// long-running extraction, and the scratch-until-saved lifecycle of the
/// result.
///
/// The derived LUT is deliberately *not* written into the user's library on
/// completion. It lives as a scratch file until they explicitly Save, so an
/// experiment doesn't litter the LUT folder.
///
/// Like `ExportCoordinator`, the save is split into a panel-free
/// `performSave(to:)` core and a `saveDialog` wrapper, and status/error text
/// leaves through closures so presentation stays with `AppViewModel`.
@MainActor
@Observable
final class DeriveCoordinator {

    var isSheetPresented: Bool = false
    private(set) var isDeriving: Bool = false
    private(set) var progress: Double = 0
    private(set) var stage: String = ""
    private(set) var derivedLUT: CubeLUT?
    private(set) var report: RecipeReport?

    @ObservationIgnored var onStatus: ((String) -> Void)?
    @ObservationIgnored var onError: ((String) -> Void)?
    /// Fired when a derive succeeds, so the app can preview the new look.
    @ObservationIgnored var onDerived: ((CubeLUT) -> Void)?
    /// Where the Save panel should open, and what to re-scan afterwards.
    @ObservationIgnored var libraryFolder: (() -> URL?)?
    /// Canonical app-owned fallback for a clean profile. Kept separate from `libraryFolder` so the
    /// existing testable/current-folder seam still reports whether the user selected a Look folder.
    @ObservationIgnored var canonicalLibraryFolder: (() -> URL?)?
    /// Called after a successful save so the sidebar picks the new file up.
    @ObservationIgnored var onSaved: ((URL) -> Void)?

    /// The in-memory cube serialized to a temp .cube, so saving later is a
    /// single `FileManager.copy`. Cleared when a new derive starts.
    @ObservationIgnored private var scratchURL: URL?
    /// Operation-owned directory holding `scratchURL`; nil for test-installed results.
    @ObservationIgnored private var scratchDirectory: URL?

    /// Identity of the current operation. Bumped synchronously by `derive`, `dismiss` and
    /// `shutdown`, so any callback carrying an older value is stale and must not publish.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isShutdown = false
    /// Every worker not yet finished, including ones retired by `dismiss`, so `shutdown` can
    /// await them all.
    @ObservationIgnored private var workers: [Int: Task<Void, Never>] = [:]

    /// The extraction seam. Production runs `RecipeExtractor.derive`; tests inject a controllable
    /// one. Parameters: RAW, JPG, progress, isCancelled.
    typealias Extractor = @Sendable (
        URL, URL, @escaping @Sendable (Double, String) -> Void, @escaping @Sendable () -> Bool
    ) throws -> RecipeExtractor.Result

    @ObservationIgnored private let extractor: Extractor
    @ObservationIgnored private let sheets: any SheetPresenting
    /// Parent of the per-operation `KromoraDerive-*` directories; tests inject a private one.
    @ObservationIgnored private let scratchRoot: URL

    /// - Parameter authoringSpace: the space the production extractor fits in and stamps. Defaults to
    ///   `WorkingSpace.current`; a scripted `extractor` reports its own space in its `Result`.
    init(
        extractor: Extractor? = nil,
        authoringSpace: WorkingSpace = .current,
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        scratchRoot: URL = FileManager.default.temporaryDirectory
    ) {
        self.extractor = extractor ?? { raw, jpg, progress, isCancelled in
            var options = RecipeExtractor.Options()
            options.authoringSpace = authoringSpace
            return try RecipeExtractor.derive(
                rawURL: raw, jpgURL: jpg, options: options,
                progress: progress, isCancelled: isCancelled
            )
        }
        self.scratchRoot = scratchRoot
        self.sheets = sheets
    }

    private enum Outcome: Sendable {
        case finished(lut: CubeLUT, report: RecipeReport, scratch: URL)
        case failed(String)
        case cancelled
    }

    // MARK: - Sheet

    func present() {
        isSheetPresented = true
    }

    /// Close the sheet. A derive still in flight is cancelled — it can run for
    /// tens of seconds and hold several hundred MB, so leaving it running after
    /// the user has walked away is never what they want.
    ///
    /// A *finished* result is kept: the user may re-open the sheet to inspect
    /// the report or save the LUT. The scratch file is cleaned up when a new
    /// derive starts.
    func dismiss() {
        isSheetPresented = false
        guard isDeriving else { return }
        generation += 1
        for worker in workers.values { worker.cancel() }
        isDeriving = false
        progress = 0
        stage = ""
        onStatus?("Derive cancelled")
    }

    /// Cancel extraction and wait for every detached extractor, including ones already retired by
    /// `dismiss()`, before their source pair or scratch directory is removed by a test fixture.
    /// Nothing publishes after this starts.
    func shutdown() async {
        isShutdown = true
        generation += 1
        let outstanding = Array(workers.values)
        for worker in outstanding { worker.cancel() }
        for worker in outstanding { await worker.value }
        workers.removeAll()
        isDeriving = false
        progress = 0
        stage = ""
        isSheetPresented = false
    }

    // MARK: - Deriving

    /// Name given to the derived cube, and to its scratch file. Pure and
    /// `nonisolated` — the extraction task needs it off the main actor.
    nonisolated static func derivedName(forJPG jpgURL: URL, size: Int) -> String {
        jpgURL.deletingPathExtension().lastPathComponent + "_recipe_\(size)_Rec709"
    }

    /// Build the `CubeLUT` for a completed derive.
    ///
    /// **Extracted so a test cannot build one differently.** This construction used to live inline in
    /// `derive`, and two tests stood up their own version of it with `CubeLUT(cube:size:name:)` — no
    /// `sourceURL`, and therefore a `derived://` ID where production produced a temp-file path. Both
    /// passed, and both passed *because* the fixture differed from production in exactly the field
    /// under test. One function used by both sides makes that drift impossible rather than merely
    /// discouraged.
    ///
    /// **No `sourceURL`, and that is the fix.** The scratch `.cube` is still written and still kept —
    /// that is what this coordinator's `scratchURL` is for — but the temp path must not *name* the
    /// LUT. When it did, `LUTID.isDerived` read false, the document held a path no library contains,
    /// and a finished derive resolved to nothing: the user got an ungraded preview. Worse for
    /// anything that persists a document, after the OS temp sweep that path can be reused by an
    /// unrelated file, so a stale reference resolves to the *wrong* LUT rather than to none.
    nonisolated static func makeDerivedLUT(
        cube: [SIMD3<Float>], size: Int, name: String, authoringSpace: WorkingSpace = .current
    ) -> CubeLUT {
        CubeLUT(cube: cube, size: size, name: name, category: "Derived", authoringSpace: authoringSpace)
    }

    /// Derive a LUT from a (RAW, JPG) pair. The result lives in `derivedLUT`
    /// and `report` until the user explicitly saves it.
    func derive(rawURL: URL, jpgURL: URL) {
        guard !isShutdown, !isDeriving else { return }
        generation += 1
        let operation = generation
        isDeriving = true
        progress = 0
        stage = "Starting…"
        derivedLUT = nil
        report = nil
        onStatus?("Deriving recipe…")

        removeScratch()

        let extractor = self.extractor
        let scratchRoot = self.scratchRoot
        workers[operation] = Task.detached {
            let outcome: Outcome
            var scratchDirectory: URL?
            do {
                let result = try extractor(
                    rawURL, jpgURL,
                    { progress, stage in
                        Task { @MainActor in
                            self.applyProgress(progress, stage, operation: operation)
                        }
                    },
                    { Task.isCancelled }
                )
                // The extractor may return normally after cancellation; never serialize for it.
                try Task.checkCancellation()

                let name = Self.derivedName(forJPG: jpgURL, size: result.size)
                // Operation-specific directory: a retired worker can never overwrite or delete
                // the scratch file of the current one.
                let directory = scratchRoot
                    .appendingPathComponent("KromoraDerive-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                scratchDirectory = directory
                let scratch = directory.appendingPathComponent("\(name).cube")
                try CubeLUT.write(
                    cube: result.cube, size: result.size, title: name,
                    authoringSpace: result.authoringSpace, to: scratch
                )
                try Task.checkCancellation()

                let lut = Self.makeDerivedLUT(
                    cube: result.cube, size: result.size, name: name,
                    authoringSpace: result.authoringSpace
                )
                outcome = .finished(lut: lut, report: result.report, scratch: scratch)
            } catch is CancellationError {
                if let scratchDirectory { try? FileManager.default.removeItem(at: scratchDirectory) }
                outcome = .cancelled
            } catch {
                if let scratchDirectory { try? FileManager.default.removeItem(at: scratchDirectory) }
                outcome = .failed("Derive failed: \(error.localizedDescription)")
            }
            await self.complete(outcome, operation: operation)
        }
    }

    private func applyProgress(_ progress: Double, _ stage: String, operation: Int) {
        guard operation == generation, isDeriving else { return }
        self.progress = progress
        self.stage = stage
    }

    /// Final main-actor hop of a worker. Only the current operation may publish; a stale one
    /// discards its unpublished scratch output instead.
    private func complete(_ outcome: Outcome, operation: Int) {
        workers[operation] = nil
        let isCurrent = operation == generation && isDeriving

        switch outcome {
        case .finished(let lut, let report, let scratch):
            guard isCurrent else {
                try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent())
                return
            }
            derivedLUT = lut
            self.report = report
            scratchURL = scratch
            scratchDirectory = scratch.deletingLastPathComponent()
            isDeriving = false
            progress = 1.0
            stage = "Done"
            onStatus?("Recipe derived (\(report.sampleCount) samples)")
            onDerived?(lut)
        case .failed(let message):
            guard isCurrent else { return }
            isDeriving = false
            progress = 0
            stage = ""
            onError?(message)
        case .cancelled:
            // `dismiss()`/`shutdown()` already reset the UI state.
            return
        }
    }

    private func removeScratch() {
        let fm = FileManager.default
        if let scratchDirectory {
            try? fm.removeItem(at: scratchDirectory)
        } else if let scratchURL {
            try? fm.removeItem(at: scratchURL)
        }
        scratchURL = nil
        scratchDirectory = nil
    }

    // MARK: - Saving

    /// Ask where to put the derived LUT, defaulting to the configured LUT
    /// folder so the library picks it up on the next scan.
    @discardableResult
    func saveDialog() -> Task<Void, Never> {
        Task { [weak self] in await self?.runSaveDialog() }
    }

    private func runSaveDialog() async {
        guard let lut = derivedLUT, scratchURL != nil else {
            onStatus?("No derived Look to save")
            return
        }

        let folder = libraryFolder?() ?? canonicalLibraryFolder?()
        guard let destination = await sheets.chooseSaveURL(configure: { panel in
            panel.title = "Save Derived Look"
            if let cubeType = UTType(filenameExtension: "cube") {
                panel.allowedContentTypes = [cubeType]
            }
            panel.nameFieldStringValue = lut.name + ".cube"
            if let folder { panel.directoryURL = folder }
        }) else { return }
        let access = SecurityScopedResourceAccess.systemGranted(for: destination)
        defer { access.release() }

        do {
            try performSave(to: destination)
            onStatus?("Saved: \(destination.lastPathComponent)")
            onSaved?(destination)
        } catch {
            onError?("Save failed: \(error.localizedDescription)")
        }
    }

    /// Copy the scratch cube beside `destination`, then atomically publish it
    /// in place of anything already there. Panel-free, so tests can drive it
    /// directly.
    func performSave(to destination: URL) throws {
        guard let scratch = scratchURL else { throw SaveError.nothingToSave }
        let fm = FileManager.default

        // Keep the staged copy in the destination directory so rename stays
        // on one filesystem and readers see either the old file or the whole
        // new cube. The non-cube extension also keeps library scans from
        // treating an in-progress save as a Look.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: staging) }

        try fm.copyItem(at: scratch, to: staging)

        let result = staging.path.withCString { stagingPath in
            destination.path.withCString { destinationPath in
                Darwin.rename(stagingPath, destinationPath)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: destination.path]
            )
        }
    }

    enum SaveError: LocalizedError {
        case nothingToSave

        var errorDescription: String? {
            switch self {
            case .nothingToSave: return "No derived Look to save"
            }
        }
    }

    // MARK: - Testing seam

    /// Install a derived result without running the extractor, so the save path
    /// can be tested without a RAW fixture.
    func setScratchResult(lut: CubeLUT, report: RecipeReport?, scratchURL: URL) {
        self.derivedLUT = lut
        self.report = report
        self.scratchURL = scratchURL
    }
}
