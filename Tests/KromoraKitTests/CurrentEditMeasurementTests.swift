import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

/// Focused coverage for KRMA-343: the current edit — not the source — is measured, through the
/// real pipeline seam, with pixel-correlated facts and graceful degradation.
final class CurrentEditMeasurementTests: TempDirectoryTestCase {
    // MARK: - Fixtures

    private func solidSamples(
        _ value: UInt8, width: Int = 64, height: Int = 64, space: WorkingSpace = .sRGB
    ) -> RenderedPixelSamples {
        let bytes = [UInt8](repeating: 0, count: width * height * 4)
        var mutable = bytes
        for index in 0..<(width * height) {
            mutable[index * 4] = value
            mutable[index * 4 + 1] = value
            mutable[index * 4 + 2] = value
            mutable[index * 4 + 3] = 255
        }
        return RenderedPixelSamples(width: width, height: height, bytes: mutable, space: space)
    }

    private func rgbSamples(
        _ pixel: (UInt8, UInt8, UInt8), width: Int = 64, height: Int = 64
    ) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = pixel.0
            bytes[index * 4 + 1] = pixel.1
            bytes[index * 4 + 2] = pixel.2
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func mixedThirds(width: Int = 63, height: Int = 63) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 3 {
                    bytes[offset] = 255; bytes[offset + 1] = 0; bytes[offset + 2] = 0
                } else if x < 2 * width / 3 {
                    bytes[offset] = 0; bytes[offset + 1] = 255; bytes[offset + 2] = 0
                } else {
                    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 255
                }
            }
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func leftBlackRightWhite(width: Int = 64, height: Int = 64) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x < width / 2 ? 0 : 255
                let offset = (y * width + x) * 4
                bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
            }
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func standardSource(_ tag: String = "standard") -> ImageSource {
        ImageSource(data: Data(tag.utf8), nativeExtent: CGSize(width: 64, height: 64))
    }

    private func rawSource(_ tag: String = "raw") -> ImageSource {
        ImageSource(
            backing: .data(Data(tag.utf8)), kind: .raw,
            nativeExtent: CGSize(width: 4000, height: 3000)
        )
    }

    private func configured(
        samples: RenderedPixelSamples?,
        native: [NativePatchPixels]? = nil,
        capabilities: RAWCapabilities? = .distinctivelySeeded
    ) async -> (CurrentEditMeasurer, FakeRenderEngine) {
        let engine = FakeRenderEngine()
        await engine.setSampledStub(samples)
        await engine.setNativeStub(native)
        await engine.setStubbedCapabilities(capabilities)
        return (CurrentEditMeasurer(engine: engine), engine)
    }

    // MARK: - Revision guards

    func testStaleDocumentHashThrowsBeforeRendering() async throws {
        let (measurer, engine) = await configured(samples: solidSamples(128))
        let document = EditDocument()
        do {
            _ = try await measurer.measure(
                source: standardSource(), document: document,
                expectedDocumentHash: "stale-hash"
            )
            XCTFail("expected a stale-document failure")
        } catch let error as CurrentEditMeasurementError {
            XCTAssertEqual(
                error,
                .staleDocument(expected: "stale-hash", actual: document.editHash)
            )
        }
        let requests = await engine.sampleRequests
        XCTAssertTrue(requests.isEmpty, "a stale request must never reach the renderer")
    }

    func testInvalidSourceExtentThrows() async throws {
        let (measurer, engine) = await configured(samples: solidSamples(128))
        let bad = ImageSource(data: Data("bad".utf8), nativeExtent: .zero)
        let document = EditDocument()
        do {
            _ = try await measurer.measure(
                source: bad, document: document, expectedDocumentHash: document.editHash
            )
            XCTFail("expected an invalid-source failure")
        } catch let error as CurrentEditMeasurementError {
            XCTAssertEqual(error, .invalidSource)
        }
        let requests = await engine.sampleRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testRenderUnavailableThrowsAndLeavesDocumentUnchanged() async throws {
        let (measurer, _) = await configured(samples: nil)
        var document = EditDocument()
        document.light.exposure = 1
        let before = document
        do {
            _ = try await measurer.measure(
                source: standardSource(), document: document,
                expectedDocumentHash: document.editHash
            )
            XCTFail("expected render-unavailable")
        } catch let error as CurrentEditMeasurementError {
            XCTAssertEqual(error, .renderUnavailable)
        }
        XCTAssertEqual(document, before)
    }

    func testIdentityDocumentMeasuresExplicitlyAsBaseline() async throws {
        let (measurer, _) = await configured(samples: solidSamples(128))
        let document = EditDocument()
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertTrue(result.isBaseline)
        XCTAssertEqual(result.documentHash, document.editHash)
    }

    // MARK: - Linear vs display, headroom separation

    func testLinearLuminanceDiffersFromDisplayAndHeadroomStaysSeparate() async throws {
        let (measurer, _) = await configured(samples: solidSamples(128))
        let document = EditDocument()
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertLessThan(
            result.globalTone.linear.mean, result.globalTone.perceptual.mean,
            "linearized sRGB must sit below the encoded display mean for mid gray"
        )
        XCTAssertEqual(result.globalTone.linear.variant, .linear)
        XCTAssertEqual(result.globalTone.perceptual.variant, .perceptual)
        // A standard source carries no decoder headroom: the display clipping fraction is still
        // reported, but nothing claims it as headroom.
        XCTAssertFalse(result.highlightHeadroom.available)
        XCTAssertEqual(result.highlightHeadroom.source, .unavailable)
        XCTAssertNil(result.highlightHeadroom.headroomEV)
        XCTAssertEqual(result.highlightHeadroom.displayHighlightClipping, 0, accuracy: 0.001)
    }

    func testClippedWhiteKeepsDisplayClippingDistinctFromHeadroom() async throws {
        let (measurer, _) = await configured(samples: solidSamples(255))
        let document = EditDocument()
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertEqual(result.globalTone.perceptual.highlightClippingFraction, 1, accuracy: 0.001)
        XCTAssertEqual(result.highlightHeadroom.displayHighlightClipping, 1, accuracy: 0.001)
        XCTAssertFalse(result.highlightHeadroom.available)
        XCTAssertNil(result.highlightHeadroom.headroomEV)
    }

    func testRawHeadroomComesFromTheDecoderNeverTheDisplayBins() async throws {
        let (measurer, _) = await configured(samples: solidSamples(255))
        let document = EditDocument()
        let result = try await measurer.measure(
            source: rawSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertEqual(result.highlightHeadroom.source, .rawDecoder)
        XCTAssertTrue(result.highlightHeadroom.available)
        XCTAssertTrue(result.highlightHeadroom.rawRecoveryLikely)
        XCTAssertNil(
            result.highlightHeadroom.headroomEV,
            "headroom is never estimated from display bins"
        )
    }

    func testRawWithoutCapabilitiesReportsUnavailable() async throws {
        let (measurer, _) = await configured(samples: solidSamples(255), capabilities: nil)
        let document = EditDocument()
        let result = try await measurer.measure(
            source: rawSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertFalse(result.highlightHeadroom.available)
        XCTAssertFalse(result.highlightHeadroom.rawRecoveryLikely)
        XCTAssertEqual(result.highlightHeadroom.displayHighlightClipping, 1, accuracy: 0.001)
        XCTAssertLessThan(result.globalConfidence, 1, "missing headroom reduces confidence")
    }

    // MARK: - Pixel-correlated color

    func testSaturationAndHueComeFromTheSameSamples() async throws {
        let (redMeasurer, _) = await configured(samples: rgbSamples((255, 0, 0)))
        let document = EditDocument()
        let red = try await redMeasurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertGreaterThan(red.color.saturationMean, 0.9)
        XCTAssertEqual(red.color.hueHistogram.count, 12)
        XCTAssertEqual(red.color.hueHistogram.reduce(0, +), 1, accuracy: 0.001)
        XCTAssertEqual(red.color.hueHistogram[0], 1, accuracy: 0.001)
        XCTAssertLessThan(red.color.estimatedNeutrality, 0.2)

        let (grayMeasurer, _) = await configured(samples: solidSamples(128))
        let gray = try await grayMeasurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertEqual(gray.color.saturationMean, 0, accuracy: 0.001)
        XCTAssertEqual(gray.color.saturationP95, 0, accuracy: 0.001)
        XCTAssertGreaterThan(gray.color.estimatedNeutrality, 0.9)
    }

    func testNeutralCandidatesRecommendOnlyWithConfidentUnmixedEvidence() async throws {
        let document = EditDocument()
        let (grayMeasurer, _) = await configured(samples: solidSamples(128))
        let gray = try await grayMeasurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertFalse(gray.color.isMixed)
        XCTAssertTrue(gray.color.recommendsNeutralCorrection)
        XCTAssertTrue(gray.color.neutralCandidates.contains(where: \.recommendsCorrection))
        XCTAssertEqual(gray.color.neutralCandidates.count, 9)
        let center = gray.color.neutralCandidates.first { $0.column == 1 && $0.row == 1 }
        XCTAssertNotNil(center?.bounds)
        XCTAssertGreaterThan(center?.confidence ?? 0, 0.5)

        let (mixedMeasurer, _) = await configured(samples: mixedThirds())
        let mixed = try await mixedMeasurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertTrue(mixed.color.isMixed, "red/green/blue thirds must read as mixed")
        XCTAssertFalse(mixed.color.recommendsNeutralCorrection)
        XCTAssertFalse(mixed.color.neutralCandidates.contains(where: \.recommendsCorrection))
    }

    func testLocalContrastSeparatesFlatFromStructured() async throws {
        let document = EditDocument()
        let (flatMeasurer, _) = await configured(samples: solidSamples(128))
        let flat = try await flatMeasurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertEqual(flat.localContrast, 0, accuracy: 0.001)

        let (splitMeasurer, _) = await configured(samples: leftBlackRightWhite())
        let split = try await splitMeasurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertGreaterThan(split.localContrast, 0.2)
        XCTAssertGreaterThan(split.localContrastConfidence, 0)
    }

    // MARK: - Regional confidence independence

    func testFailedMaskLeavesGlobalFactsUsable() async throws {
        let (measurer, _) = await configured(samples: solidSamples(128))
        let source = standardSource()
        let image = try AnalysisImageFactory.make(
            from: source, configuration: AnalysisConfiguration(maximumDimension: 64)
        )
        let store = MaskStore(directory: tempDirectory)
        // A mask at a different resolution fails validation; the globals must survive it.
        let wrongSize = try NormalizedMask(
            size: PixelDimensions(width: 4, height: 4),
            values: [Float](repeating: 1, count: 16)
        )
        let fingerprint = PhotoSourceFingerprint.data(Data("standard".utf8))
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(Data("standard".utf8)),
            sourceFingerprint: fingerprint, kind: .subject, quality: .analysis
        )
        let reference = try await store.store(wrongSize, for: key, quality: .analysis)
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .analysis, reference: reference, confidence: 1, coverage: 1
        )
        _ = image
        let document = EditDocument()
        let result = try await measurer.measure(
            source: source, document: document,
            expectedDocumentHash: document.editHash, masks: [mask]
        )
        XCTAssertTrue(result.regions.isEmpty)
        XCTAssertEqual(result.failedMaskCount, 1)
        XCTAssertGreaterThan(result.globalTone.perceptual.mean, 0)
        XCTAssertLessThan(result.globalConfidence, 1)
    }

    func testSuccessfulRegionIsMeasuredThroughTheEffectiveDocument() async throws {
        let engine = FakeRenderEngine()
        let gray = try solidCGImage(value: 200, width: 8, height: 8)
        await engine.setPreviewResult(gray)
        await engine.setSampledStub(solidSamples(200, width: 8, height: 8))
        let sourceData = Data("regional-edit".utf8)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 8, height: 8))
        let image = try AnalysisImageFactory.make(
            from: source, configuration: AnalysisConfiguration(maximumDimension: 8)
        )
        let store = MaskStore(directory: tempDirectory)
        // The measurer must share the caller's MaskStore: regional pixels resolve through it,
        // and a stranger store correctly reports them missing.
        let measurer = CurrentEditMeasurer(engine: engine, store: store)
        let pixels = try NormalizedMask(
            size: image.dimensions, values: [Float](repeating: 1, count: 64)
        )
        let fingerprint = PhotoSourceFingerprint.data(sourceData)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(sourceData), sourceFingerprint: fingerprint,
            kind: .subject, quality: .analysis
        )
        let reference = try await store.store(pixels, for: key, quality: .analysis)
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .analysis, reference: reference, confidence: 0.9, coverage: 1
        )
        var document = EditDocument()
        document.light.exposure = 0.5
        let result = try await measurer.measure(
            source: source, document: document,
            expectedDocumentHash: document.editHash, masks: [mask]
        )
        XCTAssertEqual(result.regions.count, 1)
        XCTAssertEqual(result.failedMaskCount, 0)
        guard let region = result.regions.first else {
            XCTFail("regional measurement must succeed when mask pixels resolve")
            return
        }
        XCTAssertEqual(region.confidence, 0.9, accuracy: 0.001)
        // The regional render went through the analysis view of the edited document.
        let renders = await engine.renderRequests
        XCTAssertFalse(renders.isEmpty)
        XCTAssertEqual(
            renders.last?.document,
            AutoCandidateEvaluation.analysisDocument(from: document)
        )
    }

    // MARK: - Native detail

    func testNativePlannerIsBoundedAndDeterministic() {
        let fingerprint = PhotoSourceFingerprint.data(Data("fixture".utf8))
        let extent = CGSize(width: 4000, height: 3000)
        let first = NativePatchPlanner.plan(
            fingerprint: fingerprint, count: 5, edge: 128, imageExtent: extent
        )
        let second = NativePatchPlanner.plan(
            fingerprint: fingerprint, count: 5, edge: 128, imageExtent: extent
        )
        XCTAssertEqual(first, second, "same fixture must plan the same patches")
        XCTAssertEqual(first.count, 5)
        XCTAssertTrue(first.allSatisfy { $0.edge == 128 })
        // Center probe comes first so a reduced count still covers the frame.
        XCTAssertEqual(first[0].rect.midPoint.x, 0.5, accuracy: 0.05)
        XCTAssertEqual(first[0].rect.midPoint.y, 0.5, accuracy: 0.05)

        let capped = NativePatchPlanner.plan(
            fingerprint: fingerprint, count: 99, edge: 10_000, imageExtent: extent
        )
        XCTAssertEqual(capped.count, NativePatchPlanner.maxPatches)
        XCTAssertTrue(capped.allSatisfy { $0.edge == NativePatchPlanner.maxPatchSize })

        XCTAssertTrue(NativePatchPlanner.plan(
            fingerprint: fingerprint, count: 0, edge: 128, imageExtent: extent
        ).isEmpty)
        XCTAssertTrue(NativePatchPlanner.plan(
            fingerprint: fingerprint, count: 5, edge: 128, imageExtent: .zero
        ).isEmpty)
    }

    func testNativeDetailReportsUnavailableRatherThanGuessing() async throws {
        let (measurer, engine) = await configured(samples: solidSamples(128), native: nil)
        let document = EditDocument()
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertFalse(result.detail.available)
        XCTAssertEqual(result.detail.completed, 0)
        XCTAssertGreaterThan(result.detail.requested, 0, "patches were requested, none completed")
        XCTAssertGreaterThan(result.globalTone.perceptual.mean, 0, "globals still measured")
        let nativeRequests = await engine.nativeRequests
        XCTAssertEqual(nativeRequests.count, 1)
        XCTAssertEqual(nativeRequests[0].count, result.detail.requested)
    }

    func testNativeDetailAvailableWhenSamplerProvidesPatches() async throws {
        let patch = NativePatchPixels(
            width: 8, height: 8,
            bytes: [UInt8](repeating: 128, count: 8 * 8 * 4).enumerated().map { index, byte in
                index % 4 == 3 ? 255 : byte
            }
        )
        let specs = NativePatchPlanner.plan(
            fingerprint: PhotoSourceFingerprint.data(Data("standard".utf8)),
            count: 2, edge: 64, imageExtent: CGSize(width: 64, height: 64)
        )
        let (measurer, _) = await configured(
            samples: solidSamples(128), native: [patch, patch]
        )
        let document = EditDocument()
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash,
            configuration: CurrentEditMeasurementConfiguration(
                nativePatchCount: 2, nativePatchSize: 64
            )
        )
        XCTAssertTrue(result.detail.available)
        XCTAssertEqual(result.detail.completed, 2)
        XCTAssertEqual(result.detail.patchSpecs, specs)
    }

    // MARK: - Orientation, crop, color space, RAW

    func testRotatedDocumentMeasuresWithOrientedGeometry() async throws {
        let (measurer, engine) = await configured(samples: solidSamples(128))
        var document = EditDocument()
        document.rotation = .clockwise90
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertFalse(result.isBaseline)
        let requests = await engine.sampleRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].document.rotation, .clockwise90)
    }

    func testAnalysisViewStripsFinishButRetainsGeometryAndLight() async throws {
        let (measurer, engine) = await configured(samples: solidSamples(128))
        var document = EditDocument()
        document.light.exposure = 0.75
        document.crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )
        document.color.grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 300, saturation: 40),
            blending: 50, balance: 0
        )
        document.effects.grain = GrainAdjustments(amount: 40)
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertTrue(result.isAnalysisView)
        let requests = await engine.sampleRequests
        XCTAssertEqual(requests.count, 1)
        let rendered = requests[0].document
        XCTAssertEqual(
            rendered, AutoCandidateEvaluation.analysisDocument(from: document),
            "the sampler must see the analysis view, not the creative finish"
        )
        XCTAssertEqual(rendered.light.exposure, 0.75, "light survives the view transform")
        XCTAssertEqual(rendered.crop, document.crop, "crop survives the view transform")
    }

    func testCompleteViewRetainsTheFinish() async throws {
        let (measurer, engine) = await configured(samples: solidSamples(128))
        var document = EditDocument()
        document.effects.grain = GrainAdjustments(amount: 40)
        let configuration = CurrentEditMeasurementConfiguration(analysisView: false)
        let result = try await measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash, configuration: configuration
        )
        XCTAssertFalse(result.isAnalysisView)
        XCTAssertEqual(result.effectiveDocumentHash, document.editHash)
        let requests = await engine.sampleRequests
        XCTAssertEqual(requests[0].document, document)
    }

    func testColorSpaceAndRawPathsMeasure() async throws {
        let document = EditDocument()
        let (p3Measurer, _) = await configured(samples: solidSamples(
            128, space: .displayP3
        ))
        let p3 = try await p3Measurer.measure(
            source: standardSource(), document: document,
            expectedDocumentHash: document.editHash,
            configuration: CurrentEditMeasurementConfiguration(space: .displayP3)
        )
        XCTAssertGreaterThan(p3.globalTone.perceptual.mean, 0)

        let (rawMeasurer, _) = await configured(samples: solidSamples(100))
        let raw = try await rawMeasurer.measure(
            source: rawSource(), document: document,
            expectedDocumentHash: document.editHash
        )
        XCTAssertGreaterThan(raw.globalTone.perceptual.mean, 0)
        XCTAssertTrue(raw.highlightHeadroom.available)
    }

    // MARK: - Cache identity

    func testCacheKeysDistinguishSourceDocumentConfigurationAndRevision() {
        let engine = FakeRenderEngine()
        let measurer = CurrentEditMeasurer(engine: engine)
        let source = standardSource()
        let assetID = PhotoAssetID.data(Data("standard".utf8))
        let document = EditDocument()
        let configuration = CurrentEditMeasurementConfiguration()
        let base = measurer.key(
            source: source, assetID: assetID, document: document, configuration: configuration
        )

        var edited = EditDocument()
        edited.light.exposure = 1
        XCTAssertNotEqual(
            base,
            measurer.key(
                source: source, assetID: assetID, document: edited, configuration: configuration
            ),
            "effective document must participate in the key"
        )
        XCTAssertNotEqual(
            base,
            measurer.key(
                source: standardSource("other"), assetID: assetID,
                document: document, configuration: configuration
            ),
            "source must participate in the key"
        )
        XCTAssertNotEqual(
            base,
            measurer.key(
                source: source, assetID: assetID, document: document,
                configuration: CurrentEditMeasurementConfiguration(space: .displayP3)
            ),
            "render revision (space) must participate in the key"
        )
        XCTAssertNotEqual(
            base,
            measurer.key(
                source: source, assetID: assetID, document: document,
                configuration: CurrentEditMeasurementConfiguration(analysisView: false)
            ),
            "analysis configuration must participate in the key"
        )
        XCTAssertEqual(
            base,
            measurer.key(
                source: source, assetID: assetID, document: document, configuration: configuration
            ),
            "identical inputs must key identically"
        )
    }

    func testCacheRoundTripAndStaleStoreRejected() async throws {
        let cache = CurrentEditMeasurementCache(directory: tempDirectory)
        let engine = FakeRenderEngine()
        let measurer = CurrentEditMeasurer(engine: engine)
        let source = standardSource()
        let assetID = PhotoAssetID.data(Data("standard".utf8))
        let document = EditDocument()
        let configuration = CurrentEditMeasurementConfiguration()
        let key = measurer.key(
            source: source, assetID: assetID, document: document, configuration: configuration
        )
        let initialMiss = try await cache.measurement(for: key)
        XCTAssertNil(initialMiss)

        await engine.setSampledStub(solidSamples(128))
        let measurement = try await measurer.measure(
            source: source, assetID: assetID, document: document,
            expectedDocumentHash: document.editHash, configuration: configuration
        )
        try await cache.store(measurement, for: key)
        let roundTripped = try await cache.measurement(for: key)
        XCTAssertEqual(roundTripped, measurement)

        var edited = EditDocument()
        edited.light.exposure = 2
        let editedKey = measurer.key(
            source: source, assetID: assetID, document: edited, configuration: configuration
        )
        let editedMiss = try await cache.measurement(for: editedKey)
        XCTAssertNil(
            editedMiss,
            "an edited document must not read back older facts"
        )
        do {
            try await cache.store(measurement, for: editedKey)
            XCTFail("storing under a mismatched key must fail")
        } catch let error as CurrentEditMeasurementError {
            XCTAssertEqual(
                error,
                .staleDocument(
                    expected: editedKey.effectiveDocumentHash,
                    actual: measurement.effectiveDocumentHash
                )
            )
        }
    }

    // MARK: - Helpers

    private func solidCGImage(value: UInt8, width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { throw ImageError.processingFailed }
        return image
    }
}

// MARK: - Fake sampling accessors

/// Actor-isolated stub access for the sampling seam. `FakeRenderEngine` owns the state; these
/// keep the tests from reaching across isolation.
extension FakeRenderEngine {
    func setSampledStub(_ value: RenderedPixelSamples?) { sampledStub = value }

    func setNativeStub(_ value: [NativePatchPixels]?) { nativeStub = value }

    func setPreviewResult(_ value: CGImage?) { previewResult = value }
}
