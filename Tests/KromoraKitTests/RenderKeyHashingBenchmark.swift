import CoreGraphics
import Metal
import XCTest

@testable import KromoraKit

/// KRMA-954 baseline: how much of a repeated preview request is spent JSON-encoding and SHA-256
/// hashing the edit document, mask recipes, and RAW-develop settings for cache identity.
///
/// Not an assertion — a measurement for `docs/RENDER_KEY_PLAN.md`. It drives a real `RenderEngine`
/// (no `NSWindow`) for warm per-request wall time, and times the exact `RenderCacheHash.digest`
/// inputs the engine derives for one warm masked interactive request. It also measures the extra
/// default-resolver digest work on a cache miss. The digest sets are mirrored from `RenderEngine`
/// call sites rather than counted inside the engine, so the benchmark adds no production
/// instrumentation; keep `requestDigestSet` in step with those sites when they move. Since KRMA-1101
/// the set is the memoized `RenderDocumentIdentity` builds rather than per-site document digests.
///
/// Opt-in: `KROMORA_RENDER_KEY_BENCHMARK=1 swift test -c release --filter RenderKeyHashingBenchmark`.
final class RenderKeyHashingBenchmark: TempDirectoryTestCase {
    private struct Recipe {
        let name: String
        let masks: Int
        let strokesPerMask: Int
        let samplesPerStroke: Int

        var sampleCount: Int { masks * strokesPerMask * samplesPerStroke }
    }

    private static let recipes = [
        Recipe(name: "plain", masks: 0, strokesPerMask: 0, samplesPerStroke: 0),
        Recipe(name: "5-brush", masks: 5, strokesPerMask: 2, samplesPerStroke: 48),
        Recipe(name: "5-brush-large", masks: 5, strokesPerMask: 8, samplesPerStroke: 512),
    ]

    private let imageWidth = 1600
    private let imageHeight = 1200

    // MARK: - Fixtures

    /// Deterministic brush geometry. A wandering path keeps every sample distinct, as a painted
    /// stroke would be, so the JSON payload is not artificially compressible or repetitive.
    private static func stroke(mask: Int, index: Int, samples: Int) -> BrushStroke {
        let points = (0..<samples).map { step -> BrushSample in
            let t = Double(step) / Double(max(1, samples - 1))
            let phase = Double(mask * 31 + index * 7)
            return BrushSample(
                point: CGPoint(
                    x: 0.1 + 0.8 * t,
                    y: 0.5 + 0.3 * sin(t * 6.283 + phase) * cos(t * 2.1 + phase * 0.5)
                ),
                pressure: 0.6 + 0.4 * abs(sin(t * 9 + phase))
            )
        }
        return BrushStroke(samples: points, radius: 0.04, feather: 0.5, flow: 0.8, density: 1)
    }

