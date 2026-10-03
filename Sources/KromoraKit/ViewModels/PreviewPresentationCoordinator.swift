import CryptoKit
import CoreGraphics
import CoreImage
import Foundation
import os.log

/// Value-state owner for preview presentation policy.
///
/// `PreviewCoordinator` remains the renderer-admission owner. This layer owns the state shared by
/// settled, interactive, comparison, and cache-only requests: display/baseline generations,
/// hysteretic resolution planners, and the latest-frame store lookup/write policy. It deliberately
/// has no presentation surface or `AppViewModel` reference, so request planning, stored-frame
/// behavior, and revision fencing can be tested with a fake renderer and a temporary directory.
@MainActor
final class PreviewPresentationCoordinator {
    enum CandidateSource: String, Sendable, Equatable {
        case storedFrame
        case editedThumbnail
        case originalThumbnail
        case embeddedJPEG
        case rendered
    }

    /// A persisted preview read at selection time, before the source has been prepared. It is
    /// inert: it may fill the canvas and, once every current input is known and matches, stand in
    /// for the settled render. It never drives editing tools, histograms, or writes.
    struct StoredFrameCandidate {
        let metadata: PresentationFrameMetadata
        let image: CGImage
    }

    enum StoredFrameLookup {
        /// No lookup was started for this selection.
        case idle
        case loading
        case candidate(StoredFrameCandidate)
        /// Missed, unusable for this photo, or already consumed by a confirmed frame.
        case unavailable
    }

    enum SessionState: Sendable, Equatable {
        case provisional
        case confirmed
    }

    struct PresentationSession: Sendable, Equatable {
        let assetID: PhotoAssetID
        let identity: PortablePhotoIdentity
        let generation: UInt64
        let selectionUptime: UInt64
        fileprivate(set) var state: SessionState
        fileprivate(set) var candidateSource: CandidateSource?
        /// Preserves pre-confirmation provenance after a settled frame replaces the candidate.
        fileprivate(set) var provisionalCandidateSources: [CandidateSource]
        fileprivate(set) var firstPixelLatencyMilliseconds: Double?
        fileprivate(set) var confirmedLatencyMilliseconds: Double?
        fileprivate(set) var distinctFrameCount: Int
        fileprivate(set) var provisionalFrameCount: Int
        fileprivate(set) var confirmedFrameCount: Int
        fileprivate(set) var staleGenerationDrops: Int
    }

    private static let presentationSignposter = OSSignposter(
        subsystem: "com.kromora.app", category: "presentation-session"
    )
    private(set) var presentationSession: PresentationSession?
    private(set) var displayRevision: UInt64 = 0
    private(set) var comparisonRevision: UInt64 = 0

    private var mainPlanner = ResolutionPlanner()
    private var comparisonPlanner = ResolutionPlanner()
    private var histogramPlanner = ResolutionPlanner()
    private var storedFrameTask: Task<Void, Never>?
    private var storedFrameSessionGeneration: UInt64?
    private(set) var storedFrameLookup: StoredFrameLookup = .idle
    private var canonicalWriteTasks: [PortablePhotoAssetID: Task<Void, Never>] = [:]
    private var acceptsCanonicalWrites = true
    private var canonicalStoreEnqueueCount = 0
    private var canonicalStoreEnqueueWaiters: [CheckedContinuation<Void, Never>] = []
    let store: LatestPreviewFrameStore
    private let engine: any RenderEngining
    let frameLookupLedger: FrameLookupLedger

    init(
        store: LatestPreviewFrameStore, engine: any RenderEngining = RenderEngine.shared,
        frameLookupLedger: FrameLookupLedger = .shared
    ) {
        self.store = store
        self.engine = engine
        self.frameLookupLedger = frameLookupLedger
    }

    func advanceDisplayRevision() { displayRevision &+= 1 }
    func advanceComparisonRevision() { comparisonRevision &+= 1 }

