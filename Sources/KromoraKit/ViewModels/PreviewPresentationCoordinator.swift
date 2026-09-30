import CryptoKit
import CoreGraphics
import CoreImage
import Foundation
import os.log

/// Value-state owner for preview presentation policy.
///
/// `PreviewCoordinator` remains the renderer-admission owner. This layer owns the state shared by
/// settled, interactive, comparison, and cache-only requests: display/baseline generations,
/// hysteretic resolution planners, and the durable preview cache. It deliberately has no
/// presentation surface or `AppViewModel` reference, so request planning, cache-hit behavior, and
/// revision fencing can be tested with a fake renderer and a temporary cache directory.
@MainActor
final class PreviewPresentationCoordinator {
    enum CandidateSource: String, Sendable, Equatable {
        case editedThumbnail
        case originalThumbnail
        case embeddedJPEG
        case rendered
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
        fileprivate(set) var firstPixelLatencyMilliseconds: Double?
        fileprivate(set) var confirmedLatencyMilliseconds: Double?
        fileprivate(set) var distinctFrameCount: Int
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
    private var cacheLookupTask: Task<Void, Never>?
    private var canonicalWriteTasks: [PreviewDiskCache.Key: Task<Void, Never>] = [:]
    let cache: PreviewDiskCache
    private let engine: any RenderEngining

    init(cache: PreviewDiskCache, engine: any RenderEngining = RenderEngine.shared) {
        self.cache = cache
        self.engine = engine
    }

    func advanceDisplayRevision() { displayRevision &+= 1 }
    func advanceComparisonRevision() { comparisonRevision &+= 1 }

    func beginPresentationSession(
        assetID: PhotoAssetID, identity: PortablePhotoIdentity, generation: UInt64
    ) {
        presentationSession = PresentationSession(
            assetID: assetID, identity: identity, generation: generation,
            selectionUptime: DispatchTime.now().uptimeNanoseconds,
            state: .provisional, candidateSource: nil,
            firstPixelLatencyMilliseconds: nil, confirmedLatencyMilliseconds: nil,
            distinctFrameCount: 0, staleGenerationDrops: 0
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
        default: mayReplaceCurrent = false
        }
        guard mayReplaceCurrent else { return false }
        session.candidateSource = source
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
        assetID: PhotoAssetID?, identity: PortablePhotoIdentity, generation: UInt64
    ) {
        guard var session = presentationSession,
            session.assetID == assetID, Self.identitiesMatch(session.identity, identity),
            session.generation == generation else {
                recordStaleGenerationDrop(identity: identity)
                return
            }
        session.state = .confirmed
        session.candidateSource = .rendered
        session.distinctFrameCount += 1
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
        let digest = SHA256.hash(data: identity.canonicalData)
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

    /// The exact-pixel key for a canonical request, or `nil` when its Look is unresolved. An
    /// unresolved request renders provisional (ungraded) pixels: they may be shown, but must be
    /// neither served from nor written to the durable cache, whichever side of a Look scan the
    /// request falls on.
    func cacheKey(for request: RenderRequest) -> PreviewDiskCache.Key? {
        let look = request.lookSignature
        guard look.permitsExactReuse else { return nil }
        return PreviewDiskCache.Key(
            identity: request.source.cacheIdentity,
            documentHash: request.document.editHash,
            look: look,
            targetSizeBucket: String(PreviewDiskCache.canonicalLongEdge),
            space: request.space,
            pipelineVersion: RenderPipeline.cacheVersion
        )
    }

    func cancelCacheLookup() {
        cacheLookupTask?.cancel()
        cacheLookupTask = nil
    }

    /// Performs cache I/O outside the main actor and returns only an exact-key raster. The caller
    /// still owns the source/display fence because it also owns the visible document and surfaces.
    func lookupCache(
        for key: PreviewDiskCache.Key,
        completion: @escaping @MainActor (CGImage?) -> Void
    ) {
        cancelCacheLookup()
        let cache = self.cache
        cacheLookupTask = Task { [weak self] in
            let image = await cache.readAsync(for: key)
            guard !Task.isCancelled, let self else { return }
            self.cacheLookupTask = nil
            completion(image)
        }
    }

    func resetForSource() {
        advanceDisplayRevision()
        advanceComparisonRevision()
        resetPlanners()
    }

    /// Canonical cache writes are kept here so every settled presentation and every idle build
    /// applies the same complete-frame/ROI rule. A key has one cancellable task, so rapid settled
    /// frames cannot leave a detached rasterization task per document tick.
    func writeCanonical(_ image: CIImage, for request: RenderRequest) {
        guard request.quality == .preview, request.sourceROI == nil,
              let key = cacheKey(for: request) else { return }
        canonicalWriteTasks[key]?.cancel()
        let cache = self.cache
        let engine = self.engine
        canonicalWriteTasks[key] = Task { [weak self] in
            guard !Task.isCancelled,
                  let raster = await engine.makeCanonicalPreviewRaster(
                      image, space: request.space, longEdge: PreviewDiskCache.canonicalLongEdge
                  ), !Task.isCancelled else { return }
            await cache.enqueueWrite(raster, for: key)
            guard let self else { return }
            self.canonicalWriteTasks.removeValue(forKey: key)
        }
    }

    func shutdown() {
        cancelCacheLookup()
        for task in canonicalWriteTasks.values { task.cancel() }
        canonicalWriteTasks.removeAll()
    }
}
