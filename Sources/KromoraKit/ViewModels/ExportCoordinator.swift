import Foundation
import CoreImage
import AppKit
import Darwin

/// Owns everything about writing images to disk: the single export, the batch
/// run, and the naming rules both share.
///
/// Each operation is split in two — a `perform…` core that takes an explicit
/// destination, and a thin `…Dialog` wrapper that runs the panel and calls it.
/// The panels can't run headless, so that seam is what makes export testable
/// at all.
///
/// Status and error text goes out through `onStatus`/`onError` rather than
/// being written here: the status bar and the alert belong to `AppViewModel`,
/// and this type has no business deciding how a failure is presented.
///
/// **Step 6 cut both paths over to `RenderEngine`.** Neither one takes a `CIImage` any more: they
/// take the `ImageSource` and the `EditDocument` and ask the engine to encode at `.full`. That is
/// what makes an export honour develop and adjustments — before, the single path graded a
/// full-resolution neutral decode with only the LUT, and the batch path independently reproduced the
/// same omission with its own `loadImage` + `apply`. Two places to forget the same thing is exactly
/// why the fix is "hand the document to the one funnel" rather than "remember to grade twice".
///
/// It also removes the `[processor]` capture into `Task.detached` that §2 of the spec flags: the
/// non-`Sendable` singleton is gone from both loops, and the work now happens inside the actor that
/// owns the context.
///
/// Migrated to Observation (KRMA-521): batch progress publishes through this object's own
/// boundary. The status bar observes the coordinator directly through `@Bindable` so export
/// progress never passes through AppViewModel's former root notification fan-in.
@MainActor
@Observable
final class ExportCoordinator {

    /// Every accepted single export, batch, Share render, and original bundle, by id. A job's
    /// completion removes only its own entry, so `isExporting` is "a job exists", never a flag an
    /// older job can clear under a newer one.
    private(set) var jobs: [ExportJobID: ExportJob] = [:] {
        didSet {
            if oldValue.isEmpty != jobs.isEmpty { onActivityChanged?(!jobs.isEmpty) }
        }
    }
    /// The most recent job to reach a terminal state.
    private(set) var lastFinishedJob: ExportJobRecord?
    var isExporting: Bool { !jobs.isEmpty }
    /// Progress (0...1) during a multi-image "Export All" run.
    private(set) var batchProgress: Double = 0
    /// Number of items that have reached a terminal state in the current batch.
    private(set) var batchCompleted: Int = 0
    /// Total number of items in the current batch. Zero means that no batch is active.
    private(set) var batchTotal: Int = 0
    /// The source currently in the expensive decode/render/commit section.
    private(set) var batchCurrentItem: String?
    /// The format used by the most recently started export in this session.
    /// Both export dialogs use this to seed their accessory view.
    private(set) var lastUsedFormat: ExportFormat
    /// Supplied by the app's settings owner at panel presentation time. It is a default only: the
    /// chosen export destination is never written back into the setting automatically.
    var defaultFolderURL: (() -> URL?)?

    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onExportCompleted: ((URL) -> Void)?
    var onActivityChanged: ((Bool) -> Void)?

    /// The renderer. `any RenderEngining` rather than the concrete actor for the same reason
    /// `AppViewModel` holds one: a test can then assert *what was asked to be encoded* — which
    /// document, at which scale, in which format — without a GPU or a file on disk.
    /// Production exports use a second RenderEngine actor/context/queue. A full-resolution encode
    /// is non-preemptible once Core Image enters it, so a batch cannot monopolize the display actor.
    /// The batch loop remains serial, retaining only one full-size result at a time.
    private let exportEngine: any RenderEngining
    /// Optional post-commit Photos delivery. Keeping this injectable leaves core export tests
    /// independent of PhotoKit authorization and the user's library.
    private let photosDelivery: (any PhotosDelivering)?
    private let sheets: any SheetPresenting
    /// True while a save/open sheet is up, so a repeated command cannot stack a second sheet.
    private var isPresentingSheet = false

    /// The edit store is used for batch items that have not been opened in the current session.
    /// `lutResolver` is deliberately a value-returning main-actor seam: the store owns edit values,
    /// while the app's Look library owns the non-Codable LUT table.
    var lutResolver: ((LUTID?) -> CubeLUT?)?
    private let editStore: EditDocumentStore?

    init(
        engine: any RenderEngining = RenderEngine.shared,
        exportEngine: (any RenderEngining)? = nil,
        maskResolver: (any LocalMaskResolving)? = nil,
        editStore: EditDocumentStore? = nil,
        lutResolver: ((LUTID?) -> CubeLUT?)? = nil,
        photosDelivery: (any PhotosDelivering)? = PhotoKitDelivery(),
        sheets: any SheetPresenting = AppKitSheetPresenter()
    ) {
        self.sheets = sheets
        // Test renderers are deliberately shared so request assertions remain simple. The real
        // renderer gets isolated mutable Core Image state for export work.
        self.exportEngine = exportEngine ?? (engine is RenderEngine
            ? RenderEngine(maskResolver: maskResolver ?? DefaultLocalMaskResolver()) : engine)
        self.photosDelivery = photosDelivery
        self.editStore = editStore
        self.lutResolver = lutResolver
        self.lastUsedFormat = Self.defaultFormat
    }

