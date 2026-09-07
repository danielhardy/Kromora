import CoreGraphics
import ImageIO
import XCTest
@testable import LumoKit

/// Step 2 render seam tests. These exercise the actor boundary and the one shared preview/export
/// graph rather than testing a second CPU implementation of local adjustments.
final class LocalMaskRenderingTests: TempDirectoryTestCase {
    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 8, height: 4, named: "local-mask.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 8, height: 4))
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
        XCTAssertEqual(renderer.cachedBrushStrokeCount, 1)
        XCTAssertEqual(renderer.cachedBrushStrokeCostBytes, 8 * 8 * MemoryLayout<Float>.size)

        _ = renderer.image(for: payload(at: CGPoint(x: 0.75, y: 0.5)), extent: extent, transform: .identity)
        XCTAssertEqual(renderer.cachedBrushStrokeCount, 1)
        XCTAssertLessThanOrEqual(
            renderer.cachedBrushStrokeCostBytes, 8 * 8 * MemoryLayout<Float>.size)

        renderer.removeAllCachedBrushStrokes()
        XCTAssertEqual(renderer.cachedBrushStrokeCount, 0)
        XCTAssertEqual(renderer.cachedBrushStrokeCostBytes, 0)
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
