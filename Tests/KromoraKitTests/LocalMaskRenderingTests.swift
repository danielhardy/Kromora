import CoreGraphics
import CoreImage
import ImageIO
import XCTest
@testable import KromoraKit

/// Step 2 render seam tests. These exercise the actor boundary and the one shared preview/export
/// graph rather than testing a second CPU implementation of local adjustments.
final class LocalMaskRenderingTests: TempDirectoryTestCase {
    private func source(width: Int = 8, height: Int = 4) throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: width, height: height, named: "local-mask-\(width)x\(height).png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: width, height: height))
    }

    private func layer(
        id: UUID = UUID(),
        amount: Double = 1,
        inverted: Bool = false,
        adjustments: LocalAdjustments = LocalAdjustments(exposure: 1),
        mode: MaskCombineMode = .replace
    ) -> LocalAdjustmentLayer {
        LocalAdjustmentLayer(
            id: id, isInverted: inverted, amount: amount,
            components: [MaskComponent(mode: mode, source: .linear(LinearGradientDefinition()))],
            adjustments: adjustments
        )
    }

    private func image(from result: RenderResult) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testPreviewSemanticMaskWorkingResolutionUsesFourMegapixelAndLongEdgeCaps() {
        let capped = SemanticMaskPreviewResolution.targetSize(
            for: PixelDimensions(width: 6_000, height: 4_000),
            cap: PixelDimensions(width: 2_560, height: 2_560)
        )

        XCTAssertEqual(capped, PixelDimensions(width: 2_449, height: 1_632))
        XCTAssertLessThanOrEqual(capped.width * capped.height, 4_000_000)
        XCTAssertLessThanOrEqual(max(capped.width, capped.height), 2_560)
        XCTAssertEqual(
            SemanticMaskPreviewResolution.targetSize(
                for: PixelDimensions(width: 1_600, height: 1_000),
                cap: PixelDimensions(width: 2_560, height: 2_560)
            ),
            PixelDimensions(width: 1_600, height: 1_000),
            "already-bounded previews must not be resampled"
        )
    }

    func testSemanticPreviewCapsWorkingResolutionButExportStaysFullResolution() async throws {
        let source = try source(width: 64, height: 32)
        let resolver = RecordingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        let engine = RenderEngine(
            maskResolver: resolver,
            semanticMaskPreviewCap: PixelDimensions(width: 32, height: 32)
        )
        let layer = LocalAdjustmentLayer(
            components: [MaskComponent(
                source: .semantic(SemanticMaskDefinition(target: .person))
            )],
            adjustments: LocalAdjustments(exposure: 1)
        )

        _ = try await engine.render(RenderRequest(
            source: source, document: EditDocument(localAdjustments: [layer]),
            targetSize: CGSize(width: 64, height: 32), quality: .preview, output: .raster
        ))
        _ = try await engine.render(RenderRequest(
            source: source, document: EditDocument(localAdjustments: [layer]),
            quality: .export, output: .raster
        ))

        let requests = await resolver.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].quality, .preview)
        XCTAssertEqual(requests[0].size, PixelDimensions(width: 32, height: 16))
        XCTAssertEqual(requests[1].quality, .export)
        XCTAssertEqual(requests[1].size, PixelDimensions(width: 64, height: 32))
    }

    func testCappedSemanticMaskMatchesFullResolutionForSoftAndHardEdges() async throws {
        let source = try source(width: 64, height: 32)
        let softDefinition = SemanticMaskDefinition(target: .person, edgeFeather: 0.5)
        let hardDefinition = SemanticMaskDefinition(target: .person, density: 1)

        let fixtures: [(String, SemanticMaskDefinition, PreviewMaskFixtureShape, Int)] = [
            ("soft", softDefinition, PreviewMaskFixtureShape.soft, 5),
            ("hard", hardDefinition, PreviewMaskFixtureShape.hard, 1),
        ]
        for (name, definition, shape, tolerance) in fixtures {
            let capped = RenderEngine(
                maskResolver: FixtureMaskResolver(
                    sourceFingerprint: source.cacheFingerprint, shape: shape
                ),
                semanticMaskPreviewCap: PixelDimensions(width: 32, height: 32)
            )
            let full = RenderEngine(
                maskResolver: FixtureMaskResolver(
                    sourceFingerprint: source.cacheFingerprint, shape: shape
                ),
                semanticMaskPreviewCap: nil
            )
            var layer = LocalAdjustmentLayer(
                components: [MaskComponent(source: .semantic(definition))]
            )
            if case .hard = shape { layer.isInverted = true }
            let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)
            let request = MaskOverlayRequest(
                source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
                targetSize: PixelDimensions(width: 64, height: 32), style: style
            )

            guard let cappedImage = await capped.makeMaskOverlayImage(request) else {
                return XCTFail("missing capped \(name) mask overlay")
            }
            guard let fullImage = await full.makeMaskOverlayImage(request) else {
                return XCTFail("missing full \(name) mask overlay")
            }
            assertPixelsEqual(
                try Pixels.bytes(of: cappedImage), try Pixels.bytes(of: fullImage),
                tolerance: tolerance,
                "\(name) semantic mask preview must remain visually stable when capped"
            )
        }
    }

    func testSemanticPreviewMaskWorkingResolutionBenchmark() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_SEMANTIC_MASK_PREVIEW_BENCHMARK"] == "1",
            "set KROMORA_SEMANTIC_MASK_PREVIEW_BENCHMARK=1 to run the 1:1 preview mask benchmark"
        )

        let source = try source()
        let seed = try NormalizedMask(
            size: PixelDimensions(width: 768, height: 512),
            values: (0..<768 * 512).map { Float($0 % 768) / 767 }
        )
        let layer = LocalAdjustmentLayer(
            components: [MaskComponent(
                source: .semantic(SemanticMaskDefinition(target: .person))
            )]
        )
        let request = MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 6_000, height: 4_000), style: MaskOverlayStyle(
                red: 1, green: 0, blue: 0
            )
        )
        let iterations = max(
            2, Int(ProcessInfo.processInfo.environment["KROMORA_SEMANTIC_MASK_PREVIEW_ITERATIONS"] ?? "3") ?? 3
        )

        func measure(cap: PixelDimensions?) async -> Double {
            let start = Date()
            for _ in 0..<iterations {
                let engine = RenderEngine(
                    maskResolver: SeedMaskResolver(
                        sourceFingerprint: source.cacheFingerprint, seed: seed
                    ), semanticMaskPreviewCap: cap
                )
                _ = await engine.makeMaskOverlayImage(request)
            }
            return Date().timeIntervalSince(start) * 1_000 / Double(iterations)
        }

        let cappedMilliseconds = await measure(
            cap: PixelDimensions(width: 2_560, height: 2_560)
        )
        let fullMilliseconds = await measure(cap: nil)
        let configuration = ProcessInfo.processInfo.environment[
            "KROMORA_SEMANTIC_MASK_PREVIEW_CONFIGURATION"
        ] ?? "unspecified"
        print(String(
            format: "SEMANTIC_MASK_PREVIEW_BENCHMARK configuration=%@ source=6000x4000 capped_4mp_ms=%.3f full_res_ms=%.3f speedup=%.2fx iterations=%d",
            configuration as NSString, cappedMilliseconds, fullMilliseconds,
            fullMilliseconds / cappedMilliseconds, iterations
        ))
    }

    func testSoftMaskBlendsLocalExposureAndPreviewMatchesFullRender() async throws {
        let source = try source()
        let values: [Float] = [0, 0.25, 0.5, 0.75,
                               0, 0.25, 0.5, 0.75,
                               0, 0.25, 0.5, 0.75,
                               0, 0.25, 0.5, 0.75]
        let resolver = TestMaskResolver(values: values, sourceFingerprint: source.cacheFingerprint)
        let document = EditDocument(localAdjustments: [layer()])
        let engine = RenderEngine(maskResolver: resolver)
        let preview = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        let export = try await engine.render(RenderRequest(
            source: source, document: document, quality: .export, output: .raster
        ))

        let previewImage = try image(from: preview)
        let exportImage = try image(from: export)
        XCTAssertEqual(previewImage.width, exportImage.width)
        XCTAssertEqual(previewImage.height, exportImage.height)
        assertPixelsEqual(try Pixels.bytes(of: previewImage), try Pixels.bytes(of: exportImage), tolerance: 1,
                          "preview and export must use the same local-mask graph")
        let base = try await engine.render(RenderRequest(
            source: source, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        let pixels = try Pixels.bytes(of: previewImage)
        let basePixels = try Pixels.bytes(of: image(from: base))
        XCTAssertGreaterThan(Int(pixels[2 * 4]), Int(basePixels[2 * 4]),
                             "a fractional soft-mask edge should blend the local exposure")
    }

    func testOrderedLayersFeedTheNextLayerAndGlobalSliderDoesNotReResolveMasks() async throws {
        let source = try source()
        let firstID = UUID()
        let secondID = UUID()
        let resolver = TestMaskResolver(values: Array(repeating: 1, count: 16),
                                        sourceFingerprint: source.cacheFingerprint)
        let first = layer(id: firstID, adjustments: LocalAdjustments(exposure: 1))
        let second = layer(id: secondID, adjustments: LocalAdjustments(exposure: -1))
        let engine = RenderEngine(maskResolver: resolver)
        _ = try await engine.render(RenderRequest(
            source: source, document: EditDocument(localAdjustments: [first, second]),
            targetSize: CGSize(width: 8, height: 4), quality: .preview
        ))
        _ = try await engine.render(RenderRequest(
            source: source, document: EditDocument(
                light: LightAdjustments(contrast: 25), localAdjustments: [first, second]
            ), targetSize: CGSize(width: 8, height: 4), quality: .preview
        ))
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.localMask.misses, 1, "identical component definitions share one payload")
        XCTAssertEqual(stats.localMask.hits, 3, "global slider edits must not invalidate mask payloads")
    }

    /// The payload is a reusable derived resource and has no request revision of its own. The
    /// engine's request revision must still reject a resolver result that arrives after a newer
    /// render for the same source has started.
    func testSupersededMaskResolutionIsRejectedBeforeItReachesTheRenderGraph() async throws {
        let source = try source()
        let document = EditDocument(localAdjustments: [layer()])
        let resolver = SupersedingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        let engine = RenderEngine(maskResolver: resolver)

        let first = Task { () -> LocalMaskResolutionError? in
            do {
                _ = try await engine.render(RenderRequest(
                    source: source, document: document, targetSize: CGSize(width: 8, height: 4),
                    quality: .preview, output: .raster, requestRevision: 1
                ))
                return nil
            } catch let error as LocalMaskResolutionError {
                return error
            } catch {
                return nil
            }
        }
        await resolver.waitForFirstCall()

        let second = Task { () -> Bool in
            do {
                _ = try await engine.render(RenderRequest(
                    source: source, document: document, targetSize: CGSize(width: 8, height: 4),
                    quality: .preview, output: .raster, requestRevision: 2
                ))
                return true
            } catch {
                return false
            }
        }
        let secondSucceeded = await second.value
        XCTAssertTrue(secondSucceeded)

        await resolver.releaseFirstCall()
        let firstError = await first.value
        XCTAssertEqual(firstError, .cancelled)
    }

    func testSuspendedRenderFenceSurvivesNavigationPastRenderLedgerCapacity() async throws {
        let source = try source()
        let resolver = SupersedingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        let engine = RenderEngine(maskResolver: resolver)
        let document = EditDocument(localAdjustments: [layer()])
        let first = Task {
            try await engine.render(RenderRequest(
                source: source, document: document, targetSize: CGSize(width: 8, height: 4),
                quality: .preview, output: .raster, requestRevision: 1
            ))
        }
        await resolver.waitForFirstCall()

        for index in 0..<70 {
            let visited = try self.source(width: 20 + index, height: 4)
            _ = try await engine.render(RenderRequest(
                source: visited, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
                quality: .preview, output: .raster, requestRevision: UInt64(index + 1)
            ))
        }

        _ = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster, requestRevision: 2
        ))
        await resolver.releaseFirstCall()
        do {
            _ = try await first.value
            XCTFail("the suspended revision 1 render must not publish after revision 2")
        } catch let error as LocalMaskResolutionError {
            XCTAssertEqual(error, .cancelled,
                           "the active fence survives eviction of the source's ledger entry")
        }
    }

    func testSuspendedMaskOverlayFenceSurvivesSourceEviction() async throws {
        let source = try source()
        let resolver = SupersedingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        let engine = RenderEngine(maskResolver: resolver)
        let semanticLayer = LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(
                SemanticMaskDefinition(target: .person)
            ))]
        )
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)
        let first = Task {
            await engine.makeMaskOverlayImage(MaskOverlayRequest(
                source: source, layers: [semanticLayer], selectedLayerID: semanticLayer.id,
                soloLayerID: nil, targetSize: PixelDimensions(width: 8, height: 4),
                style: style, requestRevision: 1
            ))
        }
        await resolver.waitForFirstCall()

        for index in 0..<18 {
            let visited = try self.source(width: 40 + index, height: 4)
            let visitedLayer = layer()
            _ = await engine.makeMaskOverlayImage(MaskOverlayRequest(
                source: visited, layers: [visitedLayer], selectedLayerID: visitedLayer.id,
                soloLayerID: nil, targetSize: PixelDimensions(width: 8, height: 4),
                style: style, requestRevision: UInt64(index + 1)
            ))
        }

        let replacement = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [semanticLayer], selectedLayerID: semanticLayer.id,
            soloLayerID: nil, targetSize: PixelDimensions(width: 8, height: 4),
            style: style, requestRevision: 2
        ))
        XCTAssertNotNil(replacement)
        await resolver.releaseFirstCall()
        let staleOverlay = await first.value
        XCTAssertNil(staleOverlay,
                     "the old mask overlay must not publish after its source fence was evicted")
    }

    func testNavigatingToAnotherMaskedSourceCancelsTheSupersededCoordinatorWaiter() async throws {
        let firstSource = try source(width: 8, height: 4)
        let secondSource = try source(width: 10, height: 4)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("navigation-masks"))
        let provider = ControllableStoredMaskProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let engine = RenderEngine(
            maskResolver: CoordinatorLocalMaskResolver(coordinator: coordinator)
        )
        let document = semanticDocument(target: .subject)

        let first = Task {
            try await engine.render(RenderRequest(
                source: firstSource, assetID: PhotoAnalysisCoordinator.assetID(for: firstSource),
                document: document, targetSize: firstSource.nativeExtent,
                quality: .preview, output: .raster, requestRevision: 1
            ))
        }
        let firstStarted = await provider.waitForStartedCount(1)
        XCTAssertTrue(firstStarted)

        let second = Task {
            try await engine.render(RenderRequest(
                source: secondSource, assetID: PhotoAnalysisCoordinator.assetID(for: secondSource),
                document: document, targetSize: secondSource.nativeExtent,
                quality: .preview, output: .raster, requestRevision: 2
            ))
        }
        let secondStarted = await provider.waitForStartedCount(2)
        XCTAssertTrue(secondStarted)
        let cancelledPromptly = await provider.waitForCancellationCount(1)
        await provider.release()

        XCTAssertTrue(cancelledPromptly, "navigation must cancel the old provider task")
        do {
            _ = try await first.value
            XCTFail("the superseded source render must be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await second.value
        let navigationCompletedCount = await provider.completedCount
        XCTAssertEqual(navigationCompletedCount, 1,
                       "only the currently visible source may finish mask work")
        await coordinator.shutdown()
    }

    func testMaskRecipeEditCancelsTheSupersededCoordinatorWaiter() async throws {
        let source = try source()
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("recipe-edit-masks"))
        let provider = ControllableStoredMaskProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let engine = RenderEngine(
            maskResolver: CoordinatorLocalMaskResolver(coordinator: coordinator)
        )
        let firstDocument = semanticDocument(target: .subject)
        let secondDocument = semanticDocument(target: .foreground)

        let first = Task {
            try await engine.render(RenderRequest(
                source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
                document: firstDocument, targetSize: source.nativeExtent,
                quality: .preview, output: .raster, requestRevision: 1
            ))
        }
        let firstStarted = await provider.waitForStartedCount(1)
        XCTAssertTrue(firstStarted)

        let second = Task {
            try await engine.render(RenderRequest(
                source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
                document: secondDocument, targetSize: source.nativeExtent,
                quality: .preview, output: .raster, requestRevision: 2
            ))
        }
        let secondStarted = await provider.waitForStartedCount(2)
        XCTAssertTrue(secondStarted)
        let cancelledPromptly = await provider.waitForCancellationCount(1)
        await provider.release()

        XCTAssertTrue(cancelledPromptly, "a changed semantic recipe must cancel its old waiter")
        do {
            _ = try await first.value
            XCTFail("the superseded mask recipe must be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await second.value
        let recipeCompletedCount = await provider.completedCount
        XCTAssertEqual(recipeCompletedCount, 1)
        await coordinator.shutdown()
    }

    func testMaskRequestStateEvictsOldestSourceFirst() async throws {
        let engine = RenderEngine()
        var sources: [ImageSource] = []
        for index in 0..<17 {
            sources.append(try source(width: 8 + index, height: 4))
        }

        for (index, source) in sources.enumerated() {
            _ = try await engine.render(RenderRequest(
                source: source,
                document: EditDocument(),
                targetSize: CGSize(width: 8, height: 4),
                quality: .preview,
                output: .raster,
                requestRevision: UInt64(index + 1)
            ))
        }

        let trackedSources = await engine.diagnosticsSnapshot.trackedMaskSourceKeys
        XCTAssertEqual(trackedSources.count, 16)
        XCTAssertEqual(trackedSources, sources.dropFirst().map(\.cacheFingerprint))
        XCTAssertFalse(trackedSources.contains(sources[0].cacheFingerprint))
    }

    /// KRMA-530: `latestRenderRequestRevisions` used to grow one entry per distinct source
    /// fingerprint visited in a session and was pruned only by a full cache invalidation. Navigate
    /// through many more sources than any single cap, and require every tracked-count diagnostic to
    /// stay bounded, so a long browsing session cannot leak one ledger entry per photo.
    func testLongSourceNavigationKeepsRevisionLedgerBounded() async throws {
        let engine = RenderEngine()
        let visitedSourceCount = 500

        for index in 0..<visitedSourceCount {
            // A distinct width per index gives each navigated photo its own cache fingerprint —
            // the ledger keys on identity, not on how many *calls* were made.
            let navigatedSource = try source(width: 8 + index, height: 4)
            _ = try await engine.render(RenderRequest(
                source: navigatedSource,
                document: EditDocument(),
                targetSize: CGSize(width: 8, height: 4),
                quality: .preview,
                output: .raster,
                requestRevision: UInt64(index + 1)
            ))

            let snapshot = await engine.diagnosticsSnapshot
            XCTAssertLessThanOrEqual(
                snapshot.trackedRenderSourceCount, 64,
                "render-revision ledger must stay bounded, not grow with navigation length"
            )
            XCTAssertLessThanOrEqual(
                snapshot.trackedMaskSourceKeys.count, 16,
                "mask-recipe ledger must stay bounded, not grow with navigation length"
            )
            XCTAssertLessThanOrEqual(
                snapshot.trackedMaskRequestCount, 64,
                "mask-request ledger must stay bounded, not grow with navigation length"
            )
        }

        let finalSnapshot = await engine.diagnosticsSnapshot
        XCTAssertGreaterThan(
            finalSnapshot.trackedRenderSourceCount, 0,
            "the most recently visited sources should still be tracked"
        )
    }

    func testInvalidateSourceCacheClearsMaskSourceOrder() async throws {
        let engine = RenderEngine()
        let firstSource = try source(width: 8, height: 4)

        _ = try await engine.render(RenderRequest(
            source: firstSource,
            document: EditDocument(),
            targetSize: CGSize(width: 8, height: 4),
            quality: .preview,
            output: .raster,
            requestRevision: 1
        ))
        let trackedAfterFirst = await engine.diagnosticsSnapshot.trackedMaskSourceKeys
        XCTAssertEqual(trackedAfterFirst, [firstSource.cacheFingerprint])

        await engine.invalidateSourceCache()
        let trackedAfterInvalidate = await engine.diagnosticsSnapshot.trackedMaskSourceKeys
        XCTAssertEqual(
            trackedAfterInvalidate, [],
            "invalidateSourceCache must clear mask source order along with the recipe table"
        )

        let secondSource = try source(width: 9, height: 4)
        _ = try await engine.render(RenderRequest(
            source: secondSource,
            document: EditDocument(),
            targetSize: CGSize(width: 9, height: 4),
            quality: .preview,
            output: .raster,
            requestRevision: 1
        ))
        let trackedAfterSecond = await engine.diagnosticsSnapshot.trackedMaskSourceKeys
        XCTAssertEqual(trackedAfterSecond, [secondSource.cacheFingerprint])
    }

    func testGlobalOnlyEditHitsTheResolvedSemanticMaskCacheWithoutCallingProviderAgain() async throws {
        let source = try source()
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("global-edit-masks"))
        let provider = ControllableStoredMaskProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let engine = RenderEngine(
            maskResolver: CoordinatorLocalMaskResolver(coordinator: coordinator)
        )
        let localAdjustments = semanticDocument(target: .subject).localAdjustments
        let firstDocument = EditDocument(localAdjustments: localAdjustments)
        let secondDocument = EditDocument(
            light: LightAdjustments(contrast: 30), localAdjustments: localAdjustments
        )

        let first = Task {
            try await engine.render(RenderRequest(
                source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
                document: firstDocument, targetSize: source.nativeExtent,
                quality: .preview, output: .raster, requestRevision: 1
            ))
        }
        let firstStarted = await provider.waitForStartedCount(1)
        XCTAssertTrue(firstStarted)
        await provider.release()
        _ = try await first.value
        let before = await engine.cacheStatistics()

        _ = try await engine.render(RenderRequest(
            source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
            document: secondDocument, targetSize: source.nativeExtent,
            quality: .preview, output: .raster, requestRevision: 2
        ))
        let after = await engine.cacheStatistics()

        let globalEditCallCount = await provider.callCount
        XCTAssertEqual(globalEditCallCount, 1,
                       "a global-only edit must not re-enter the Vision provider")
        XCTAssertGreaterThan(after.localMask.hits, before.localMask.hits,
                             "the unchanged semantic definition must hit the mask payload cache")
        await coordinator.shutdown()
    }

    private func semanticDocument(target: SemanticTarget) -> EditDocument {
        EditDocument(localAdjustments: [
            LocalAdjustmentLayer(
                components: [MaskComponent(
                    source: .semantic(SemanticMaskDefinition(target: target))
                )],
                adjustments: LocalAdjustments(exposure: 1)
            )
        ])
    }

    func testSemanticExportRejectsAnUnresolvedMaskWithAnActionableError() async throws {
        let source = try source()
        let semantic = LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 1)
        )
        let engine = RenderEngine()
        do {
            _ = try await engine.render(RenderRequest(
                source: source, document: EditDocument(localAdjustments: [semantic]),
                quality: .export, output: .raster
            ))
            XCTFail("unresolved semantic masks must not silently export")
        } catch let error as LocalMaskResolutionError {
            guard case .semanticMaskUnavailable(let target, let quality) = error else {
                return XCTFail("unexpected mask error: \(error)")
            }
            XCTAssertEqual(target, .subject)
            XCTAssertEqual(quality, .render)
        }
    }

    func testSemanticPreviewRejectsAnUnavailableMaskInsteadOfSilentlySkippingIt() async throws {
        let source = try source()
        let semantic = LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .foreground)))],
            adjustments: LocalAdjustments(exposure: 1)
        )

        do {
            _ = try await RenderEngine().render(RenderRequest(
                source: source, document: EditDocument(localAdjustments: [semantic]),
                targetSize: CGSize(width: 8, height: 4), quality: .preview, output: .raster
            ))
            XCTFail("an unavailable semantic mask must not render as an unmasked success")
        } catch let error as LocalMaskResolutionError {
            XCTAssertEqual(
                error,
                .semanticMaskUnavailable(target: .foreground, quality: .preview)
            )
        }
    }

    func testForegroundAndBackgroundSemanticMasksChangePixelsInPreviewAndExport() async throws {
        let source = try source()
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("semantic-masks"))
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store,
            maskProvider: SplitSemanticMaskProvider(store: store),
            stages: [:]
        )
        let engine = RenderEngine(maskResolver: CoordinatorLocalMaskResolver(coordinator: coordinator))
        let base = try await engine.render(RenderRequest(
            source: source, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))

        func semanticLayer(_ target: SemanticTarget, exposure: Double) -> LocalAdjustmentLayer {
            LocalAdjustmentLayer(
                components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: target)))],
                adjustments: LocalAdjustments(exposure: exposure)
            )
        }
        let foreground = try await engine.render(RenderRequest(
            source: source,
            document: EditDocument(localAdjustments: [semanticLayer(.foreground, exposure: 2)]),
            targetSize: CGSize(width: 8, height: 4), quality: .preview, output: .raster
        ))
        let background = try await engine.render(RenderRequest(
            source: source,
            document: EditDocument(localAdjustments: [semanticLayer(.background, exposure: -2)]),
            targetSize: CGSize(width: 8, height: 4), quality: .preview, output: .raster
        ))

        let basePixels = try Pixels.bytes(of: image(from: base))
        let foregroundPixels = try Pixels.bytes(of: image(from: foreground))
        let backgroundPixels = try Pixels.bytes(of: image(from: background))
        func difference(_ lhs: [UInt8], _ rhs: [UInt8], x: Int, y: Int) -> Int {
            let offset = (y * 8 + x) * 4
            return (0..<3).reduce(0) { $0 + abs(Int(lhs[offset + $1]) - Int(rhs[offset + $1])) }
        }

        XCTAssertGreaterThan(difference(foregroundPixels, basePixels, x: 1, y: 2), 10)
        XCTAssertLessThan(difference(foregroundPixels, basePixels, x: 6, y: 2), 3)
        XCTAssertLessThan(difference(backgroundPixels, basePixels, x: 1, y: 2), 3)
        XCTAssertGreaterThan(difference(backgroundPixels, basePixels, x: 6, y: 2), 10)

        let foregroundExport = try await engine.render(RenderRequest(
            source: source,
            document: EditDocument(localAdjustments: [semanticLayer(.foreground, exposure: 2)]),
            quality: .export, output: .raster
        ))
        assertPixelsEqual(
            foregroundPixels, try Pixels.bytes(of: image(from: foregroundExport)), tolerance: 1,
            "semantic foreground preview and export must share the local adjustment graph"
        )
    }

    func testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail() async throws {
        let source = try source(width: 16, height: 8)
        let semantic = LocalAdjustmentLayer(
            components: [MaskComponent(
                source: .semantic(SemanticMaskDefinition(target: .foreground))
            )],
            adjustments: LocalAdjustments(exposure: 2)
        )
        let document = EditDocument(localAdjustments: [semantic])
        let engine = RenderEngine(
            maskResolver: FixtureMaskResolver(sourceFingerprint: source.cacheFingerprint, shape: .hard)
        )

        let full = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 16, height: 8),
            quality: .preview, output: .raster
        ))
        let roi = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 16, height: 8),
            sourceROI: CGRect(x: 8, y: 0, width: 8, height: 8),
            quality: .preview, output: .raster
        ))

        let fullPixels = try Pixels.bytes(of: image(from: full))
        let roiPixels = try Pixels.bytes(of: image(from: roi))
        var expectedROI = [UInt8]()
        for y in 0..<8 {
            let start = (y * 16 + 8) * 4
            expectedROI.append(contentsOf: fullPixels[start..<(start + 8 * 4)])
        }
        assertPixelsEqual(
            roiPixels, expectedROI, tolerance: 1,
            "a zoomed semantic preview must preserve full-source mask coordinates"
        )

        let thumbnailImage = await engine.makeThumbnailCGImage(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 16, height: 8),
            quality: .thumbnail, output: .raster
        ))
        let thumbnail = try XCTUnwrap(thumbnailImage)
        assertPixelsEqual(
            try Pixels.bytes(of: thumbnail), fullPixels, tolerance: 1,
            "the primary fit preview and edited thumbnail must show equivalent masked pixels"
        )
    }

    func testBuiltInResolverRendersAnalyticLinearAndRadialMasks() async throws {
        let source = try source()
        let linear = layer(adjustments: LocalAdjustments(exposure: 1))
        let radial = LocalAdjustmentLayer(
            components: [MaskComponent(source: .radial(RadialGradientDefinition()))],
            adjustments: LocalAdjustments(saturation: 35)
        )
        let result = try await RenderEngine().render(RenderRequest(
            source: source, document: EditDocument(localAdjustments: [linear, radial]),
            targetSize: CGSize(width: 8, height: 4), quality: .preview, output: .raster
        ))
        let pixels = try Pixels.bytes(of: image(from: result))
        XCTAssertTrue(pixels.allSatisfy { $0 <= 255 }, "analytic mask output must stay finite")
    }

    func testBrushRasterCacheIsBoundedByBytesAndCanBeFlushed() throws {
        let renderer = LocalMaskRenderer(maxBrushStrokeCacheCostBytes: 8 * 8 * MemoryLayout<Float>.size)
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        func payload(at point: CGPoint) -> LocalMaskPayload {
            LocalMaskPayload(
                sourceFingerprint: "cache-test",
                targetSize: PixelDimensions(width: 8, height: 8),
                quality: .preview,
                descriptor: .brush(BrushMaskDefinition(strokes: [BrushStroke(
                    samples: [BrushSample(point: point)], radius: 0.1
                )]))
            )
        }

        _ = renderer.image(for: payload(at: CGPoint(x: 0.25, y: 0.5)), extent: extent, transform: .identity)
        XCTAssertEqual(renderer.diagnosticsSnapshot.cachedBrushStrokeCount, 1)
        XCTAssertLessThan(
            renderer.diagnosticsSnapshot.cachedBrushStrokeCostBytes,
            8 * 8 * MemoryLayout<Float>.size,
            "a small dab should cache only its touched tile"
        )

        _ = renderer.image(for: payload(at: CGPoint(x: 0.75, y: 0.5)), extent: extent, transform: .identity)
        XCTAssertGreaterThanOrEqual(renderer.diagnosticsSnapshot.cachedBrushStrokeCount, 1)
        XCTAssertLessThanOrEqual(
            renderer.diagnosticsSnapshot.cachedBrushStrokeCostBytes,
            8 * 8 * MemoryLayout<Float>.size)

        renderer.removeAllCachedBrushStrokes()
        XCTAssertEqual(renderer.diagnosticsSnapshot.cachedBrushStrokeCount, 0)
        XCTAssertEqual(renderer.diagnosticsSnapshot.cachedBrushStrokeCostBytes, 0)
    }

    func testBrushRasterUsesTouchedTileAndPreservesNonZeroExtentCoordinates() throws {
        let dimensions = PixelDimensions(width: 128, height: 64)
        let renderer = LocalMaskRenderer()
        let payload = LocalMaskPayload(
            sourceFingerprint: "roi-test", targetSize: dimensions, quality: .preview,
            descriptor: .brush(BrushMaskDefinition(strokes: [BrushStroke(
                samples: [
                    BrushSample(point: CGPoint(x: 0.22, y: 0.63)),
                    BrushSample(point: CGPoint(x: 0.28, y: 0.64)),
                ], radius: 0.03, feather: 0.7
            )]))
        )
        let origin = CGRect(x: 19, y: 7, width: 128, height: 64)
        guard let shifted = renderer.image(for: payload, extent: origin, transform: .identity),
              let zeroOrigin = renderer.image(
                  for: payload, extent: CGRect(origin: .zero, size: origin.size), transform: .identity
              ) else {
            return XCTFail("brush ROI did not render")
        }

        XCTAssertLessThan(
            renderer.diagnosticsSnapshot.cachedBrushStrokeCostBytes,
            dimensions.width * dimensions.height * MemoryLayout<Float>.size / 16,
            "a small stroke should not retain a full-frame raster"
        )
        assertPixelsEqual(
            try Pixels.bytes(of: shifted), try Pixels.bytes(of: zeroOrigin), tolerance: 1,
            "moving the Core Image extent origin must not move brush coverage"
        )
    }

    func testBrushRasterAccumulatesSeparatedStrokesWithoutFullFrameSmear() throws {
        let dimensions = PixelDimensions(width: 64, height: 32)
        let renderer = LocalMaskRenderer()
        let definition = BrushMaskDefinition(strokes: [
            BrushStroke(samples: [BrushSample(point: CGPoint(x: 0.2, y: 0.5))], radius: 0.08),
            BrushStroke(samples: [BrushSample(point: CGPoint(x: 0.8, y: 0.5))], radius: 0.08),
        ])
        let payload = LocalMaskPayload(
            sourceFingerprint: "separated-strokes", targetSize: dimensions, quality: .preview,
            descriptor: .brush(definition)
        )
        guard let image = renderer.image(
            for: payload, extent: CGRect(origin: .zero, size: CGSize(
                width: dimensions.width, height: dimensions.height)), transform: .identity
        ) else {
            return XCTFail("separated brush strokes did not render")
        }
        let pixels = try Pixels.bytes(of: image)
        XCTAssertEqual(pixels.count, dimensions.width * dimensions.height * 4)
        guard pixels.count >= dimensions.width * dimensions.height * 4 else { return }
        let alphaValues = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertGreaterThan(alphaValues.max() ?? 0, 200, "the brush image should contain coverage")
        if let firstOnly = renderer.image(
            for: LocalMaskPayload(
                sourceFingerprint: "single-stroke", targetSize: dimensions, quality: .preview,
                descriptor: .brush(BrushMaskDefinition(strokes: [definition.strokes[0]]))
            ), extent: CGRect(origin: .zero, size: CGSize(
                width: dimensions.width, height: dimensions.height)), transform: .identity
        ) {
            let firstPixels = try Pixels.bytes(of: firstOnly)
            let firstAlpha = stride(from: 3, to: firstPixels.count, by: 4).map { firstPixels[$0] }
            XCTAssertGreaterThan(firstAlpha.max() ?? 0, 200, "a single dab should contain coverage")
        }
        let alphaAt = { (x: Int, y: Int) in pixels[(y * dimensions.width + x) * 4 + 3] }
        XCTAssertGreaterThan(alphaAt(13, 16), 200, "the first dab should remain covered")
        XCTAssertGreaterThan(alphaAt(51, 16), 200, "the second dab should remain covered")
        XCTAssertLessThan(alphaAt(32, 16), 5, "separated dabs must not smear across the frame")
    }

    func testMaskOverlayUsesResolvedAlphaAndSoloDoesNotChangeExport() async throws {
        let source = try source()
        let linearID = UUID()
        let radialID = UUID()
        let linear = LocalAdjustmentLayer(
            components: [MaskComponent(id: linearID, source: .linear(LinearGradientDefinition()))]
        )
        let radial = LocalAdjustmentLayer(
            components: [MaskComponent(id: radialID, source: .radial(RadialGradientDefinition()))]
        )
        let resolver = OverlayMaskResolver(
            sourceFingerprint: source.cacheFingerprint,
            values: [linearID: 0.2, radialID: 0.8]
        )
        let engine = RenderEngine(maskResolver: resolver)
        let style = MaskOverlayStyle(inspection: .colorWash, red: 1, green: 0, blue: 0)

        guard let normal = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [linear, radial], selectedLayerID: linear.id,
            soloLayerID: nil, targetSize: PixelDimensions(width: 4, height: 2), style: style
        )) else { return XCTFail("linear mask overlay did not render") }
        guard let solo = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [linear, radial], selectedLayerID: linear.id,
            soloLayerID: radial.id, targetSize: PixelDimensions(width: 4, height: 2), style: style
        )) else { return XCTFail("solo mask overlay did not render") }
        let normalPixel = try Pixels.bytes(of: normal)
        let soloPixel = try Pixels.bytes(of: solo)
        XCTAssertLessThanOrEqual(abs(Int(normalPixel[3]) - 51), 2)
        XCTAssertLessThanOrEqual(abs(Int(soloPixel[3]) - 204), 2)
        XCTAssertGreaterThan(Int(soloPixel[3]), Int(normalPixel[3]))

        guard let grayscale = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [linear], selectedLayerID: linear.id,
            soloLayerID: nil, targetSize: PixelDimensions(width: 4, height: 2),
            style: MaskOverlayStyle(inspection: .grayscale, red: 1, green: 0, blue: 0)
        )) else { return XCTFail("grayscale mask overlay did not render") }
        let grayscalePixel = try Pixels.bytes(of: grayscale)
        XCTAssertEqual(grayscalePixel[0], grayscalePixel[1])
        XCTAssertEqual(grayscalePixel[1], grayscalePixel[2])
        XCTAssertEqual(grayscalePixel[3], 255)

        let before = try await engine.render(RenderRequest(
            source: source, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        guard await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [linear], selectedLayerID: linear.id,
            soloLayerID: nil, targetSize: PixelDimensions(width: 4, height: 2), style: style
        )) != nil else { return XCTFail("mask overlay did not render") }
        let after = try await engine.render(RenderRequest(
            source: source, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        assertPixelsEqual(
            try Pixels.bytes(of: image(from: before)), try Pixels.bytes(of: image(from: after)),
            "presentation-only mask inspection must not alter exported/rendered pixels"
        )
    }

    func testMaskOverlayInspectsSelectedComponentWithoutApplyingItsCombineMode() async throws {
        let source = try source()
        let baseID = UUID()
        let semanticID = UUID()
        let layer = LocalAdjustmentLayer(components: [
            MaskComponent(id: baseID, mode: .replace,
                          source: .linear(LinearGradientDefinition())),
            MaskComponent(id: semanticID, mode: .subtract,
                          source: .semantic(SemanticMaskDefinition(target: .foreground))),
        ])
        let engine = RenderEngine(maskResolver: OverlayMaskResolver(
            sourceFingerprint: source.cacheFingerprint,
            values: [baseID: 0.2, semanticID: 0.8]
        ))
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)

        guard let selected = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 4, height: 2), style: style,
            selectedComponentID: semanticID
        )) else { return XCTFail("selected component overlay did not render") }
        guard let solo = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 4, height: 2), style: style,
            selectedComponentID: baseID, soloComponentID: semanticID
        )) else { return XCTFail("solo component overlay did not render") }

        XCTAssertLessThanOrEqual(abs(Int(try Pixels.bytes(of: selected)[3]) - 204), 2)
        XCTAssertLessThanOrEqual(abs(Int(try Pixels.bytes(of: solo)[3]) - 204), 2)
    }

    func testStaleSelectedComponentFallsBackToUsableComponents() async throws {
        // LUMO-272: a selected component id can go stale while the layer selection survives
        // (undo, component delete, fresh draft ids during creation). The tooling draws via
        // its first-enabled fallback, so strict overlay filtering showed handles with no wash
        // and no banner. The overlay must fall back the same way; solo isolation stays strict.
        let source = try source()
        let draftComponent = MaskComponent(source: .linear(LinearGradientDefinition()))
        let draft = LocalAdjustmentLayer(components: [draftComponent])
        let engine = RenderEngine()
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)
        let targetSize = PixelDimensions(width: 4, height: 4)

        guard let wash = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [draft], selectedLayerID: draft.id, soloLayerID: nil,
            targetSize: targetSize, style: style, selectedComponentID: UUID()
        )) else {
            return XCTFail("stale selection must fall back to usable components")
        }
        // Default definition fades top-zero to bottom-full: corners must differ. (Pixel
        // centers sample inside the edge, so the top reads a small ramp value, not exact 0.)
        let bytes = try Pixels.bytes(of: wash)
        XCTAssertLessThan(Int(bytes[0]), 30)
        let bottomOffset = (targetSize.height - 1) * targetSize.width * 4
        XCTAssertGreaterThan(Int(bytes[bottomOffset]), 200)
    }

    func testOverlayResolveIsExemptFromRenderRevisionSupersession() async throws {
        // LUMO-275: previews note displayRevision (unbounded) into the same max-slot the
        // overlay's sourceRevision used — after the first preview renders, every overlay
        // resolve was cancelled forever, for every mask type. The overlay path is exempt
        // (revision 0 skips noting and always reads current); the render domain keeps its
        // guards, so a lagging nonzero overlay request is still superseded.
        let source = try source()
        let component = MaskComponent(source: .linear(LinearGradientDefinition()))
        let layer = LocalAdjustmentLayer(components: [component])
        let engine = RenderEngine()
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)
        let targetSize = PixelDimensions(width: 8, height: 4)
        var document = EditDocument()
        document.localAdjustments = [layer]
        _ = try await engine.render(RenderRequest(
            source: source, document: document,
            targetSize: CGSize(width: 8, height: 4),
            quality: .preview, requestRevision: 5
        ))

        func overlay(revision: UInt64) async -> CGImage? {
            await engine.makeMaskOverlayImage(MaskOverlayRequest(
                source: source, layers: [layer], selectedLayerID: layer.id,
                soloLayerID: nil, targetSize: targetSize, style: style,
                requestRevision: revision, selectedComponentID: component.id,
                soloComponentID: nil
            ))
        }
        let supersededWash = await overlay(revision: 1)
        XCTAssertNil(
            supersededWash,
            "a lagging nonzero revision stays superseded"
        )
        let exemptWash = await overlay(revision: 0)
        XCTAssertNotNil(
            exemptWash,
            "the exempt overlay revision must resolve despite noted renders"
        )
    }

    @MainActor
    func testProductionOverlayPathSurvivesPreviewRenders() async throws {
        // End-to-end through AppViewModel.renderMaskOverlay: the production overlay request
        // must resolve after main-preview renders noted higher revisions on the shared engine.
        let url = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: "exempt-overlay.png", in: tempDirectory)
        let engine = RenderEngine()
        let viewModel = makeAppViewModel(engine: engine, editStore: makeInMemoryEditStore())
        viewModel.openImage(url: url)
        try await waitForOverlayTest("the image to load") { viewModel.sourceImage != nil }
        let source = try XCTUnwrap(viewModel.maskingSource)
        var document = EditDocument()
        let component = MaskComponent(source: .linear(LinearGradientDefinition()))
        let layer = LocalAdjustmentLayer(components: [component])
        document.localAdjustments = [layer]
        _ = try await engine.render(RenderRequest(
            source: source, document: document,
            targetSize: CGSize(width: 64, height: 48),
            quality: .preview, requestRevision: 9
        ))

        let wash = await viewModel.renderMaskOverlay(
            layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 64, height: 48),
            style: MaskOverlayStyle(red: 1, green: 0, blue: 0),
            selectedComponentID: component.id, soloComponentID: nil
        )
        XCTAssertNotNil(wash, "production overlay must survive noted preview revisions")
    }

    @MainActor
    private func waitForOverlayTest(
        _ description: String, timeout: TimeInterval = 10,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testStaleSoloComponentStaysStrict() async throws {
        // Solo isolation is explicit: an unknown solo component resolves nothing.
        let source = try source()
        let draftComponent = MaskComponent(source: .linear(LinearGradientDefinition()))
        let draft = LocalAdjustmentLayer(components: [draftComponent])
        let engine = RenderEngine()
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)

        let wash = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [draft], selectedLayerID: draft.id,
            soloLayerID: draft.id,
            targetSize: PixelDimensions(width: 4, height: 4), style: style,
            selectedComponentID: nil, soloComponentID: UUID()
        ))
        XCTAssertNil(wash, "stale solo selection must stay strict")
    }

    func testRasterPayloadRowsRenderTopDownInOverlay() async throws {
        // Regression: rasterImage used to flip rows ("Core Image bitmap rows are bottom-up"),
        // which vertically mirrored every rasterized mask — semantic regions and brush strokes —
        // because `CIImage(bitmapData:)` memory row 0 already renders as the top output row
        // through the same RGBAf + blend + createCGImage chain the overlay uses.
        let source = try source()
        let componentID = UUID()
        let layer = LocalAdjustmentLayer(components: [MaskComponent(
            id: componentID, source: .semantic(SemanticMaskDefinition(target: .subject))
        )])
        // Only the top row of the mask has coverage.
        struct TopRowResolver: LocalMaskResolving {
            let sourceFingerprint: String
            func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
                let mask = try NormalizedMask(
                    size: request.targetSize,
                    values: (0..<request.targetSize.width * request.targetSize.height).map {
                        $0 < request.targetSize.width ? Float(1) : Float(0)
                    }
                )
                return LocalMaskPayload(
                    sourceFingerprint: sourceFingerprint,
                    definitionHash: RenderCacheHash.digest(request.component.source),
                    targetSize: request.targetSize,
                    quality: request.quality,
                    descriptor: .raster(mask)
                )
            }
        }
        let engine = RenderEngine(maskResolver: TopRowResolver(
            sourceFingerprint: source.cacheFingerprint))
        guard let overlay = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 8, height: 4),
            style: MaskOverlayStyle(inspection: .grayscale, red: 1, green: 0, blue: 0)
        )) else { return XCTFail("overlay did not render") }
        let pixels = try Pixels.bytes(of: overlay)
        // Grayscale inspection copies coverage into RGB and forces alpha opaque.
        let coverageAt = { (x: Int, y: Int) in pixels[(y * 8 + x) * 4] }
        XCTAssertEqual(coverageAt(0, 0), 255, "top mask row must render at the top output row")
        XCTAssertLessThan(coverageAt(0, 3), 5, "bottom output rows must stay uncovered")
    }

    func testRasterPayloadRGBA8MatchesPreviousRGBAfOverlayOnFeatheredFixture() async throws {
        let source = try source()
        let width = 8
        let height = 4
        let values = (0..<(width * height)).map { index in
            // A soft, non-binary coverage ramp exercises the quantization boundary throughout
            // the same alpha-mask blend used by the production overlay.
            Float(index) / Float(width * height - 1)
        }
        let component = MaskComponent(
            source: .semantic(SemanticMaskDefinition(target: .subject))
        )
        let layer = LocalAdjustmentLayer(components: [component])

        struct FeatheredResolver: LocalMaskResolving {
            let sourceFingerprint: String
            let values: [Float]
            let size: PixelDimensions

            func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
                let mask = try NormalizedMask(size: size, values: values)
                return LocalMaskPayload(
                    sourceFingerprint: sourceFingerprint,
                    definitionHash: RenderCacheHash.digest(request.component.source),
                    targetSize: request.targetSize,
                    quality: request.quality,
                    descriptor: .raster(mask)
                )
            }
        }

        let engine = RenderEngine(maskResolver: FeatheredResolver(
            sourceFingerprint: source.cacheFingerprint,
            values: values,
            size: PixelDimensions(width: width, height: height)
        ))
        let style = MaskOverlayStyle(red: 0.85, green: 0.2, blue: 0.05)
        guard let actual = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: width, height: height), style: style
        )) else { return XCTFail("feathered raster overlay did not render") }

        // Recreate the pre-LUMO-266 RGBAf bitmap path as the independent reference. The two
        // images then take the same blendWithAlphaMask and RGBA8 output path end-to-end.
        var floatPixels = [Float](repeating: 0, count: values.count * 4)
        for index in values.indices { floatPixels[index * 4 + 3] = values[index] }
        let floatData = floatPixels.withUnsafeBytes { Data($0) }
        let floatMask = CIImage(
            bitmapData: floatData,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: nil
        )
        let color = CIImage(color: CIColor(red: style.red, green: style.green,
                                            blue: style.blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = color
        blend.backgroundImage = clear
        blend.maskImage = floatMask
        let expected = try XCTUnwrap(Pixels.context.createCGImage(
            try XCTUnwrap(blend.outputImage), from: floatMask.extent,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ))

        assertPixelsEqual(
            try Pixels.bytes(of: actual), try Pixels.bytes(of: expected), tolerance: 1,
            "RGBA8 alpha masks must match the previous RGBAf overlay path"
        )
    }

    func testLinearColorWashUsesRenderedSmoothstepFalloffInsteadOfAFlatTint() async throws {
        let source = try source()
        let definition = LinearGradientDefinition(
            zeroStrengthPoint: CGPoint(x: 0.5, y: 0.2),
            fullStrengthPoint: CGPoint(x: 0.5, y: 0.8))
        let layer = LocalAdjustmentLayer(components: [MaskComponent(
            source: .linear(definition)
        )])
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)

        guard let overlay = await RenderEngine().makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 1, height: 9), style: style
        )) else { return XCTFail("linear color-wash overlay did not render") }

        let pixels = try Pixels.bytes(of: overlay)
        let alphaAtRow = { (row: Int) in pixels[row * 4 + 3] }
        let alpha = (0..<9).map(alphaAtRow)
        XCTAssertEqual(alpha.first, 0, "the zero-strength edge must remain clear")
        XCTAssertEqual(alpha.last, 255, "the full-strength edge must be fully washed")
        XCTAssertGreaterThan(alpha[4], alpha[2], "the wash must increase through the transition")
        XCTAssertGreaterThan(alpha[6], alpha[4], "the wash must continue toward full strength")
        XCTAssertGreaterThan(alpha[4], 40, "the transition midpoint must be visibly washed")
        XCTAssertLessThan(alpha[4], 215, "the transition midpoint must not be a flat full tint")
    }

    func testMaskOverlayPreservesPartialCoverageInColorAndGrayscaleModes() async throws {
        let source = try source()
        let componentID = UUID()
        let layer = LocalAdjustmentLayer(components: [MaskComponent(
            id: componentID, source: .linear(LinearGradientDefinition())
        )])

        struct CoverageResolver: LocalMaskResolving {
            let sourceFingerprint: String

            func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
                let values: [Float] = [0, 0.5, 1]
                let mask = try NormalizedMask(
                    size: request.targetSize,
                    values: (0..<request.targetSize.width * request.targetSize.height).map {
                        values[$0 % values.count]
                    }
                )
                return LocalMaskPayload(
                    sourceFingerprint: sourceFingerprint,
                    definitionHash: RenderCacheHash.digest(request.component.source),
                    targetSize: request.targetSize,
                    quality: request.quality,
                    descriptor: .raster(mask)
                )
            }
        }

        let engine = RenderEngine(maskResolver: CoverageResolver(
            sourceFingerprint: source.cacheFingerprint))
        let colorRequest = MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 3, height: 1),
            style: MaskOverlayStyle(red: 1, green: 0, blue: 0)
        )
        guard let color = await engine.makeMaskOverlayImage(colorRequest) else {
            return XCTFail("color coverage overlay did not render")
        }
        let colorPixels = try Pixels.bytes(of: color)
        XCTAssertEqual(colorPixels[3], 0)
        XCTAssertLessThanOrEqual(abs(Int(colorPixels[7]) - 128), 2)
        XCTAssertEqual(colorPixels[11], 255)

        guard let grayscale = await engine.makeMaskOverlayImage(
            MaskOverlayRequest(
                source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
                targetSize: PixelDimensions(width: 3, height: 1),
                style: MaskOverlayStyle(inspection: .grayscale, red: 1, green: 0, blue: 0)
            )
        ) else { return XCTFail("grayscale coverage overlay did not render") }
        let grayscalePixels = try Pixels.bytes(of: grayscale)
        XCTAssertEqual(grayscalePixels[0], grayscalePixels[1])
        XCTAssertEqual(grayscalePixels[1], grayscalePixels[2])
        XCTAssertEqual(grayscalePixels[3], 255)
        XCTAssertGreaterThan(grayscalePixels[4], grayscalePixels[0])
        XCTAssertLessThan(grayscalePixels[4], grayscalePixels[8])
        XCTAssertEqual(grayscalePixels[8], 255)
    }

    func testMaskOverlayUsesTheSharedResolverForBrushAndSemanticLayers() async throws {
        let source = try source()
        let brush = LocalAdjustmentLayer(components: [MaskComponent(source: .brush(
            BrushMaskDefinition(strokes: [BrushStroke(
                samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))], radius: 0.4
            )])
        ))])
        let linear = LocalAdjustmentLayer(
            components: [MaskComponent(source: .linear(LinearGradientDefinition()))]
        )
        let radial = LocalAdjustmentLayer(
            components: [MaskComponent(source: .radial(RadialGradientDefinition()))]
        )
        let semantic = LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))]
        )
        let engine = RenderEngine(maskResolver: RepresentativeOverlayResolver(
            sourceFingerprint: source.cacheFingerprint
        ))
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)

        for layer in [brush, linear, radial, semantic] {
            guard let image = await engine.makeMaskOverlayImage(MaskOverlayRequest(
                source: source, layers: [layer], selectedLayerID: layer.id,
                soloLayerID: nil, targetSize: PixelDimensions(width: 8, height: 4), style: style
            )) else {
                return XCTFail("overlay did not render (layer.maskingTypeTitle)")
            }
            XCTAssertEqual(image.width, 8)
            XCTAssertEqual(image.height, 4)
        }
    }

    func testGPUCompositionPreservesOrderedOperationsInversionAndDisabledComponents() async throws {
        let source = try source()
        let firstID = UUID()
        let subtractID = UUID()
        let intersectID = UUID()
        let disabledID = UUID()
        let layer = LocalAdjustmentLayer(
            components: [
                MaskComponent(id: firstID, mode: .replace,
                              source: .linear(LinearGradientDefinition())),
                MaskComponent(id: subtractID, mode: .subtract,
                              source: .brush(BrushMaskDefinition(strokes: [BrushStroke()]))),
                MaskComponent(id: intersectID, mode: .intersect,
                              source: .radial(RadialGradientDefinition())),
                MaskComponent(id: disabledID, mode: .add, isEnabled: false,
                              source: .linear(LinearGradientDefinition())),
            ])
        let resolver = OverlayMaskResolver(
            sourceFingerprint: source.cacheFingerprint,
            values: [firstID: 0.8, subtractID: 0.25, intersectID: 0.9, disabledID: 1])
        let engine = RenderEngine(maskResolver: resolver)
        let style = MaskOverlayStyle(red: 1, green: 0, blue: 0)

        guard let normal = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 4, height: 2), style: style
        )) else { return XCTFail("composed mask did not render") }
        let normalPixel = try Pixels.bytes(of: normal)
        XCTAssertLessThanOrEqual(abs(Int(normalPixel[3]) - 153), 2)

        var inverted = layer
        inverted.isInverted = true
        guard let invertedImage = await engine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source, layers: [inverted], selectedLayerID: inverted.id, soloLayerID: nil,
            targetSize: PixelDimensions(width: 4, height: 2), style: style
        )) else { return XCTFail("inverted composed mask did not render") }
        let invertedPixel = try Pixels.bytes(of: invertedImage)
        XCTAssertLessThanOrEqual(abs(Int(invertedPixel[3]) - 102), 2)
    }

    // MARK: - Two-phase preview (deferred semantic masks)

    /// The base frame of a masked preview must be exactly "everything that does not need Vision":
    /// procedural and brush layers drawn, semantic layers left for the refinement.
    func testDeferredSemanticPassResolvesOnlyNonSemanticComponents() async throws {
        let source = try source(width: 16, height: 8)
        let resolver = ComponentRecordingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        let engine = RenderEngine(maskResolver: resolver)
        let linear = MaskSource.linear(LinearGradientDefinition())
        let semantic = MaskSource.semantic(SemanticMaskDefinition(target: .person))
        let document = EditDocument(localAdjustments: [
            LocalAdjustmentLayer(
                components: [MaskComponent(source: linear)],
                adjustments: LocalAdjustments(exposure: 1)
            ),
            LocalAdjustmentLayer(
                components: [MaskComponent(source: semantic)],
                adjustments: LocalAdjustments(exposure: -1)
            ),
        ])
        let base = try await engine.render(request(
            source: source, document: document, maskResolution: .deferSemantic
        ))
        var seen = await resolver.resolved
        XCTAssertEqual(seen, [linear],
                       "the base frame must not ask the semantic resolver for anything")

        let refined = try await engine.render(request(source: source, document: document))
        seen = await resolver.resolved
        XCTAssertEqual(seen, [linear, semantic],
                       "the refinement resolves the semantic component that the base frame skipped")
        assertPixelsDiffer(
            try Pixels.bytes(of: image(from: base)), try Pixels.bytes(of: image(from: refined)),
            "the refinement must actually add the semantic layer's look"
        )
    }

    /// A layer whose semantic component *removes* coverage cannot be drawn from its remaining
    /// components: doing so would apply the look to pixels the resolved mask subtracts, which reads
    /// as a flash rather than a refinement. Such a layer is absent from the base frame entirely.
    func testDeferredSemanticPassOmitsLayersThatWouldOverApply() async throws {
        let source = try source(width: 16, height: 8)
        let resolver = ComponentRecordingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        let engine = RenderEngine(maskResolver: resolver)
        let document = EditDocument(localAdjustments: [
            LocalAdjustmentLayer(
                components: [
                    MaskComponent(mode: .replace, source: .linear(LinearGradientDefinition())),
                    MaskComponent(
                        mode: .subtract, source: .semantic(SemanticMaskDefinition(target: .person))
                    ),
                ],
                adjustments: LocalAdjustments(exposure: 1)
            )
        ])
        let base = try await engine.render(request(
            source: source, document: document, maskResolution: .deferSemantic
        ))
        let seen = await resolver.resolved
        XCTAssertTrue(seen.isEmpty, "a layer deferred whole resolves none of its components")

        let unedited = try await engine.render(request(source: source, document: EditDocument()))
        assertPixelsEqual(
            try Pixels.bytes(of: image(from: base)), try Pixels.bytes(of: image(from: unedited)),
            "the base frame must show the photo without the deferred layer"
        )
        let refined = try await engine.render(request(source: source, document: document))
        assertPixelsDiffer(
            try Pixels.bytes(of: image(from: base)), try Pixels.bytes(of: image(from: refined)),
            "the refinement must land the deferred layer"
        )
    }

    /// Export and full-resolution renders never take the progressive path, so their pixels do not
    /// depend on which components happened to be resolved when the frame was built.
    func testExportIgnoresTheDeferredSemanticPolicy() async throws {
        let source = try source(width: 16, height: 8)
        let document = EditDocument(localAdjustments: [
            LocalAdjustmentLayer(
                components: [MaskComponent(
                    source: .semantic(SemanticMaskDefinition(target: .person))
                )],
                adjustments: LocalAdjustments(exposure: 1)
            )
        ])
        let engine = RenderEngine(
            maskResolver: ComponentRecordingMaskResolver(sourceFingerprint: source.cacheFingerprint)
        )
        XCTAssertEqual(
            RenderRequest(source: source, document: document, quality: .export).maskResolution,
            .resolved, "an export request defaults to the exact path"
        )
        let exported = try await engine.render(RenderRequest(
            source: source, document: document, quality: .export, output: .raster
        ))
        let full = try await engine.render(RenderRequest(
            source: source, document: document, quality: .fullResolution, output: .raster
        ))
        assertPixelsEqual(
            try Pixels.bytes(of: image(from: exported)), try Pixels.bytes(of: image(from: full)),
            "export and full-resolution renders must agree with the resolved graph"
        )
    }

    /// The subset rule is the whole safety argument for the base frame, so it is pinned directly
    /// rather than only through rendered pixels.
    func testDeferredPreviewAdmissionFollowsTheSubsetRule() {
        let semantic = MaskSource.semantic(SemanticMaskDefinition(target: .subject))
        let linear = MaskSource.linear(LinearGradientDefinition())
        func layer(
            _ components: [MaskComponent], inverted: Bool = false
        ) -> LocalAdjustmentLayer {
            LocalAdjustmentLayer(isInverted: inverted, components: components)
        }

        XCTAssertTrue(layer([MaskComponent(source: linear)]).allowsDeferredSemanticPreview,
                      "a layer without semantic components resolves fully in the base frame")
        XCTAssertTrue(
            layer([MaskComponent(mode: .replace, source: semantic)]).allowsDeferredSemanticPreview,
            "a semantic-only layer contributes nothing to the base frame, which is a subset"
        )
        XCTAssertTrue(
            layer([
                MaskComponent(mode: .replace, source: semantic),
                MaskComponent(mode: .add, source: linear),
            ]).allowsDeferredSemanticPreview,
            "dropping a leading replace leaves the rest composing against the empty mask"
        )
        XCTAssertFalse(
            layer([
                MaskComponent(mode: .replace, source: linear),
                MaskComponent(mode: .subtract, source: semantic),
            ]).allowsDeferredSemanticPreview,
            "a subtracting semantic component would over-apply while it is unresolved"
        )
        XCTAssertFalse(
            layer([
                MaskComponent(mode: .replace, source: linear),
                MaskComponent(mode: .intersect, source: semantic),
            ]).allowsDeferredSemanticPreview,
            "an intersecting semantic component would over-apply while it is unresolved"
        )
        XCTAssertFalse(
            layer([
                MaskComponent(mode: .replace, source: linear),
                MaskComponent(mode: .replace, source: semantic),
            ]).allowsDeferredSemanticPreview,
            "a later replace discards the components the base frame would have drawn"
        )
        XCTAssertFalse(
            layer([
                MaskComponent(mode: .replace, source: semantic),
                MaskComponent(mode: .add, source: linear),
            ], inverted: true).allowsDeferredSemanticPreview,
            "layer inversion turns the base frame's subset back into a superset"
        )
        var disabledSemantic = MaskComponent(mode: .subtract, source: semantic)
        disabledSemantic.isEnabled = false
        XCTAssertTrue(
            layer([MaskComponent(source: linear), disabledSemantic]).allowsDeferredSemanticPreview,
            "an unusable component takes part in neither pass"
        )
    }

    private func request(
        source: ImageSource,
        document: EditDocument,
        maskResolution: MaskResolutionPolicy = .resolved
    ) -> RenderRequest {
        RenderRequest(
            source: source, document: document,
            targetSize: source.nativeExtent, quality: .preview, output: .raster,
            maskResolution: maskResolution
        )
    }
}