    func beginPresentationSession(
        assetID: PhotoAssetID, identity: PortablePhotoIdentity, generation: UInt64,
        selectionUptime: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        cancelStoredFrameLookup()
        presentationSession = PresentationSession(
            assetID: assetID, identity: identity, generation: generation,
            selectionUptime: selectionUptime,
            state: .provisional, candidateSource: nil,
            provisionalCandidateSources: [],
            firstPixelLatencyMilliseconds: nil, confirmedLatencyMilliseconds: nil,
            distinctFrameCount: 0, provisionalFrameCount: 0, confirmedFrameCount: 0,
            staleGenerationDrops: 0
        )
        let token = Self.opaqueToken(identity)
        Self.presentationSignposter.emitEvent(
            "PresentationSelection", "asset=\(token, privacy: .public) generation=\(generation)"
        )
    }

    /// The single admission point for inert same-asset frames. Candidate admission immediately
    /// suppresses an embedded JPEG, even if the thumbnail's drawable callback has not arrived.
    func presentProvisional(
        _ source: CandidateSource, assetID: PhotoAssetID,
        identity: PortablePhotoIdentity, generation: UInt64
    ) -> Bool {
        guard var session = presentationSession,
            session.assetID == assetID, Self.identitiesMatch(session.identity, identity),
            session.generation == generation, session.state == .provisional
        else {
            recordStaleGenerationDrop(identity: identity)
            return false
        }
        let mayReplaceCurrent: Bool
        switch (session.candidateSource, source) {
        case (nil, _): mayReplaceCurrent = true
        case (.originalThumbnail, .editedThumbnail): mayReplaceCurrent = true
        case (.editedThumbnail, .storedFrame), (.originalThumbnail, .storedFrame),
            (.embeddedJPEG, .storedFrame): mayReplaceCurrent = true
        default: mayReplaceCurrent = false
        }
        guard mayReplaceCurrent else { return false }
        session.candidateSource = source
        session.provisionalCandidateSources.append(source)
        presentationSession = session
        Self.emitPresentationMetric(
            "PresentationCandidate", session: session, source: source.rawValue
        )
        return true
    }

    func confirmProvisionalPresentation(
        _ source: CandidateSource, assetID: PhotoAssetID?,
        identity: PortablePhotoIdentity, generation: UInt64
    ) {
        guard var session = presentationSession,
            session.assetID == assetID, Self.identitiesMatch(session.identity, identity),
            session.generation == generation, session.state == .provisional,
            session.candidateSource == source else {
                recordStaleGenerationDrop(identity: identity)
                return
            }
        session.distinctFrameCount += 1
        session.provisionalFrameCount += 1
        if session.firstPixelLatencyMilliseconds == nil {
            session.firstPixelLatencyMilliseconds = Self.elapsedMilliseconds(
                since: session.selectionUptime
            )
        }
        presentationSession = session
        Self.emitPresentationMetric("PresentationFirstPixel", session: session, source: source.rawValue)
    }

    func admitsPublication(
        assetID: PhotoAssetID?, identity: PortablePhotoIdentity, generation: UInt64
    ) -> Bool {
        guard let session = presentationSession,
            session.assetID == assetID, Self.identitiesMatch(session.identity, identity),
            session.generation == generation else {
                recordStaleGenerationDrop(identity: identity)
                return false
            }
        return true
    }

    func confirmRenderedFrame(
        assetID: PhotoAssetID?, identity: PortablePhotoIdentity, generation: UInt64,
        as source: CandidateSource = .rendered
    ) {
        guard var session = presentationSession,
            session.assetID == assetID, Self.identitiesMatch(session.identity, identity),
            session.generation == generation else {
                recordStaleGenerationDrop(identity: identity)
                return
            }
        let confirmsVisibleStoredFrame = session.state == .provisional
            && session.candidateSource == .storedFrame && session.provisionalFrameCount > 0
            && source == .storedFrame
        session.state = .confirmed
        session.candidateSource = source
        consumeStoredFrame()
        if !confirmsVisibleStoredFrame { session.distinctFrameCount += 1 }
        session.confirmedFrameCount += 1
        if session.firstPixelLatencyMilliseconds == nil {
            session.firstPixelLatencyMilliseconds = Self.elapsedMilliseconds(
                since: session.selectionUptime
            )
        }
        if session.confirmedLatencyMilliseconds == nil {
            session.confirmedLatencyMilliseconds = Self.elapsedMilliseconds(
                since: session.selectionUptime
            )
        }
        presentationSession = session
        Self.emitPresentationMetric(
            "PresentationConfirmed", session: session, source: CandidateSource.rendered.rawValue
        )
    }