    private static let defaultFormat: ExportFormat = .jpeg

    // MARK: - Jobs

    func activeJobCount(of kind: ExportJobKind) -> Int {
        jobs.values.reduce(0) { $0 + ($1.kind == kind ? 1 : 0) }
    }

    /// Accepts a job unless one is already running. Another command is refused with a visible
    /// status and the running job is left alone; Share renders of one picker may overlap each
    /// other, but not a running export.
    func admitJob(_ kind: ExportJobKind, itemCount: Int = 1, announce: Bool = true) -> ExportJobID? {
        let conflicts = jobs.values.contains { !(kind == .share && $0.kind == .share) }
        guard !conflicts else {
            if announce { onStatus?(ExportJobBusyError().localizedDescription + " Wait for it to finish.") }
            return nil
        }
        let id = ExportJobID()
        jobs[id] = ExportJob(id: id, kind: kind, itemCount: itemCount)
        return id
    }

    /// Hands the job's task to the registry so cancellation and shutdown reach it.
    func attach<Success: Sendable, Failure: Error>(
        _ task: Task<Success, Failure>, to id: ExportJobID
    ) {
        jobs[id]?.cancel = { task.cancel() }
        jobs[id]?.settled = { _ = await task.result }
    }

    /// Removes exactly this job. Calling it again, or for a job shutdown already cleared, is a no-op.
    func finishJob(_ id: ExportJobID, outcome: ExportJobOutcome = .completed) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        lastFinishedJob = ExportJobRecord(id: id, kind: job.kind, outcome: outcome)
    }

    /// A job missing from the registry (cleared by shutdown) counts as cancelled.
    private func isCancellationRequested(_ id: ExportJobID) -> Bool {
        jobs[id]?.cancellationRequested ?? true
    }

    private func requestCancellation(of id: ExportJobID) {
        jobs[id]?.cancellationRequested = true
        jobs[id]?.cancel?()
    }

    /// Runs `operation` as a registered job and returns its result. Cancelling the caller cancels
    /// the job, and shutdown cancels and awaits it. Throws `ExportJobBusyError` when refused.
    func runJob<Result: Sendable>(
        _ kind: ExportJobKind,
        itemCount: Int = 1,
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        guard let id = admitJob(kind, itemCount: itemCount, announce: false) else {
            onStatus?(ExportJobBusyError().localizedDescription + " Wait for it to finish.")
            throw ExportJobBusyError()
        }
        let work = Task { @MainActor [weak self] in
            do {
                let value = try await operation()
                self?.finishJob(id)
                return value
            } catch {
                self?.finishJob(id, outcome: error is CancellationError ? .cancelled : .failed)
                throw error
            }
        }
        attach(work, to: id)
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    // MARK: - Types

    /// One image to export, reduced to the `Sendable` bits. Deliberately not
    /// `ImageCollection.Item`: that carries an `NSImage` thumbnail we don't
    /// want crossing an actor boundary.
    struct BatchItem: Sendable {
        let url: URL?
        let data: Data?
        let name: String
        /// Stable identity used to find the item's persisted edit record. It is optional so the
        /// original panel-free API remains source-compatible for callers that only have a URL/data
        /// pair.
        /// A URL with no supplied identity stays `nil` here so construction does no file I/O; use
        /// `resolvedAssetID()` where the identity is needed.
        let assetID: PhotoAssetID?
        /// Opaque identity carried by the library source when available. The legacy `assetID` is
        /// retained for source compatibility, but it is never used as the persistence key.
        let portableIdentity: PortablePhotoIdentity?
        /// A source bookmark can outlive the folder scope that was active when the item was scanned.
        /// It is kept as data, never as an open security scope.
        let bookmarkData: Data?
        /// A live session snapshot wins over disk when the user edited this photo moments ago.
        /// `nil` means the coordinator should resolve the durable record.
        let document: EditDocument?
        /// An optional pre-resolved table for `document.lut`. When absent, the coordinator resolves
        /// the document's Look ID; a missing per-asset Look causes that item to fail.
        let lut: CubeLUT?

        init(
            url: URL?, data: Data?, name: String,
            assetID: PhotoAssetID? = nil,
            portableIdentity: PortablePhotoIdentity? = nil,
            bookmarkData: Data? = nil,
            document: EditDocument? = nil,
            lut: CubeLUT? = nil
        ) {
            self.url = url
            self.data = data
            self.name = name
            self.assetID = assetID ?? (url == nil ? data.map(PhotoAssetID.data) : nil)
            self.portableIdentity = portableIdentity
            self.bookmarkData = bookmarkData
            self.document = document
            self.lut = lut
        }

        /// The supplied identity, or the file-backed identity resolved off the calling actor.
        func resolvedAssetID() async -> PhotoAssetID? {
            if let assetID { return assetID }
            guard let url else { return nil }
            return await PhotoAssetID.resolveFile(url)
        }
    }

    struct BatchOutcome: Equatable {
        let exported: Int
        let failed: Int
        let total: Int
        let cancelled: Bool
        let photosFailed: Int

        init(
            exported: Int, failed: Int, total: Int, cancelled: Bool = false,
            photosFailed: Int = 0
        ) {
            self.exported = exported
            self.failed = failed
            self.total = total
            self.cancelled = cancelled
            self.photosFailed = photosFailed
        }

        var isCancelled: Bool { cancelled }
    }

    // MARK: - Naming

    // Pure and `nonisolated`: the batch loop needs them off the main actor.

    /// `‹photo›_‹LUT name›` — the shared stem for both export paths. Spaces in
    /// the LUT name become underscores so the result is shell-friendly.
    nonisolated static func exportBaseName(source: String, lut: CubeLUT?) -> String {
        let suffix = lut.map { "_" + $0.name.replacingOccurrences(of: " ", with: "_") } ?? ""
        return source + suffix
    }

    nonisolated static func defaultFileName(
        source: String,
        lut: CubeLUT?,
        format: ExportFormat
    ) -> String {
        exportBaseName(source: source, lut: lut) + "." + format.fileExtension
    }

    // MARK: - Single export

    /// Ask for a destination, then export. `suggestedBaseName` is the stem; the
    /// extension comes from the current format.
    func exportDialog(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        document: EditDocument,
        lut: CubeLUT?,
        suggestedBaseName: String
    ) {
        guard !isPresentingSheet else { return }
        guard !isExporting else {
            onStatus?(ExportJobBusyError().localizedDescription + " Wait for it to finish.")
            return
        }
        isPresentingSheet = true
        let formatPicker = ExportFormatAccessoryView(selectedFormat: lastUsedFormat)
        let directoryURL = defaultFolderURL?()
        Task { [weak self] in
            guard let self else { return }
            defer { self.isPresentingSheet = false }
            let chosen = await self.sheets.chooseSaveURL { panel in
                panel.title = "Export"
                panel.nameFieldStringValue =
                    suggestedBaseName + "." + formatPicker.selectedFormat.fileExtension
                panel.directoryURL = directoryURL
                panel.allowedContentTypes = [formatPicker.selectedFormat.utType]
                formatPicker.onSelectionChanged = { [weak panel] format in
                    panel?.nameFieldStringValue = suggestedBaseName + "." + format.fileExtension
                    panel?.allowedContentTypes = [format.utType]
                }
                panel.accessoryView = formatPicker
            }
            guard let url = chosen else { return }
            self.performExportFromDialog(
                source: source, assetID: assetID, document: document, lut: lut,
                formatPicker: formatPicker, url: url
            )
        }
    }

    private func performExportFromDialog(
        source: ImageSource, assetID: PhotoAssetID?, document: EditDocument, lut: CubeLUT?,
        formatPicker: ExportFormatAccessoryView, url: URL
    ) {
        performExport(
            source: source,
            assetID: assetID,
            document: document,
            lut: lut,
            options: ExportOptions(
                format: formatPicker.selectedFormat,
                destination: .file(url),
                metadata: formatPicker.metadataPolicy,
                location: formatPicker.locationPolicy,
                photos: formatPicker.photosOptions,
                outputSharpening: formatPicker.outputSharpening
            ),
            to: url,
            access: .systemGranted(for: url)
        )
    }

    /// Encode `document` over `source` at full resolution and write it to `url`.
    /// Panel-free, so tests can drive it directly.
    ///
    /// The encode happens inside the engine; the *write* deliberately does not. File I/O is not the
    /// GPU's business, and keeping it out here means the actor never touches the sandbox or a
    /// half-written file (`RenderEngining.encode` returns `Data` for exactly this reason).
    func performExport(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        document: EditDocument,
        lut: CubeLUT?,
        format: ExportFormat,
        to url: URL
    ) {
        performExport(
            source: source, assetID: assetID, document: document, lut: lut,
            options: ExportOptions(format: format, destination: .file(url)), to: url
        )
    }

    /// Validate and start one export from a complete, panel-independent policy.
    func performExport(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions,
        to url: URL,
        access: SecurityScopedResourceAccess? = nil
    ) {
        do {
            try options.validate()
        } catch {
            access?.release()
            onError?("Export failed: \(error.localizedDescription)")
            return
        }
        guard let jobID = admitJob(.single) else {
            access?.release()
            return
        }
        lastUsedFormat = options.format
        onStatus?("Exporting...")

        let task = Task { [weak self, exportEngine, options, access] in
            var outcome = ExportJobOutcome.completed
            defer { self?.finishJob(jobID, outcome: outcome) }
            let destinationAccess = access ?? SecurityScopedResourceAccess.startAccessing(url)
            defer { destinationAccess?.release() }
            var interval = KromoraObservability.begin(.export, source: source, quality: .export)
            defer { interval.end() }
            do {
                try Task.checkCancellation()
                let data = try await exportEngine.render(RenderRequest(
                    source: source, assetID: assetID, document: document, lut: lut,
                    quality: .export,
                    output: .encoded(
                        format: options.format, quality: CGFloat(options.quality)
                    ),
                    space: options.colorSpace,
                    exportOptions: options
                )).data
                try Task.checkCancellation()
                try await Self.write(data, to: url, scopedFileURL: destinationAccess != nil)
                self?.onExportCompleted?(url)
                if let photos = options.photos, let delivery = self?.photosDelivery {
                    do {
                        let result = try await delivery.deliver(
                            data: data,
                            filename: url.lastPathComponent,
                            format: options.format,
                            options: photos
                        )
                        self?.reportPhotosSuccess(result, filename: url.lastPathComponent)
                    } catch {
                        self?.onStatus?("Exported: \(url.lastPathComponent)")
                        self?.onError?("Photos delivery failed; the file is safe at \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                } else {
                    self?.onStatus?("Exported: \(url.lastPathComponent)")
                }
            } catch {
                outcome = error is CancellationError ? .cancelled : .failed
                self?.onError?("Export failed: \(error.localizedDescription)")
            }
        }
        attach(task, to: jobID)
    }

    /// Render and encode one image without writing it or touching export status. Share uses this to
    /// render lazily, when the user picks a service.
    func renderEncodedData(
        source: ImageSource,
        assetID: PhotoAssetID?,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) async throws -> Data {
        try options.validate()
        return try await exportEngine.render(RenderRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            quality: .export,
            output: .encoded(format: options.format, quality: CGFloat(options.quality)),
            space: options.colorSpace,
            exportOptions: options
        )).data
    }

    /// Renders one batch item to encoded data without writing it, for lazy Share. The item's own
    /// edit snapshot wins; `document` and `lut` apply only when the item carries none.
    func renderEncodedData(
        for item: BatchItem, document: EditDocument, lut: CubeLUT?, options: ExportOptions
    ) async throws -> Data {
        try options.validate()
        guard let sourceAccess = await Self.sourceAccess(for: item) else {
            throw ImageError.exportFailed
        }
        let itemAssetID = await item.resolvedAssetID()
        let resolution = try await resolvedDocument(for: item, assetID: itemAssetID, fallback: document)
        let itemLUT = try resolvedLUT(for: item, resolution: resolution, fallback: lut)
        let hasSourceScope = sourceAccess.url?.startAccessingSecurityScopedResource() ?? false
        defer {
            if hasSourceScope { sourceAccess.url?.stopAccessingSecurityScopedResource() }
        }
        return try await exportEngine.render(RenderRequest(
            source: sourceAccess.source, assetID: itemAssetID, document: resolution.document,
            lut: itemLUT, quality: .export,
            output: .encoded(format: options.format, quality: CGFloat(options.quality)),
            space: options.colorSpace,
            exportOptions: options
        )).data
    }

    /// Start a single export using the file destination embedded in options.
    func performExport(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) {
        guard case .file(let url)? = options.destination else {
            onError?("Export failed: a file destination is required.")
            return
        }
        performExport(source: source, document: document, lut: lut, options: options, to: url)
    }

    // MARK: - Batch export

    /// Ask for a folder, then render `document` over every item and write the
    /// results into it.
    func batchExportDialog(items: [BatchItem], document: EditDocument, lut: CubeLUT?) {
        guard !items.isEmpty else {
            onStatus?("Import a set of images first (Export All works on the filmstrip)")
            return
        }

        guard !isPresentingSheet else { return }
        guard !isExporting else {
            onStatus?(ExportJobBusyError().localizedDescription + " Wait for it to finish.")
            return
        }
        isPresentingSheet = true
        let formatPicker = ExportFormatAccessoryView(selectedFormat: lastUsedFormat)
        let directoryURL = defaultFolderURL?()
        Task { [weak self] in
            guard let self else { return }
            defer { self.isPresentingSheet = false }
            let chosen = await self.sheets.chooseOpenURLs { panel in
                panel.title = "Choose Export Folder"
                panel.prompt = "Export Here"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                panel.directoryURL = directoryURL
                panel.accessoryView = formatPicker
            }
            guard let folder = chosen?.first else { return }
            self.startBatchExport(
                items: items, document: document, lut: lut, folder: folder,
                formatPicker: formatPicker
            )
        }
    }

    private func startBatchExport(
        items: [BatchItem], document: EditDocument, lut: CubeLUT?, folder: URL,
        formatPicker: ExportFormatAccessoryView
    ) {
        let format = formatPicker.selectedFormat
        let access = SecurityScopedResourceAccess.systemGranted(for: folder)
        // A job may have started while the sheet was up.
        guard let jobID = admitJob(.batch, itemCount: items.count) else {
            access.release()
            return
        }
        // Record the choice as soon as the dialog completes, before the async batch starts.
        lastUsedFormat = format
        let options = ExportOptions(
            format: format,
            destination: .folder(folder),
            metadata: formatPicker.metadataPolicy,
            location: formatPicker.locationPolicy,
            photos: formatPicker.photosOptions
        )
        let task = Task { [weak self, access] in
            guard let self else {
                access.release()
                return BatchOutcome(exported: 0, failed: items.count, total: items.count)
            }
            return await self.performBatchExport(
                items, document: document, lut: lut, options: options, to: folder,
                access: access, jobID: jobID
            )
        }
        attach(task, to: jobID)
    }

    /// Stop starting new items. If the renderer is at a cooperative cancellation point it also
    /// stops the current render; otherwise the current item finishes without being committed and
    /// the loop exits before another source is touched.
    func cancelBatchExport() {
        guard batchTotal > 0,
              let id = jobs.values.first(where: { $0.kind == .batch })?.id else { return }
        requestCancellation(of: id)
        onStatus?("Cancelling export…")
    }

    /// Cancel single and batch export work and wait for any renderer or disk operation to finish.
    /// This is intentionally separate from the user-facing batch cancellation status flow.
    func shutdown() async {
        let active = Array(jobs.keys)
        for id in active { requestCancellation(of: id) }
        for id in active { await jobs[id]?.settled?() }
        for id in active { finishJob(id, outcome: .cancelled) }
        batchProgress = 0
        batchCompleted = 0
        batchTotal = 0
        batchCurrentItem = nil
    }

    /// The batch core. Renders each item through the engine with progress; an
    /// image that fails to decode or encode is counted and skipped, never
    /// aborting the run. Returns the tally so callers (and tests) can assert on it.
    ///
    /// The fallback `document`/`lut` arguments are retained for callers that intentionally want to
    /// apply one look to a set. A `BatchItem` with a live snapshot or a durable record always wins,
    /// which is what current/selected export uses.
    ///
    /// **Not memoized, deliberately.** The engine's developed-source memo only covers preview
    /// scales; a batch renders N *different* images at `.full`, so a memo would hold one
    /// full-resolution intermediate per item and never see a hit. See §6.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        format: ExportFormat,
        to folder: URL
    ) async -> BatchOutcome {
        await performBatchExport(
            items, document: document, lut: lut,
            options: ExportOptions(format: format, destination: .folder(folder)), to: folder
        )
    }

    /// Start a batch export using the folder destination embedded in options.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) async -> BatchOutcome {
        guard case .folder(let folder)? = options.destination else {
            onError?("Export failed: a folder destination is required.")
            return BatchOutcome(exported: 0, failed: items.count, total: items.count)
        }
        return await performBatchExport(
            items, document: document, lut: lut, options: options, to: folder
        )
    }

    /// Batch export using a complete, panel-independent policy.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions,
        to folder: URL,
        access: SecurityScopedResourceAccess? = nil,
        jobID admittedJob: ExportJobID? = nil
    ) async -> BatchOutcome {
        defer { access?.release() }
        do {
            try options.validate()
        } catch {
            if let admittedJob { finishJob(admittedJob, outcome: .failed) }
            onError?("Export failed: \(error.localizedDescription)")
            return BatchOutcome(exported: 0, failed: items.count, total: items.count)
        }

        // The panel path admits the job before its task starts; a direct caller is admitted here.
        guard let jobID = admittedJob ?? admitJob(.batch, itemCount: items.count) else {
            return BatchOutcome(exported: 0, failed: items.count, total: items.count)
        }
        lastUsedFormat = options.format
        batchProgress = 0
        batchCompleted = 0
        batchTotal = items.count
        batchCurrentItem = nil
        // Copy the value-only work list before any async suspension. The caller may continue
        // changing its live library selection while the panel-free operation is running, but that
        // must never add, remove, or reorder work in this batch.
        let operationItems = Array(items)
        let total = operationItems.count
        onStatus?("Exporting 0 of \(total)…")

        var exported = 0
        var failed = 0
        var photosFailed = 0
        var cancelled = false

        // Reserve destinations in selection order before each render starts. The batch remains
        // serial to keep at most one full-resolution raster and encoded Data alive, while the
        // reservation set makes duplicate names deterministic and collision-free.
        var reservedPaths = Set<String>()

        let hasDestinationScope = access == nil && folder.startAccessingSecurityScopedResource()
        defer {
            if hasDestinationScope { folder.stopAccessingSecurityScopedResource() }
        }

        for item in operationItems {
            guard !Task.isCancelled, !isCancellationRequested(jobID) else {
                cancelled = true
                break
            }
            batchCurrentItem = item.name
            onStatus?("Exporting \(batchCompleted) of \(total)… \(item.name)")
            if let sourceAccess = await Self.sourceAccess(for: item) {
                let source = sourceAccess.source
                let itemAssetID = await item.resolvedAssetID()
                let documentResolution: DocumentResolution
                let itemLUT: CubeLUT?
                do {
                    documentResolution = try await resolvedDocument(
                        for: item, assetID: itemAssetID, fallback: document
                    )
                    itemLUT = try resolvedLUT(
                        for: item, resolution: documentResolution, fallback: lut
                    )
                } catch {
                    failed += 1
                    onStatus?("Skipped \(item.name): \(error.localizedDescription)")
                    let done = exported + failed
                    batchCompleted = done
                    batchProgress = Double(done) / Double(total)
                    continue
                }
                guard !Task.isCancelled, !isCancellationRequested(jobID) else {
                    cancelled = true
                    break
                }
                let itemDocument = documentResolution.document
                let lookName = options.filenamePolicy == .sourceNameWithLook ? itemLUT?.name : nil
                let base = options.filenamePolicy.baseName(source: item.name, look: lookName)
                var dest = uniqueExportURL(
                    in: folder, base: base, ext: options.format.fileExtension
                )
                var counter = 2
                while reservedPaths.contains(dest.standardizedFileURL.path) {
                    dest = folder.appendingPathComponent(
                        "\(base) \(counter).\(options.format.fileExtension)"
                    )
                    counter += 1
                }
                reservedPaths.insert(dest.standardizedFileURL.path)
                do {
                    try Task.checkCancellation()
                    guard !isCancellationRequested(jobID) else { throw CancellationError() }
                    let hasSourceScope = sourceAccess.url?.startAccessingSecurityScopedResource() ?? false
                    defer {
                        if hasSourceScope { sourceAccess.url?.stopAccessingSecurityScopedResource() }
                    }
                    var interval = KromoraObservability.begin(.export, source: source, quality: .export)
                    defer { interval.end() }
                    let data = try await exportEngine.render(RenderRequest(
                        source: source, assetID: itemAssetID, document: itemDocument, lut: itemLUT,
                        quality: .export,
                        output: .encoded(
                            format: options.format, quality: CGFloat(options.quality)
                        ),
                        space: options.colorSpace,
                        exportOptions: options
                    )).data
                    try Task.checkCancellation()
                    guard !isCancellationRequested(jobID) else { throw CancellationError() }
                    try await Self.write(data, to: dest)
                    try Task.checkCancellation()
                    guard !isCancellationRequested(jobID) else { throw CancellationError() }
                    exported += 1
                    if let photos = options.photos, let delivery = photosDelivery {
                        do {
                            let result = try await delivery.deliver(
                                data: data,
                                filename: dest.lastPathComponent,
                                format: options.format,
                                options: photos
                            )
                            if let warning = result.warning {
                                photosFailed += 1
                                onStatus?("Exported \(item.name); Photos warning: \(warning)")
                            }
                        } catch {
                            photosFailed += 1
                            onStatus?("Exported \(item.name); Photos delivery failed: \(error.localizedDescription)")
                        }
                    }
                } catch is CancellationError {
                    cancelled = true
                    break
                } catch {
                    failed += 1
                    onStatus?("Skipped \(item.name): \(error.localizedDescription)")
                }
            } else {
                failed += 1
                onStatus?("Skipped \(item.name): source unavailable")
            }

            let done = exported + failed
            batchCompleted = done
            batchProgress = Double(done) / Double(total)
            onStatus?("Exporting \(done) of \(total)…")
        }

        cancelled = cancelled || Task.isCancelled || isCancellationRequested(jobID)
        let outcome = BatchOutcome(
            exported: exported,
            failed: failed,
            total: total,
            cancelled: cancelled,
            photosFailed: photosFailed
        )
        batchProgress = 0
        batchCompleted = 0
        batchTotal = 0
        batchCurrentItem = nil
        finishJob(jobID, outcome: cancelled ? .cancelled : .completed)
        onStatus?(Self.summary(for: outcome, folder: folder))
        return outcome
    }

    /// Write off the main actor.
    ///
    /// Both loops are `@MainActor` now that the encode happens inside `RenderEngine` rather than in a
    /// detached task — but a full-resolution 16-bit TIFF is hundreds of megabytes, and handing that
    /// to the main thread would stutter the window for exactly as long as the disk takes. `Data` and
    /// `URL` are `Sendable`, so getting it off costs nothing.
    private static func write(
        _ data: Data,
        to url: URL,
        scopedFileURL: Bool = false
    ) async throws {
        if scopedFileURL {
            // NSSavePanel grants access to the selected file. Staging a sibling and moving it
            // over the selection needs directory access that the file grant doesn't provide.
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                try Self.writeSelectedFile(data, to: url)
            }.value
            try Task.checkCancellation()
            return
        }

        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).partial"
        )
        var committed = false
        defer {
            if !committed { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: temporaryURL, options: .atomic)
        }.value
        try Task.checkCancellation()
        // moveItem does not replace an existing destination. That last boundary protects an
        // already-exported file even if another process creates the same name after reservation.
        try FileManager.default.moveItem(at: temporaryURL, to: url)
        committed = true
    }

    /// Create a panel-selected file without touching its parent directory. The save-panel grant
    /// authorizes this exact URL; the exclusive create also preserves the export path's
    /// no-overwrite behavior while ensuring a failed write removes only the file we created.
    nonisolated private static func writeSelectedFile(_ data: Data, to url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o666))
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// A resolved source plus the URL that may need a temporary security scope. The source itself
    /// always points at the original URL/data; it never points at a thumbnail or preview bitmap.
    private struct SourceAccess: Sendable {
        let source: ImageSource
        let url: URL?
    }

    /// How to reproduce a batch item, as an `ImageSource`.
    ///
    /// `nativeExtent` is `.zero` because a batch export never measures one: the extent exists so a
    /// *preview* can compute a downscale factor without decoding twice, and `RenderScale.full`
    /// returns 1.0 regardless. The pipeline reads the decoder's own size anyway, never this field
    /// (`RenderPipeline.developedSource`), so decoding every file up front just to fill it in would
    /// be pure cost.
    private static func sourceAccess(for item: BatchItem) async -> SourceAccess? {
        if let url = item.url {
            let resolved = resolveScopedURL(url: url, bookmarkData: item.bookmarkData)
            return SourceAccess(
                source: await ImageSource.resolve(url: resolved, nativeExtent: .zero),
                url: resolved
            )
        }
        if let data = item.data {
            return SourceAccess(source: ImageSource(data: data, nativeExtent: .zero), url: nil)
        }
        return nil
    }

    private static func resolveScopedURL(url: URL, bookmarkData: Data?) -> URL {
        guard let bookmarkData else { return url }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return url
        }
        return resolved
    }

    /// Which edit one batch item exports, and whether it is that item's own.
    ///
    /// An item with a live snapshot or a durable record always exports that edit. A healthy package
    /// asset with no saved edit exports neutral. Only an item with no store identity at all (a
    /// caller exporting loose files) takes the caller's `fallback`; the active photo's edit is never
    /// substituted for a package asset whose own edit could not be established.
    private struct DocumentResolution {
        let document: EditDocument
        let isPerAsset: Bool
    }

    private struct ItemExportError: LocalizedError {
        let errorDescription: String?
    }

    private func resolvedDocument(
        for item: BatchItem, assetID: PhotoAssetID?, fallback: EditDocument
    ) async throws -> DocumentResolution {
        if let document = item.document { return DocumentResolution(document: document, isPerAsset: true) }
        guard let editStore, let assetID else {
            return DocumentResolution(document: fallback, isPerAsset: false)
        }
        let result = await editStore.load(
            for: EditSourceReference(
                assetID: assetID, portableIdentity: item.portableIdentity, url: item.url
            )
        )
        guard result.isUsableForPrefetch else {
            throw ItemExportError(
                errorDescription: "its saved edit could not be read (\(result.status.message ?? "unreadable"))"
            )
        }
        return DocumentResolution(
            document: result.found ? result.document : EditDocument(), isPerAsset: true
        )
    }

    /// The Look for one item. A per-asset document that names a Look which cannot be loaded fails
    /// the item rather than exporting without it and reporting a fully reproduced edit.
    private func resolvedLUT(
        for item: BatchItem, resolution: DocumentResolution, fallback lut: CubeLUT?
    ) throws -> CubeLUT? {
        if let itemLUT = item.lut { return itemLUT }
        let lutID = resolution.document.lut.lutID
        let resolved = lutResolver?(lutID)
        if resolution.isPerAsset {
            if lutID != nil, resolved == nil {
                throw ItemExportError(errorDescription: "its Look could not be loaded")
            }
            return resolved
        }
        return resolved ?? lut
    }

    /// The line shown when a batch finishes.
    nonisolated static func summary(for outcome: BatchOutcome, folder: URL) -> String {
        let destination = folder.lastPathComponent
        if outcome.cancelled {
            let processed = outcome.exported + outcome.failed
            let remaining = max(0, outcome.total - processed)
            return "Export cancelled after \(processed) of \(outcome.total) (\(outcome.exported) exported, \(outcome.failed) failed, \(remaining) not started)\(photosSummary(for: outcome)) to \(destination)"
        }
        if outcome.failed == 0 {
            let plural = outcome.exported == 1 ? "" : "s"
            return "Exported \(outcome.exported) image\(plural)\(photosSummary(for: outcome)) to \(destination)"
        }
        return "Exported \(outcome.exported) of \(outcome.total) (\(outcome.failed) failed)\(photosSummary(for: outcome)) to \(destination)"
    }

    private func reportPhotosSuccess(_ result: PhotosDeliveryResult, filename: String) {
        if let warning = result.warning {
            onStatus?("Exported: \(filename); Photos warning: \(warning)")
        } else if result.albumAdded {
            onStatus?("Exported: \(filename) and added to Photos album")
        } else {
            onStatus?("Exported: \(filename) and added to Photos")
        }
    }

    nonisolated private static func photosSummary(for outcome: BatchOutcome) -> String {
        guard outcome.photosFailed > 0 else { return "" }
        return " (Photos: \(outcome.photosFailed) failed)"
    }
}