/// Records which component definitions each pass asked for. Its masks are flat, so the rendered
/// pixels reflect exactly which components took part; semantic masks return partial coverage so a
/// composition that subtracts one does not collapse to an empty mask.
private actor ComponentRecordingMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    private(set) var resolved: [MaskSource] = []

    init(sourceFingerprint: String) {
        self.sourceFingerprint = sourceFingerprint
    }

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        resolved.append(request.component.source)
        let count = max(0, request.targetSize.width * request.targetSize.height)
        let coverage: Float = request.component.source.semanticDefinition == nil ? 1 : 0.5
        let mask = try NormalizedMask(
            size: request.targetSize, values: Array(repeating: coverage, count: count)
        )
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

private struct TestMaskResolver: LocalMaskResolving {
    let values: [Float]
    let sourceFingerprint: String

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let count = max(0, request.targetSize.width * request.targetSize.height)
        let payloadValues = values.isEmpty ? Array(repeating: Float(0), count: count) :
            (0..<count).map { values[$0 % values.count] }
        let mask = try NormalizedMask(size: request.targetSize, values: payloadValues)
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

private actor RecordingMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    private(set) var requests: [(quality: RenderQuality, size: PixelDimensions)] = []

    init(sourceFingerprint: String) {
        self.sourceFingerprint = sourceFingerprint
    }

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        requests.append((request.quality, request.targetSize))
        let count = request.targetSize.width * request.targetSize.height
        let mask = try NormalizedMask(
            size: request.targetSize, values: Array(repeating: Float(1), count: count)
        )
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

private enum PreviewMaskFixtureShape: Sendable {
    case soft
    case hard
}

private struct FixtureMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    let shape: PreviewMaskFixtureShape

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let width = request.targetSize.width
        let height = request.targetSize.height
        let values = (0..<height).flatMap { _ in
            (0..<width).map { x in
                switch shape {
                case .soft:
                    return Float(Double(x) / Double(max(width - 1, 1)))
                case .hard:
                    return x < width / 2 ? 1 : 0
                }
            }
        }
        let mask = try NormalizedMask(size: request.targetSize, values: values)
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

private struct SeedMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    let seed: NormalizedMask

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let mask = try MaskOperations.resized(seed, to: request.targetSize)
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

/// A deterministic stand-in for Vision that remains suspended until released and records whether
/// cancellation reached the provider task. Yield-based gates make the assertions about task
/// outcomes and counts rather than elapsed wall-clock time.
private actor ControllableStoredMaskProvider: SemanticMaskProviding {
    private let store: MaskStore
    private var isReleased = false
    private(set) var callCount = 0
    private(set) var cancellationCount = 0
    private(set) var completedCount = 0

    init(store: MaskStore) {
        self.store = store
    }

    func mask(
        for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality
    ) async throws -> RegionMask {
        callCount += 1
        do {
            while !isReleased {
                try Task.checkCancellation()
                await Task.yield()
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            cancellationCount += 1
            throw CancellationError()
        }

        let pixels = try NormalizedMask(
            size: image.dimensions,
            values: Array(repeating: Float(1), count: image.dimensions.width * image.dimensions.height)
        )
        let key = MaskCacheKey(
            assetID: image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source),
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind, quality: quality, providerVersion: "controlled-test"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        completedCount += 1
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality, reference: reference, confidence: 1, coverage: 1
        )
    }

    func release() {
        isReleased = true
    }

    func waitForStartedCount(_ expected: Int) async -> Bool {
        for _ in 0..<100_000 {
            if callCount >= expected { return true }
            await Task.yield()
        }
        return callCount >= expected
    }

    func waitForCancellationCount(_ expected: Int) async -> Bool {
        for _ in 0..<100_000 {
            if cancellationCount >= expected { return true }
            await Task.yield()
        }
        return cancellationCount >= expected
    }
}

private actor SupersedingMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    private var callCount = 0
    private var firstCallSeen = false
    private var firstCallWaiter: CheckedContinuation<Void, Never>?
    private var firstCallRelease: CheckedContinuation<Void, Never>?

