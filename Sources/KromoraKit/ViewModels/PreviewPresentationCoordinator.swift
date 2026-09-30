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
    private var canonicalWriteTasks: [PreviewDiskCache.Key: Task<Void, Never>] = [:]
    let cache: PreviewDiskCache
    private let engine: any RenderEngining

    init(cache: PreviewDiskCache, engine: any RenderEngining = RenderEngine.shared) {
        self.cache = cache
        self.engine = engine
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
