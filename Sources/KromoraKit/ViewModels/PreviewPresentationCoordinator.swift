import CoreGraphics
import CoreImage
import Foundation

/// Value-state owner for preview presentation policy.
///
/// `PreviewCoordinator` remains the renderer-admission owner. This layer owns the state shared by
/// settled, interactive, comparison, and cache-only requests: display/baseline generations,
/// hysteretic resolution planners, and the durable preview cache. It deliberately has no
/// presentation surface or `AppViewModel` reference, so request planning, cache-hit behavior, and
/// revision fencing can be tested with a fake renderer and a temporary cache directory.
@MainActor
final class PreviewPresentationCoordinator {
    private(set) var displayRevision: UInt64 = 0
    private(set) var comparisonRevision: UInt64 = 0

    private var mainPlanner = ResolutionPlanner()
    private var comparisonPlanner = ResolutionPlanner()
    private var histogramPlanner = ResolutionPlanner()
    private var cacheLookupTask: Task<Void, Never>?
    let cache: PreviewDiskCache

    init(cache: PreviewDiskCache) {
        self.cache = cache
    }

    func advanceDisplayRevision() { displayRevision &+= 1 }
    func advanceComparisonRevision() { comparisonRevision &+= 1 }

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

    func cacheKey(for request: RenderRequest) -> PreviewDiskCache.Key {
        PreviewDiskCache.Key(
            identity: request.source.cacheIdentity,
            documentHash: request.document.editHash,
            lookFingerprint: request.lut?.cacheFingerprint ?? "unresolved",
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
            let image = await Task.detached(priority: .utility) {
                cache.read(for: key)
            }.value
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
    /// applies the same complete-frame/ROI rule. Rasterization still belongs to Core Image's
    /// existing render owner (`PreviewDiskCache.canonicalRaster`).
    func writeCanonical(_ image: CIImage, for request: RenderRequest) {
        guard request.quality == .preview, request.sourceROI == nil else { return }
        let cache = self.cache
        let key = cacheKey(for: request)
        Task.detached(priority: .background) {
            guard !Task.isCancelled,
                let raster = PreviewDiskCache.canonicalRaster(from: image, space: request.space),
                !Task.isCancelled else { return }
            cache.write(raster, for: key)
        }
    }

    func shutdown() {
        cancelCacheLookup()
    }
}