    init(sourceFingerprint: String) {
        self.sourceFingerprint = sourceFingerprint
    }

    func waitForFirstCall() async {
        guard !firstCallSeen else { return }
        await withCheckedContinuation { continuation in
            firstCallWaiter = continuation
        }
    }

    func releaseFirstCall() {
        firstCallRelease?.resume()
        firstCallRelease = nil
    }

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        callCount += 1
        if callCount == 1 {
            firstCallSeen = true
            firstCallWaiter?.resume()
            firstCallWaiter = nil
            await withCheckedContinuation { continuation in
                firstCallRelease = continuation
            }
        }

        let count = request.targetSize.width * request.targetSize.height
        let mask = try NormalizedMask(
            size: request.targetSize, values: Array(repeating: Float(1), count: count)
        )
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

private struct OverlayMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    let values: [UUID: Float]

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let value = values[request.component.id] ?? 0
        let count = request.targetSize.width * request.targetSize.height
        let mask = try NormalizedMask(
            size: request.targetSize, values: Array(repeating: value, count: count)
        )
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

private struct RepresentativeOverlayResolver: LocalMaskResolving {
    let sourceFingerprint: String

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        if case .semantic = request.component.source {
            let count = request.targetSize.width * request.targetSize.height
            let mask = try NormalizedMask(
                size: request.targetSize, values: Array(repeating: 0.6, count: count)
            )
            return LocalMaskPayload(
                sourceFingerprint: sourceFingerprint,
                definitionHash: RenderCacheHash.digest(request.component.source),
                targetSize: request.targetSize,
                quality: request.quality,
                descriptor: .raster(mask)
            )
        }
        return try await DefaultLocalMaskResolver().resolve(request)
    }
}

private actor SplitSemanticMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard kind == .foreground || kind == .subject || kind == .person else {
            throw VisionSemanticMaskError.unsupported(kind)
        }
        let size = image.dimensions
        let values = (0..<size.height).flatMap { _ in
            (0..<size.width).map { $0 < size.width / 2 ? Float(1) : Float(0) }
        }
        let pixels = try NormalizedMask(size: size, values: values)
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "split-test-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: .foreground,
            bounds: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: pixels.coverage
        )
    }
}