// MARK: - Export format control

/// The format choice belongs to the export flow, alongside the destination, rather than in the
/// editor toolbar. Keeping this as an AppKit accessory also lets the Save panel update its filename
/// extension and content-type filter as the user changes the explicit export choice.
@MainActor
private final class ExportFormatAccessoryView: NSView {
    private let picker: NSSegmentedControl
    private let metadataCheckbox: NSButton
    private let locationCheckbox: NSButton
    private let photosCheckbox: NSButton
    private let albumField: NSTextField
    private let sharpeningMedium: NSPopUpButton
    private let sharpeningStrength: NSPopUpButton
    var onSelectionChanged: ((ExportFormat) -> Void)?

    init(selectedFormat: ExportFormat) {
        picker = NSSegmentedControl(
            labels: ExportFormat.allCases.map(\.rawValue),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        metadataCheckbox = NSButton(
            checkboxWithTitle: "Preserve camera metadata (EXIF/TIFF)", target: nil, action: nil
        )
        locationCheckbox = NSButton(
            checkboxWithTitle: "Include location metadata (GPS)", target: nil, action: nil
        )
        photosCheckbox = NSButton(
            checkboxWithTitle: "Also add to Photos", target: nil, action: nil
        )
        albumField = NSTextField(string: "")
        sharpeningMedium = NSPopUpButton(frame: .zero, pullsDown: false)
        sharpeningStrength = NSPopUpButton(frame: .zero, pullsDown: false)
        super.init(frame: .zero)

        let label = NSTextField(labelWithString: "Export format:")
        label.setContentHuggingPriority(.required, for: .horizontal)

        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.target = self
        picker.action = #selector(selectionChanged)
        picker.selectedSegment = ExportFormat.allCases.firstIndex(of: selectedFormat) ?? 0
        picker.setAccessibilityLabel("Export format")
        picker.setAccessibilityHelp("Choose TIFF, JPEG, PNG, or HEIF for the exported image")

        metadataCheckbox.state = .on
        metadataCheckbox.target = self
        metadataCheckbox.action = #selector(metadataSelectionChanged)
        metadataCheckbox.setAccessibilityLabel("Preserve camera metadata")
        metadataCheckbox.setAccessibilityHelp(
            "Keep camera and capture metadata without enabling location sharing"
        )

        locationCheckbox.state = .off
        locationCheckbox.target = self
        locationCheckbox.action = #selector(locationSelectionChanged)
        locationCheckbox.setAccessibilityLabel("Include location metadata")
        locationCheckbox.setAccessibilityHelp(
            "Share the source photo's precise GPS location; off by default"
        )

        photosCheckbox.setAccessibilityLabel("Also add to Photos")
        photosCheckbox.target = self
        photosCheckbox.action = #selector(photosSelectionChanged)

        albumField.placeholderString = "Album (optional)"
        albumField.isEnabled = false
        albumField.setAccessibilityLabel("Photos album name")

        sharpeningMedium.addItems(withTitles: ["None", "Screen", "Matte", "Glossy"])
        sharpeningMedium.selectItem(at: 0)
        sharpeningMedium.setAccessibilityLabel("Output sharpening medium")
        sharpeningStrength.addItems(withTitles: ["Low", "Standard", "High"])
        sharpeningStrength.selectItem(at: 1)
        sharpeningStrength.setAccessibilityLabel("Output sharpening strength")

        let formatStack = NSStackView(views: [label, picker])
        formatStack.orientation = .horizontal
        formatStack.alignment = .centerY
        formatStack.spacing = 8
        let photosStack = NSStackView(views: [photosCheckbox, albumField])
        photosStack.orientation = .horizontal
        photosStack.alignment = .centerY
        photosStack.spacing = 8
        let privacyStack = NSStackView(views: [metadataCheckbox, locationCheckbox])
        privacyStack.orientation = .vertical
        privacyStack.alignment = .leading
        privacyStack.spacing = 2
        let sharpeningLabel = NSTextField(labelWithString: "Output sharpening:")
        let sharpeningStack = NSStackView(views: [sharpeningLabel, sharpeningMedium, sharpeningStrength])
        sharpeningStack.orientation = .horizontal
        sharpeningStack.alignment = .centerY
        sharpeningStack.spacing = 8
        let stack = NSStackView(views: [formatStack, privacyStack, photosStack, sharpeningStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 480, height: 142)
    }

    var selectedFormat: ExportFormat {
        let index = picker.selectedSegment
        guard ExportFormat.allCases.indices.contains(index) else { return .jpeg }
        return ExportFormat.allCases[index]
    }

    var photosOptions: PhotosExportOptions? {
        guard photosCheckbox.state == .on else { return nil }
        return PhotosExportOptions(albumName: albumField.stringValue)
    }

    var metadataPolicy: ExportMetadataPolicy {
        metadataCheckbox.state == .on ? .preserve : .strip
    }

    var locationPolicy: ExportLocationPolicy {
        metadataCheckbox.state == .on && locationCheckbox.state == .on ? .include : .exclude
    }

    var outputSharpening: OutputSharpening {
        let media = OutputSharpeningMedium.allCases[sharpeningMedium.indexOfSelectedItem]
        let strengthIndex = max(0, min(OutputSharpeningStrength.allCases.count - 1,
                                       sharpeningStrength.indexOfSelectedItem))
        return OutputSharpening(medium: media, strength: OutputSharpeningStrength.allCases[strengthIndex])
    }

    @objc private func selectionChanged() {
        onSelectionChanged?(selectedFormat)
    }

    @objc private func metadataSelectionChanged() {
        locationCheckbox.isEnabled = metadataCheckbox.state == .on
    }

    @objc private func locationSelectionChanged() {}

    @objc private func photosSelectionChanged() {
        albumField.isEnabled = photosCheckbox.state == .on
    }
}

// MARK: - Naming helpers

/// A non-colliding `base.ext` URL inside `folder`, appending " 2", " 3", …
/// when a file of that name already exists. Free function (not `@MainActor`)
/// so it can be called from the off-actor batch export task.
func uniqueExportURL(in folder: URL, base: String, ext: String) -> URL {
    let fm = FileManager.default
    var candidate = folder.appendingPathComponent("\(base).\(ext)")
    var n = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
        n += 1
    }
    return candidate
}