    private static func document(_ recipe: Recipe) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = 0.3
        document.light.contrast = 12
        document.color.vibrance = 10
        document.localAdjustments = (0..<recipe.masks).map { mask in
            LocalAdjustmentLayer(
                name: "Brush \(mask)",
                components: [
                    MaskComponent(
                        name: "Brush",
                        source: .brush(BrushMaskDefinition(strokes: (0..<recipe.strokesPerMask).map {
                            stroke(mask: mask, index: $0, samples: recipe.samplesPerStroke)
                        }))
                    )
                ],
                adjustments: LocalAdjustments(exposure: 0.4 + Double(mask) * 0.1)
            )
        }
        return document
    }

    /// Mutable memo and tick counter shared by the warm closures, which the engine would call on
    /// the render actor in sequence.
    private final class IdentityTicker {
        var memo = RenderDocumentIdentityMemo()
        var document: EditDocument
        let source: RenderSourceFingerprint

        init(document: EditDocument, source: RenderSourceFingerprint) {
            self.document = document
            self.source = source
            _ = memo.identity(for: document, source: source)
        }

        /// One exposure tick: the next request's document, as a slider drag produces.
        func tick() -> String {
            document.light.exposure += 0.01
            return memo.identity(for: document, source: source).sessionKey
        }

        /// A repeat lookup of the same document (the second use within one request).
        func repeatLookup() -> String { memo.identity(for: document, source: source).sessionKey }
    }

    /// Every `RenderCacheHash.digest` a warm masked interactive standard-source preview still pays
    /// after KRMA-1101: the engine builds the memoized `RenderDocumentIdentity` once for the preview
    /// key and once more in `buildImage` (a memo hit), and nothing else digests a document, a
    /// component source, or the RAW-develop settings. A first cache miss builds the identity cold;
    /// the default resolver reuses the identity's component digests instead of hashing again.
    private static func requestDigestSet(
        _ document: EditDocument,
        source: RenderSourceFingerprint,
        includeDefaultResolver: Bool = false
    ) -> [(String, () -> String)] {
        if includeDefaultResolver {
            return [("identity cold build", { RenderDocumentIdentity(document).sessionKey })]
        }
        let ticker = IdentityTicker(document: document, source: source)
        return [
            ("previewCacheKey identity (memoized exposure tick)", { ticker.tick() }),
            ("buildImage identity (memo hit)", { ticker.repeatLookup() }),
        ]
    }

    // MARK: - Timing

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func p95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(ceil(0.95 * Double(sorted.count))) - 1)]
    }

    /// Median and p95 milliseconds of `body` over `iterations` timed runs after one warm-up.
    private static func time(_ iterations: Int, _ body: () -> Void) -> (median: Double, p95: Double) {
        body()
        let clock = ContinuousClock()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            samples.append(milliseconds(clock.measure(body)))
        }
        return (median(samples), p95(samples))
    }

    // MARK: - Benchmark

    func testOptInRenderKeyHashingBaseline() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_RENDER_KEY_BENCHMARK"] == "1",
            "set KROMORA_RENDER_KEY_BENCHMARK=1 to run the KRMA-954 render-key hashing baseline"
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let iterations = max(
            5, Int(ProcessInfo.processInfo.environment["KROMORA_RENDER_KEY_ITERATIONS"] ?? "30") ?? 30
        )
        let url = try Fixtures.writeGradientPNG(
            width: imageWidth, height: imageHeight, named: "render-key.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: imageWidth, height: imageHeight))

        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        print("\n=== KRMA-954 render-key hashing baseline ===")
        print(
            "chip=\(device.name) os=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion) " +
                "build=\(configuration) iterations=\(iterations) image=\(imageWidth)x\(imageHeight)"
        )

        for recipe in Self.recipes {
            let document = Self.document(recipe)
            let json = try JSONEncoder().encode(document)
            let benchmarkSource = RenderSourceFingerprint(source)
            let warmDigestSet = Self.requestDigestSet(document, source: benchmarkSource)
            let coldDigestSet = Self.requestDigestSet(
                document, source: benchmarkSource, includeDefaultResolver: true)

            // A warm slider tick hits cached mask payloads but still hashes their definitions for
            // cache lookup and composition. The resolver hash is paid only on a payload miss.
            let warmPerRequest = Self.time(iterations) {
                for (_, digest) in warmDigestSet { _ = digest() }
            }
            let coldPerRequest = Self.time(iterations) {
                for (_, digest) in coldDigestSet { _ = digest() }
            }
            // One whole-document durable identity: `editHash`/`renderingHash`. The main actor
            // computes this at least twice per slider tick in `markingManualEdits`.
            let editHash = Self.time(iterations) { _ = document.editHash }

            // Main-actor cost per presented slider tick: one `markingManualEdits` plus one
            // frame-identity construction. Before KRMA-1098 this was two `renderingHash` calls
            // plus one `editHash`; it is now `==` on the documents.
            let tickBase = document
            var tickEdited = document
            tickEdited.light.exposure += 0.01
            let mainActorTick = Self.time(iterations) {
                _ = EditDocument.markingManualEdits(from: tickBase, to: tickEdited)
                _ = PreviewFrameIdentity(
                    sourceToken: source.traceToken, document: tickEdited.visibleEditValue,
                    space: .current)
            }
            // KRMA-1099: first-miss cost for 30 distinct drag values. `sync` is what a consumer on
            // the main actor paid before the off-caller path (the digest on the caller). The
            // off-caller figure is the only work left on the calling actor before the digest hops to
            // the concurrent pool: the memo lookup, which is a miss for a new value.
            let dragMemo = DurableEditIdentityMemo()
            let syncMemo = DurableEditIdentityMemo()
            var dragDocument = document
            var syncMisses: [Double] = []
            var callerLookups: [Double] = []
            var offCallerEndToEnd: [Double] = []
            let missClock = ContinuousClock()
            for tick in 0..<30 {
                dragDocument.light.exposure = 0.01 * Double(tick + 1)
                syncMisses.append(Self.milliseconds(missClock.measure {
                    _ = syncMemo.digest(for: dragDocument)
                }))
                callerLookups.append(Self.milliseconds(missClock.measure {
                    _ = dragMemo.cachedDigest(for: dragDocument)
                }))
                offCallerEndToEnd.append(Self.milliseconds(await missClock.measure {
                    _ = await dragMemo.digestOffCaller(for: dragDocument)
                }))
            }
            XCTAssertEqual(dragMemo.computationCount, 30)
            XCTAssertEqual(syncMemo.computationCount, 30)
            print(String(
                format: "recipe=%@ first_miss_sync_ms=%.3f first_miss_main_actor_ms=%.4f " +
                    "first_miss_off_caller_end_to_end_ms=%.3f digests_per_distinct_value=1",
                recipe.name as NSString, Self.median(syncMisses), Self.median(callerLookups),
                Self.median(offCallerEndToEnd)))

            print(String(
                format: "recipe=%@ main_actor_tick_ms=%.4f p95=%.4f",
                recipe.name as NSString, mainActorTick.median, mainActorTick.p95))

            // Candidate costs for the plan. An exposure tick leaves `localAdjustments` sharing
            // storage with the previous value, so `==` takes Array's buffer-identity fast path.
            var ticked = document
            ticked.light.exposure += 0.01
            let unchangedCompare = Self.time(iterations) {
                _ = ticked.localAdjustments == document.localAdjustments
            }
            // Worst case for equality: an equal value with distinct storage (a decoded document,
            // or undo to an older value), forcing element-wise comparison of every brush sample.
            let rebuilt = try JSONDecoder().decode(EditDocument.self, from: json)
            XCTAssertEqual(rebuilt.localAdjustments, document.localAdjustments)
            let deepCompare = Self.time(iterations) {
                _ = rebuilt.localAdjustments == document.localAdjustments
            }
            let changedComponent = Self.time(iterations) {
                _ = RenderCacheHash.digest(ticked.light)
            }

            // KRMA-1100: `RenderDocumentIdentity` cold build versus a memoized build after an
            // exposure tick (only the changed component is digested).
            let coldIdentity = Self.time(iterations) { _ = RenderDocumentIdentity(document) }
            let fingerprint = RenderSourceFingerprint(source)
            var identityMemo = RenderDocumentIdentityMemo()
            _ = identityMemo.identity(for: document, source: fingerprint)
            var identityTick = document
            let memoizedIdentity = Self.time(iterations) {
                identityTick.light.exposure += 0.01
                _ = identityMemo.identity(for: identityTick, source: fingerprint)
            }
            print(String(
                format: "recipe=%@ identity_build_ms cold=%.4f memoized_exposure_tick=%.4f p95=%.4f",
                recipe.name as NSString, coldIdentity.median, memoizedIdentity.median,
                memoizedIdentity.p95))

            // KRMA-1102: a paint tick appends one sample to the last stroke of the last brush
            // mask. Identity work should scale with that stroke, not the whole mask.
            if recipe.masks > 0 {
                var paintMemo = RenderDocumentIdentityMemo()
                _ = paintMemo.identity(for: document, source: fingerprint)
                var paintDocument = document
                let layerIndex = paintDocument.localAdjustments.count - 1
                let paintTick = Self.time(iterations) {
                    guard case .brush(var brush) = paintDocument.localAdjustments[layerIndex]
                        .components[0].source else { return }
                    let last = brush.strokes.count - 1
                    let n = Double(brush.strokes[last].samples.count)
                    brush.strokes[last].samples.append(
                        BrushSample(point: CGPoint(x: 0.5 + 0.0001 * n.truncatingRemainder(dividingBy: 100), y: 0.5)))
                    paintDocument.localAdjustments[layerIndex].components[0].source = .brush(brush)
                    _ = paintMemo.identity(for: paintDocument, source: fingerprint)
                }
                print(String(
                    format: "recipe=%@ paint_tick_identity_ms median=%.4f p95=%.4f",
                    recipe.name as NSString, paintTick.median, paintTick.p95))
            }

            // Real engine, interactive exposure ticks: masks hit their payload cache after the
            // first tick, while the global change misses the preview raster cache every time.
            let engine = RenderEngine()
            let clock = ContinuousClock()
            var renderSamples: [Double] = []
            for tick in 0...iterations {
                // One recipe mutated per tick, as a slider drag does: layer, component, and stroke
                // IDs stay stable, so only the global exposure differs between requests.
                var tickDocument = document
                tickDocument.light.exposure = 0.3 + Double(tick) * 0.01
                let request = RenderRequest(
                    source: source,
                    document: tickDocument,
                    targetSize: CGSize(width: imageWidth, height: imageHeight),
                    quality: .interactive,
                    requestRevision: UInt64(tick + 1)
                )
                var image: CGImage?
                let elapsed = await clock.measure {
                    image = await engine.makeCGImage(request)
                }
                XCTAssertNotNil(image, "\(recipe.name) tick \(tick) did not render")
                if tick > 0 { renderSamples.append(Self.milliseconds(elapsed)) }
            }
            let renderMedian = Self.median(renderSamples)
            let caches = await engine.cacheStatistics()
            let work = await engine.workStatistics()

            print(
                String(
                    format: "recipe=%@ masks=%d samples=%d json_bytes=%d " +
                        "warm_digests_per_request=%d warm_digest_ms_per_request=%.3f " +
                        "warm_p95=%.3f cold_digests_per_request=%d " +
                        "cold_digest_ms_per_request=%.3f edit_hash_ms=%.3f " +
                        "render_ms_per_warm_request=%.2f p95=%.2f digest_share=%.1f%% " +
                        "unchanged_eq_us=%.2f deep_eq_us=%.1f changed_component_digest_us=%.1f",
                    recipe.name as NSString, recipe.masks, recipe.sampleCount, json.count,
                    warmDigestSet.count, warmPerRequest.median, warmPerRequest.p95,
                    coldDigestSet.count, coldPerRequest.median, editHash.median,
                    renderMedian, Self.p95(renderSamples),
                    warmPerRequest.median / renderMedian * 100,
                    unchangedCompare.median * 1_000, deepCompare.median * 1_000,
                    changedComponent.median * 1_000
                )
            )
            print(
                "  caches recipe=\(recipe.name) localMask hits=\(caches.localMask.hits) " +
                    "misses=\(caches.localMask.misses) processingPrefix hits=\(caches.processingPrefix.hits) " +
                    "misses=\(caches.processingPrefix.misses) developedSource hits=" +
                    "\(caches.developedSource.hits) prefixMaterializations=" +
                    "\(work.processingPrefixMaterializations)"
            )
        }
    }
}