    func hasPresentedStoredFrame(generation: UInt64) -> Bool {
        guard let session = presentationSession, session.generation == generation else { return false }
        return session.state == .provisional && session.candidateSource == .storedFrame
            && session.provisionalFrameCount > 0
    }

    func hasStoredFrameCandidate(generation: UInt64) -> Bool {
        guard let session = presentationSession, session.generation == generation else { return false }
        return session.state == .provisional && session.candidateSource == .storedFrame
    }

    private func recordStaleGenerationDrop(identity: PortablePhotoIdentity) {
        guard var session = presentationSession else { return }
        session.staleGenerationDrops += 1
        presentationSession = session
        let token = Self.opaqueToken(identity)
        Self.presentationSignposter.emitEvent(
            "PresentationStaleDrop",
            "asset=\(token, privacy: .public) activeGeneration=\(session.generation) drops=\(session.staleGenerationDrops)"
        )
    }

    private static func elapsedMilliseconds(since uptime: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds &- uptime) / 1_000_000
    }

    private static func opaqueToken(_ identity: PortablePhotoIdentity) -> String {
        // The portable UUID already has no path/content data. Hashing it directly avoids
        // JSON-encoding the full fingerprint on every selection just to emit a private-safe token.
        let digest = SHA256.hash(data: Data(identity.assetID.raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    private static func identitiesMatch(
        _ expected: PortablePhotoIdentity, _ actual: PortablePhotoIdentity
    ) -> Bool {
        expected.assetID == actual.assetID
            && expected.sourceFingerprint.matches(actual.sourceFingerprint)
    }

    private static func emitPresentationMetric(
        _ name: StaticString, session: PresentationSession, source: String
    ) {
        let token = opaqueToken(session.identity)
        presentationSignposter.emitEvent(
            name,
            "asset=\(token, privacy: .public) generation=\(session.generation) source=\(source, privacy: .public) frames=\(session.distinctFrameCount) firstMS=\(session.firstPixelLatencyMilliseconds ?? -1) confirmedMS=\(session.confirmedLatencyMilliseconds ?? -1) staleDrops=\(session.staleGenerationDrops)"
        )
    }

    func resetPlanners() {
        mainPlanner.reset()
        comparisonPlanner.reset()
        histogramPlanner.reset()
    }

    func plan(
        for document: EditDocument,
        nativeExtent: CGSize,
        viewportSize: CGSize,
        surface: ResolutionPlannerSurface,
        navigation: CanvasNavigation
    ) -> ResolutionPlan {
        switch surface {
        case .mainPreview:
            return mainPlanner.plan(
                nativeExtent: document.rotation.orientedExtent(nativeExtent),
                crop: document.crop, viewportSize: viewportSize, navigation: navigation
            )
        case .comparisonBaseline:
            return comparisonPlanner.plan(
                nativeExtent: document.rotation.orientedExtent(nativeExtent),
                crop: document.crop, viewportSize: viewportSize, navigation: navigation
            )
        case .histogram:
            return histogramPlanner.plan(
                nativeExtent: document.rotation.orientedExtent(nativeExtent),
                crop: document.crop, viewportSize: viewportSize, navigation: navigation
            )
        }
    }

    // MARK: Stored frame

    /// Begin reading this photo's latest persisted preview. Runs in parallel with source
    /// preparation; `completion` runs on the main actor with the candidate, or `nil`, only if the
    /// selection is still the session that asked. A candidate that is unusable for this photo
    /// (different source, unpresentable color space) is reported as a miss.
    func beginStoredFrameLookup(
        assetID: PhotoAssetID, identity: PortablePhotoIdentity, generation: UInt64,
        completion: @escaping @MainActor (StoredFrameCandidate?) -> Void
    ) {
        cancelStoredFrameLookup()
        storedFrameSessionGeneration = generation
        storedFrameLookup = .loading
        let store = self.store
        storedFrameTask = Task { [weak self] in
            async let pin: Void = store.setPinned([identity.assetID])
            let result = await store.readWithOutcome(for: identity)
            let hit = result.hit
            await pin
            guard !Task.isCancelled, let self else { return }
            guard self.storedFrameSessionGeneration == generation else { return }
            self.storedFrameTask = nil
            guard let session = self.presentationSession,
                session.assetID == assetID, session.generation == generation,
                self.storedFrameSessionGeneration == generation
            else { return }
            let provisionalInputs = FrameCurrentInputs(source: identity)
            if let hit {
                let classification = FrameClassifier.classifyWithReason(
                    hit.frame.metadata, against: provisionalInputs
                )
                let outcome: FrameLookupOutcome
                switch classification.classification {
                case .exact: outcome = .exact
                case .staleCompatible: outcome = .staleCompatible
                case .provisionalOnly: outcome = .provisionalOnly
                case .unusable:
                    outcome = .rejected(classification.reason ?? .sourceFingerprintMismatch)
                }
                await self.frameLookupLedger.record(surface: .editPreview, outcome: outcome)
                guard !Task.isCancelled,
                      self.storedFrameSessionGeneration == generation else { return }
                if classification.classification.isPresentable {
                    let candidate = StoredFrameCandidate(metadata: hit.frame.metadata, image: hit.image)
                    self.storedFrameLookup = .candidate(candidate)
                    completion(candidate)
                } else {
                    self.storedFrameLookup = .unavailable
                    completion(nil)
                }
            } else {
                await self.frameLookupLedger.record(
                    surface: .editPreview,
                    outcome: result.corrupt ? .corrupt : .missingFile
                )
                self.storedFrameLookup = .unavailable
                completion(nil)
            }
        }
    }

    func cancelStoredFrameLookup() {
        let task = storedFrameTask
        storedFrameTask = nil
        storedFrameSessionGeneration = nil
        storedFrameLookup = .idle
        guard let task else { return }
        // The store task may be suspended behind package I/O. Cancellation handlers run on the
        // caller, so yield before invoking them on the selection path. Generation fencing above
        // prevents its late result from replacing a newer lookup.
        Task { @MainActor in
            await Task.yield()
            task.cancel()
        }
    }

    /// The candidate has served its purpose once a confirmed frame exists; later requests in the
    /// session (edits, undo) must render, never reuse a frame from before they happened.
    func consumeStoredFrame() {
        if case .idle = storedFrameLookup { return }
        storedFrameTask?.cancel()
        storedFrameTask = nil
        storedFrameLookup = .unavailable
    }

    /// The freshness of the session's candidate against what the request would render, or `nil`
    /// when there is no usable candidate for this source revision. `editsResolved` is false until
    /// the stored edit document has been adopted, which keeps the candidate from ever suppressing
    /// a render it cannot yet justify.
    ///
    /// `storedLook` is the current edit revision's content-addressed Look identity. It stands in
    /// for a Look the browser has not resolved yet, so a warm open is exact regardless of whether
    /// the Look scan has finished.
    func classifyStoredFrame(
        for request: RenderRequest, sourceRevision: UInt64, editsResolved: Bool,
        storedLook: LookSignature? = nil
    ) -> (classification: FrameClassification, candidate: StoredFrameCandidate)? {
        guard case .candidate(let candidate) = storedFrameLookup,
            storedFrameSessionGeneration == sourceRevision,
            let session = presentationSession, session.generation == sourceRevision
        else { return nil }
        var look = request.lookSignature
        if !look.permitsExactReuse, let storedLook, storedLook.permitsExactReuse,
            storedLook.lutID == look.lutID
        {
            look = storedLook
        }
        let inputs = FrameCurrentInputs(
            source: request.source.portableIdentity,
            editHash: editsResolved ? request.document.editHash : nil,
            look: editsResolved ? look : nil,
            workingSpace: request.space
        )
        return (FrameClassifier.classify(candidate.metadata, against: inputs), candidate)
    }

    var isStoredFrameLookupLoading: Bool {
        if case .loading = storedFrameLookup { return true }
        return false
    }

    /// Whether the persisted frame for this request's photo already matches it exactly. Used by
    /// idle building so it does not re-render what a relaunch would already show.
    func storedFrameIsExact(for request: RenderRequest) async -> Bool {
        let identity = request.source.portableIdentity
        guard let metadata = await store.metadata(for: identity) else { return false }
        let inputs = FrameCurrentInputs(
            source: identity, editHash: request.document.editHash,
            look: request.lookSignature, workingSpace: request.space
        )
        return FrameClassifier.classify(metadata, against: inputs) == .exact
    }

    func resetForSource() {
        advanceDisplayRevision()
        advanceComparisonRevision()
        resetPlanners()
    }

    /// Canonical writes are kept here so every settled presentation and every idle build applies
    /// the same complete-frame/ROI rule. An asset has one cancellable task, so rapid settled
    /// frames cannot leave a detached rasterization task per document tick.
    func writeCanonical(_ image: CIImage, for request: RenderRequest) {
        let look = request.lookSignature
        guard acceptsCanonicalWrites, request.quality == .preview,
              request.sourceROI == nil, look.permitsExactReuse
        else { return }
        let identity = request.source.portableIdentity
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return }
        let signature = FrameSignature(
            source: identity, editHash: request.document.editHash, look: look,
            workingSpace: request.space, pixelEpoch: RenderPipeline.pixelEpoch
        )
        let geometry = PresentedGeometry(
            crop: request.document.crop, rotation: request.document.rotation,
            orientedAspectRatio: Double(extent.width / extent.height)
        )
        canonicalWriteTasks[identity.assetID]?.cancel()
        let store = self.store
        let engine = self.engine
        canonicalWriteTasks[identity.assetID] = Task { [weak self] in
            guard !Task.isCancelled,
                  let raster = await engine.makeCanonicalPreviewRaster(
                      image, space: request.space, longEdge: LatestPreviewFrameStore.canonicalLongEdge
                  ), !Task.isCancelled,
                  let self, self.acceptsCanonicalWrites else { return }
            let frame = PresentationFrame(
                metadata: PresentationFrameMetadata(
                    identity: identity, kind: .preview2048, signature: signature,
                    geometry: geometry, rasterColorSpace: raster.rasterColorSpace,
                    perceptualDigest: raster.perceptualDigest, presentedAt: Date(),
                    pixelWidth: raster.pixelWidth, pixelHeight: raster.pixelHeight
                ),
                rasterData: raster.jpegData
            )
            self.canonicalStoreEnqueueCount += 1
            await store.enqueueWrite(frame)
            self.canonicalStoreEnqueueCount -= 1
            if self.canonicalStoreEnqueueCount == 0 {
                let waiters = self.canonicalStoreEnqueueWaiters
                self.canonicalStoreEnqueueWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
            self.canonicalWriteTasks.removeValue(forKey: identity.assetID)
        }
    }

    /// Wait for writes already admitted by the preview store. Canonical rasterization that has
    /// not reached the store remains ordinary cancellable renderer work.
    func flushPendingWrites() async {
        await store.waitForPendingWrites()
    }

    func shutdown() async {
        acceptsCanonicalWrites = false
        cancelStoredFrameLookup()
        let writeTasks = Array(canonicalWriteTasks.values)
        for task in writeTasks { task.cancel() }
        canonicalWriteTasks.removeAll()
        // Rasterization that has not entered the store is cancelled and need not delay exit.
        if canonicalStoreEnqueueCount > 0 {
            await withCheckedContinuation {
                canonicalStoreEnqueueWaiters.append($0)
            }
        }
        await store.waitForPendingWrites()
    }
}
