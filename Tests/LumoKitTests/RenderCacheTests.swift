import XCTest
import CoreGraphics
import ImageIO
@testable import LumoKit

/// Cache contract tests: cache hits are observable, keys are complete, and resource use stays
/// bounded without ever caching the final full-resolution export path.
final class RenderCacheTests: TempDirectoryTestCase {

    private func makeSource() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "cache.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    private func request(
        source: ImageSource,
        document: EditDocument = EditDocument(),
        targetSize: CGSize = CGSize(width: 32, height: 32),
        quality: RenderQuality = .preview,
        space: WorkingSpace = .sRGB
    ) -> RenderRequest {
        RenderRequest(
            source: source, document: document, targetSize: targetSize,
            quality: quality, output: .raster, space: space
        )
    }

    private func semanticDocument(generationVersion: Int = 1) -> EditDocument {
        EditDocument(localAdjustments: [
            LocalAdjustmentLayer(
                components: [MaskComponent(source: .semantic(SemanticMaskDefinition(
                    target: .person, generationVersion: generationVersion
                )))],
                adjustments: LocalAdjustments(exposure: 1)
            )
        ])
    }

    private func semanticRequest(
        source: ImageSource,
        document: EditDocument,
        maskResolution: MaskResolutionPolicy = .resolved,
        requestRevision: UInt64 = 0
    ) -> RenderRequest {
        RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 48, height: 32),
            quality: .preview, maskResolution: maskResolution, requestRevision: requestRevision
        )
    }

    func testIdenticalPreviewRequestsHitAndExposeCounters() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let request = request(source: source)
        let sourceKeyBefore = RenderSourceFingerprint(source)

        _ = try await engine.render(request)
        let sourceKeyAfter = RenderSourceFingerprint(source)
        _ = try await engine.render(request)

        XCTAssertEqual(sourceKeyBefore, sourceKeyAfter)
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 1)
        XCTAssertEqual(stats.preview.hits, 1)
        XCTAssertEqual(stats.preview.count, 1)
    }

    func testPreviewKeyIncludesDocumentSizeQualityAndWorkingSpace() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let document = EditDocument(adjustments: [.exposure(ev: 0.25)])

        _ = try await engine.render(request(source: source))
        _ = try await engine.render(request(source: source, document: document))
        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 48, height: 48)))
        _ = try await engine.render(request(source: source, quality: .interactive))
        _ = try await engine.render(request(source: source, space: .displayP3))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 5)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testPreviewKeyIncludesAllGrainParameters() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let neutral = request(source: source)
        let amount = request(source: source, document: EditDocument(effects: EffectsAdjustments(
            grain: GrainAdjustments(amount: 35)
        )))
        let size = request(source: source, document: EditDocument(effects: EffectsAdjustments(
            grain: GrainAdjustments(amount: 35, size: 80)
        )))
        let roughness = request(source: source, document: EditDocument(effects: EffectsAdjustments(
            grain: GrainAdjustments(amount: 35, size: 80, roughness: 15)
        )))

        _ = try await engine.render(neutral)
        _ = try await engine.render(amount)
        _ = try await engine.render(size)
        _ = try await engine.render(roughness)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 4)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testFullResolutionRequestsNeverEnterThePreviewCache() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let full = RenderRequest(source: source, document: EditDocument(), quality: .export, output: .raster)

        _ = try await engine.render(full)
        _ = try await engine.render(full)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.hits, 0)
        XCTAssertEqual(stats.preview.misses, 0)
        XCTAssertEqual(stats.preview.count, 0)
    }

    func testDevelopedSourceIsReusedAcrossDifferentEdits() async throws {
        let source = try makeSource()
        let engine = RenderEngine()

        _ = try await engine.render(request(source: source))
        _ = try await engine.render(request(
            source: source, document: EditDocument(adjustments: [.vibrance(amount: 0.3)])
        ))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1)
    }

    func testPartitionSurvivalTest() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let previewRequests = (0..<4).map { offset in
            request(
                source: source,
                targetSize: CGSize(width: 28 + offset * 4, height: 28 + offset * 4)
            )
        }

        for previewRequest in previewRequests {
            _ = await engine.makeCIImage(previewRequest)
        }
        let beforeThumbnails = await engine.cacheStatistics()

        for size in 8...57 {
            _ = await engine.makeCIImage(RenderRequest(
                source: source,
                document: EditDocument(),
                targetSize: CGSize(width: size, height: size),
                quality: .thumbnail,
                output: .raster
            ))
        }

        let afterThumbnails = await engine.cacheStatistics()
        XCTAssertEqual(afterThumbnails.developedSource.count, 4)
        XCTAssertEqual(afterThumbnails.developedSource.evictions,
                       beforeThumbnails.developedSource.evictions,
                       "thumbnail churn must not evict editor developed sources")

        for previewRequest in previewRequests {
            _ = await engine.makeCIImage(previewRequest)
        }
        let afterHits = await engine.cacheStatistics()
        XCTAssertEqual(afterHits.developedSource.hits - afterThumbnails.developedSource.hits, 4)
    }

    func testEvictionAccountingTest() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        _ = await engine.makeCIImage(request(source: source, targetSize: CGSize(width: 32, height: 32)))
        let before = await engine.cacheStatistics()

        for size in 8...57 {
            _ = await engine.makeCIImage(RenderRequest(
                source: source,
                document: EditDocument(),
                targetSize: CGSize(width: size, height: size),
                quality: .thumbnail,
                output: .raster
            ))
        }

        let after = await engine.cacheStatistics()
        XCTAssertEqual(after.developedSource.evictions, before.developedSource.evictions)
        XCTAssertGreaterThanOrEqual(after.thumbnailDevelopedSource.evictions, 49)
    }

    func testByteCapTest() async throws {
        let sourceURL = try Fixtures.writeGradientPNG(
            width: 512, height: 512, named: "thumbnail-byte-cap.png", in: tempDirectory
        )
        let source = ImageSource(url: sourceURL, nativeExtent: CGSize(width: 512, height: 512))
        let cap = 100_000
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            thumbnailDevelopedSourceMaxEntries: 256,
            thumbnailDevelopedSourceMaxCostBytes: cap
        ))

        for size in 100...149 {
            _ = await engine.makeCIImage(RenderRequest(
                source: source,
                document: EditDocument(),
                targetSize: CGSize(width: size, height: size),
                quality: .thumbnail,
                output: .raster
            ))
        }

        let stats = await engine.cacheStatistics()
        XCTAssertLessThanOrEqual(stats.thumbnailDevelopedSource.costBytes, cap)
    }

    func testMaskedPrefixHitTest() async throws {
        let source = try makeSource()
        let document = semanticDocument()
        let engine = RenderEngine(maskResolver: VersionedSemanticMaskResolver(
            sourceFingerprint: source.cacheFingerprint, providerVersion: "mask-v1",
            coverage: 1
        ))
        let renderRequest = semanticRequest(source: source, document: document)

        let first = await engine.makeCGImage(renderRequest)
        let second = await engine.makeCGImage(renderRequest)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1,
                       "a settled semantic mask must not force source re-development")
        XCTAssertGreaterThanOrEqual(stats.processingPrefix.hits, 1,
                                    "the post-local prefix should be reusable")
    }

    func testMaskVersionMissTest() async throws {
        let source = try makeSource()
        let firstDocument = semanticDocument(generationVersion: 1)
        let secondDocument = semanticDocument(generationVersion: 2)
        let engine = RenderEngine(maskResolver: VersionedSemanticMaskResolver(
            sourceFingerprint: source.cacheFingerprint, providerVersion: "mask-v1",
            coverage: 1
        ))

        let firstImage = await engine.makeCGImage(
            semanticRequest(source: source, document: firstDocument)
        )
        let secondImage = await engine.makeCGImage(
            semanticRequest(source: source, document: secondDocument)
        )
        let first = try XCTUnwrap(firstImage)
        let second = try XCTUnwrap(secondImage)

        XCTAssertNotEqual(try Pixels.bytes(of: first), try Pixels.bytes(of: second),
                          "a changed semantic definition must not reuse the old local prefix")
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.processingPrefix.misses, 2,
                       "each semantic version gets its own post-local entry")
    }

    func testMidResolutionPoisonTest() async throws {
        let source = try makeSource()
        let document = semanticDocument()
        let engine = RenderEngine(maskResolver: VersionedSemanticMaskResolver(
            sourceFingerprint: source.cacheFingerprint, providerVersion: "mask-v1",
            coverage: 1
        ))

        let deferredImage = await engine.makeCGImage(semanticRequest(
            source: source, document: document, maskResolution: .deferSemantic,
            requestRevision: 1
        ))
        let resolvedImage = await engine.makeCGImage(semanticRequest(
            source: source, document: document, requestRevision: 2
        ))
        let deferred = try XCTUnwrap(deferredImage)
        let resolved = try XCTUnwrap(resolvedImage)

        XCTAssertNotEqual(try Pixels.bytes(of: deferred), try Pixels.bytes(of: resolved),
                          "the resolved frame must not hit the deferred mask-less prefix")
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.count, 1,
                       "the deferred fast path must not materialize a settled-mask entry")
    }

    func testUnmaskedNoOpTest() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let first = request(source: source)
        let second = request(source: source)

        _ = try await engine.render(first)
        _ = try await engine.render(second)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.hits, 1,
                       "unmasked preview key behavior must remain unchanged")
    }

    func testTextureWarmupPrimesDevelopedSourceForTheNextPreview() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let request = request(source: source)

        _ = await engine.makeCIImage(request)
        let warmStats = await engine.cacheStatistics()
        _ = await engine.makeCIImage(request)
        let nextPreviewStats = await engine.cacheStatistics()

        XCTAssertEqual(warmStats.developedSource.misses, 1)
        XCTAssertEqual(nextPreviewStats.developedSource.hits, 1)
    }

    func testDownstreamOnlyEditsReuseTheCompletedProcessingPrefix() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let firstDocument = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 15))
        )
        let secondDocument = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 65))
        )

        _ = await engine.makeCGImage(request(source: source, document: firstDocument))
        _ = await engine.makeCGImage(request(source: source, document: secondDocument))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1)
        XCTAssertEqual(stats.processingPrefix.misses, 1)
        XCTAssertEqual(stats.processingPrefix.hits, 1,
                       "grain-only edits must not rebuild the completed pre-LUT prefix")
    }

    func testCachedPrefixPreservesDownstreamCropGrainAndLUTPixels() async throws {
        let source = try makeSource()
        let lut = TestImages.warmLUT()
        let engine = RenderEngine()
        let first = EditDocument(
            light: LightAdjustments(contrast: 25),
            effects: EffectsAdjustments(
                texture: 18,
                vignette: VignetteAdjustments(amount: 30),
                grain: GrainAdjustments(amount: 15)
            ),
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.15, width: 0.75, height: 0.7)),
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.35)
        )
        let second = EditDocument(
            light: LightAdjustments(contrast: 25),
            effects: EffectsAdjustments(
                texture: 18,
                vignette: VignetteAdjustments(amount: 30),
                grain: GrainAdjustments(amount: 70)
            ),
            crop: first.crop,
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.8)
        )
        func makeRequest(_ document: EditDocument) -> RenderRequest {
            RenderRequest(
                source: source, document: document, lut: lut,
                targetSize: CGSize(width: 64, height: 64), quality: .preview
            )
        }

        _ = await engine.makeCGImage(makeRequest(first))
        let cachedImage = await engine.makeCGImage(makeRequest(second))
        let cached = try XCTUnwrap(cachedImage)
        let freshEngine = RenderEngine()
        let freshImage = await freshEngine.makeCGImage(makeRequest(second))
        let fresh = try XCTUnwrap(freshImage)

        XCTAssertEqual(cached.width, fresh.width)
        XCTAssertEqual(cached.height, fresh.height)
        assertPixelsEqual(try Pixels.bytes(of: cached), try Pixels.bytes(of: fresh), tolerance: 2,
                          "a materialized prefix must preserve downstream LUT, crop, vignette, and grain")
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.hits, 1)
    }

    func testSharedPrefixTest() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let base = EditDocument(light: LightAdjustments(exposure: 0.35))
        let looks = [
            TestImages.identityLUT(name: "shared-identity"),
            TestImages.warmLUT(name: "shared-warm"),
            CubeLUT(
                cube: TestImages.toBlackCube(), size: 4, name: "shared-black"
            ),
        ]

        let images = await withTaskGroup(of: CGImage?.self, returning: [CGImage].self) { group in
            for look in looks {
                group.addTask {
                    await engine.makeLookPreviewCGImage(LookPreviewRequest(
                        source: source, document: base, look: look,
                        targetSize: CGSize(width: 48, height: 32)
                    ))
                }
            }
            var result: [CGImage] = []
            for await image in group {
                if let image { result.append(image) }
            }
            return result
        }

        XCTAssertEqual(images.count, looks.count)
        for lhs in 0..<images.count {
            for rhs in (lhs + 1)..<images.count {
                XCTAssertNotEqual(
                    try Pixels.bytes(of: images[lhs]), try Pixels.bytes(of: images[rhs]),
                    "each candidate LUT must produce a distinct thumbnail"
                )
            }
        }
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.thumbnailDevelopedSource.misses, 1)
        XCTAssertEqual(stats.thumbnailDevelopedSource.count, 1)
        XCTAssertEqual(stats.processingPrefix.misses, 1)
        XCTAssertEqual(stats.processingPrefix.count, 1)
        let work = await engine.workStatistics()
        XCTAssertEqual(work.processingPrefixMaterializations, 1)
    }

    func testNonLUTFallbackTest() async throws {
        let source = try makeSource()
        let look = TestImages.warmLUT(name: "fallback")
        let base = EditDocument()
        let candidate = EditDocument(
            light: LightAdjustments(exposure: 0.6),
            lut: LUTSettings(lutID: look.lutID, intensity: 1)
        )
        let request = LookPreviewRequest(
            source: source, baseDocument: base, candidateDocument: candidate,
            look: look, targetSize: CGSize(width: 48, height: 32)
        )
        XCTAssertFalse(request.isLUTOnlyChange)

        let optimizedEngine = RenderEngine()
        let fullEngine = RenderEngine()
        let optimizedImage = await optimizedEngine.makeLookPreviewCGImage(request)
        let fullImage = await fullEngine.makeCGImage(request.renderRequest)
        let optimizedEntry = try XCTUnwrap(optimizedImage)
        let fullEntry = try XCTUnwrap(fullImage)
        assertPixelsEqual(
            try Pixels.bytes(of: optimizedEntry), try Pixels.bytes(of: fullEntry), tolerance: 1,
            "a non-LUT candidate must match the full-build reference"
        )
    }

    func testUpstreamEditsInvalidateOnlyTheProcessingPrefix() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let first = EditDocument(light: LightAdjustments(exposure: 0.25))
        let second = EditDocument(light: LightAdjustments(exposure: 0.75))

        _ = await engine.makeCGImage(request(source: source, document: first))
        _ = await engine.makeCGImage(request(source: source, document: second))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1,
                       "a Light edit must reuse the unchanged developed source")
        XCTAssertEqual(stats.processingPrefix.misses, 2)
        XCTAssertEqual(stats.processingPrefix.hits, 0)
    }

    func testFullResolutionWorkNeverEntersTheProcessingPrefixCache() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let document = EditDocument(light: LightAdjustments(exposure: 0.5))
        let request = RenderRequest(
            source: source, document: document, quality: .export,
            output: .encoded(format: .png, quality: 1)
        )

        _ = try await engine.render(request)
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.count, 0)
        XCTAssertEqual(stats.processingPrefix.misses, 0)
    }

    func testProcessingPrefixEvictionHonorsItsIndependentBudget() async throws {
        let source = try makeSource()
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            previewMaxEntries: 12, previewMaxCostBytes: 10_000_000,
            developedSourceMaxEntries: 2, developedSourceMaxCostBytes: 10_000_000,
            processingPrefixMaxEntries: 1, processingPrefixMaxCostBytes: 10_000_000
        ))

        _ = await engine.makeCGImage(request(
            source: source, document: EditDocument(light: LightAdjustments(exposure: 0.1))
        ))
        _ = await engine.makeCGImage(request(
            source: source, document: EditDocument(light: LightAdjustments(exposure: 0.2))
        ))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.count, 1)
        XCTAssertGreaterThanOrEqual(stats.processingPrefix.evictions, 1)
    }

    /// A 3,000×2,000 RGBA-half prefix is 48 MB on the CPU and another 48 MB when consumed as a
    /// Metal texture. With a 64 MB working-set budget it must stay fused; rendering it repeatedly
    /// must not allocate and then reject the same intermediate on every downstream edit.
    func testAboveBudgetStandardPrefixStaysFusedWithoutMaterializationStorm() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "uncacheable-standard.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 3_000, height: 2_000))
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            previewMaxEntries: 12, previewMaxCostBytes: 10_000_000,
            developedSourceMaxEntries: 2, developedSourceMaxCostBytes: 256 * 1024 * 1024,
            processingPrefixMaxEntries: 1, processingPrefixMaxCostBytes: 64 * 1024 * 1024
        ))
        let request = { (grain: Double) in
            RenderRequest(
                source: source,
                document: EditDocument(
                    light: LightAdjustments(exposure: 0.25),
                    effects: EffectsAdjustments(grain: GrainAdjustments(amount: grain))
                ),
                targetSize: CGSize(width: 3_000, height: 2_000), quality: .preview
            )
        }

        let first = await engine.makeCGImage(request(10))
        let second = await engine.makeCGImage(request(40))
        let third = await engine.makeCGImage(request(80))
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)

        let stats = await engine.cacheStatistics()
        let work = await engine.workStatistics()
        XCTAssertEqual(stats.processingPrefix.count, 0)
        XCTAssertEqual(work.processingPrefixMaterializations, 0)
        XCTAssertEqual(work.materializationBudgetSkips, 3)
    }

    /// The RAW session has the same no-retain fallback. This is opt-in because Core Image needs a
    /// licensed camera file, but when one is available every edit must avoid the rejected half-float
    /// allocation while still returning a renderable frame.
    func testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let source = ImageSource(url: rawURL, nativeExtent: CGSize(width: 6_000, height: 4_000))
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            previewMaxEntries: 12, previewMaxCostBytes: 10_000_000,
            developedSourceMaxEntries: 2, developedSourceMaxCostBytes: 1_024 * 1_024,
            processingPrefixMaxEntries: 1, processingPrefixMaxCostBytes: 1_024 * 1_024
        ))
        let request = { (exposure: Double) in
            RenderRequest(
                source: source,
                document: EditDocument(rawDevelop: RAWDevelopSettings(exposure: exposure)),
                targetSize: CGSize(width: 3_000, height: 2_000), quality: .interactive
            )
        }

        let first = await engine.makeCGImage(request(0.0))
        let second = await engine.makeCGImage(request(0.5))
        let third = await engine.makeCGImage(request(1.0))
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)

        let work = await engine.workStatistics()
        XCTAssertEqual(work.rawOutputRequests, 3)
        XCTAssertEqual(work.materializationBudgetSkips, 3)
    }

    func testCacheCostAccountingCannotOverflow() {
        let cache = BoundedLRUCache<Int, Int>(maxEntries: 2, maxCostBytes: Int.max)
        cache.insert(1, for: 1, cost: Int.max)
        cache.insert(2, for: 2, cost: Int.max)

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.statistics.costBytes, Int.max)
    }

    func testEffectiveInteractiveScaleCannotReuseSettledDevelopedSource() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "above-cap-cache.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 3_000, height: 2_000))
        let engine = RenderEngine()
        let settled = request(source: source, targetSize: CGSize(width: 2_400, height: 1_600))
        let interactive = request(
            source: source, targetSize: CGSize(width: 2_400, height: 1_600), quality: .interactive
        )

        func extent(of image: CIImage?) -> CGSize {
            image?.extent.integral.size ?? .zero
        }

        let interactiveFirst = await engine.makeCIImage(interactive)
        let settledSecond = await engine.makeCIImage(settled)
        XCTAssertEqual(extent(of: interactiveFirst), CGSize(width: 1_500, height: 1_000))
        XCTAssertEqual(extent(of: settledSecond), CGSize(width: 2_400, height: 1_600))

        let reverseEngine = RenderEngine()
        let settledFirst = await reverseEngine.makeCIImage(settled)
        let interactiveSecond = await reverseEngine.makeCIImage(interactive)
        XCTAssertEqual(extent(of: settledFirst), CGSize(width: 2_400, height: 1_600))
        XCTAssertEqual(extent(of: interactiveSecond), CGSize(width: 1_500, height: 1_000))
    }

    func testInteractiveBudgetsWithDifferentEffectiveScalesDoNotCollide() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "budget-cache.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 3_000, height: 2_000))
        let engine = RenderEngine()
        let request = { (budget: Double) in
            RenderRequest(
                source: source, document: EditDocument(), targetSize: CGSize(width: 2_400, height: 1_600),
                quality: .interactive, frameBudgetMilliseconds: budget
            )
        }

        let short = await engine.makeCIImage(request(16.7))
        let generous = await engine.makeCIImage(request(33.4))
        XCTAssertEqual(short?.extent.integral.size, CGSize(width: 1_500, height: 1_000))
        XCTAssertEqual(generous?.extent.integral.size, CGSize(width: 2_122, height: 1_415))
    }

    func testSourceContentFingerprintSeparatesDataBackedImages() async throws {
        let firstURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "first.png", in: tempDirectory)
        let secondURL = try Fixtures.writeGradientPNG(width: 64, height: 96, named: "second.png", in: tempDirectory)
        let first = ImageSource(data: try Data(contentsOf: firstURL), nativeExtent: CGSize(width: 96, height: 64))
        let second = ImageSource(data: try Data(contentsOf: secondURL), nativeExtent: CGSize(width: 64, height: 96))
        let engine = RenderEngine()

        _ = try await engine.render(request(source: first))
        _ = try await engine.render(request(source: second))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 2)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testReplacingAURLBackedSourceCannotReuseItsPreview() async throws {
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "mutable.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let engine = RenderEngine()
        let request = request(source: source)
        let first = try await engine.render(request)

        let replacement = try Fixtures.makeCGImage(width: 96, height: 64, red: 0.1, green: 0.8, blue: 0.2)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, replacement, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let second = try await engine.render(request)
        XCTAssertNotEqual(first.data, second.data)
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.hits, 0)
        XCTAssertEqual(stats.preview.misses, 2)
    }

    func testExplicitInvalidationForcesTheNextPreviewToMiss() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let request = request(source: source)

        _ = try await engine.render(request)
        await engine.invalidateRenderCaches()
        _ = try await engine.render(request)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 2)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testConfiguredLimitEvictsLeastRecentlyUsedPreviewEntries() async throws {
        let source = try makeSource()
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            previewMaxEntries: 1, previewMaxCostBytes: 1_000_000,
            developedSourceMaxEntries: 2, developedSourceMaxCostBytes: 1_000_000
        ))

        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 24, height: 24)))
        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 32, height: 32)))
        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 24, height: 24)))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.count, 1)
        XCTAssertGreaterThanOrEqual(stats.preview.evictions, 1)
        XCTAssertEqual(stats.preview.misses, 3)
    }

    func testMemoryPressurePurgesRenderAndThumbnailCaches() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        _ = try await engine.render(request(source: source))
        _ = Thumbnails.generate(from: sourceURL(for: source))

        await engine.evictForMemoryPressure()
        let renderStats = await engine.cacheStatistics()
        XCTAssertEqual(renderStats.preview.count, 0)
        XCTAssertGreaterThanOrEqual(renderStats.preview.evictions, 1)
        XCTAssertEqual(Thumbnails.cacheStatistics().count, 0)
    }

    func testThumbnailRequestsHitAndFileChangesMiss() throws {
        Thumbnails.invalidateCache()
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "thumb-cache.png", in: tempDirectory)
        let before = Thumbnails.cacheStatistics()

        XCTAssertNotNil(Thumbnails.generate(from: url, maxPixelSize: 40))
        XCTAssertNotNil(Thumbnails.generate(from: url, maxPixelSize: 40))
        let afterHit = Thumbnails.cacheStatistics()
        XCTAssertEqual(afterHit.hits - before.hits, 1)

        // Replacing the file changes its resource fingerprint even though its path and dimensions
        // remain the same, so the old pixels cannot be served from the thumbnail cache.
        let replacement = try Fixtures.makeCGImage(width: 96, height: 64, red: 0.1, green: 0.8, blue: 0.2)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, replacement, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertNotNil(Thumbnails.generate(from: url, maxPixelSize: 40))
        let afterChange = Thumbnails.cacheStatistics()
        XCTAssertEqual(afterChange.misses - afterHit.misses, 1)
    }

    private func sourceURL(for source: ImageSource) -> URL {
        guard case .url(let url) = source.backing else { fatalError("test source must be URL-backed") }
        return url
    }
}

private struct VersionedSemanticMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    let providerVersion: String
    let coverage: Float

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let count = request.targetSize.width * request.targetSize.height
        let resolvedCoverage: Float = {
            guard case .semantic(let definition) = request.component.source else { return coverage }
            return definition.generationVersion == 1 ? coverage : coverage * 0.25
        }()
        let mask = try NormalizedMask(
            size: request.targetSize,
            values: Array(repeating: resolvedCoverage, count: count)
        )
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            providerVersion: providerVersion,
            descriptor: .raster(mask)
        )
    }
}
