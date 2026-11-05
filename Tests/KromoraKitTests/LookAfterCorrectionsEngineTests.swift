import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1178 through the real `RenderEngine`: corrections → Look → finishing.
///
/// The pixel-order proofs live in `RenderPipelineTests`; this file pins what only the engine owns —
/// that it evaluates that exact graph, that the completed processing prefix is invalidated on both
/// sides of the Look, that Look browsing reuses the developed source, and that Save as Look samples
/// the same order the canvas renders. The RAW methods need a local camera file and are in the
/// optional lane.
final class LookAfterCorrectionsEngineTests: TempDirectoryTestCase {

    private var source: ImageSource!
    private var sourceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "look-order.png", in: tempDirectory)
        sourceURL = url
        source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    /// A strongly non-linear cube (per-channel cubic with a cross-channel term).
    private func curvedLUT(name: String = "curved", gamma: Float = 3) -> CubeLUT {
        let size = 8
        var cube = [SIMD3<Float>]()
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let (x, y, z) = (Float(r) / denom, Float(g) / denom, Float(b) / denom)
                    cube.append(SIMD3(pow(x, gamma), min(1, y * y + 0.2 * x * z), sqrt(z)))
                }
            }
        }
        return CubeLUT(cube: cube, size: size, name: name)
    }

    /// A smooth but clearly non-linear cube. `curvedLUT` has an infinite-slope `sqrt` that no
    /// 65³ table can reproduce, which would make Save as Look's approximation, not the pipeline
    /// order, the thing under test.
    private func smoothLUT(name: String = "smooth") -> CubeLUT {
        let size = 9
        var cube = [SIMD3<Float>]()
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let (x, y, z) = (Float(r) / denom, Float(g) / denom, Float(b) / denom)
                    cube.append(SIMD3(x * x, min(1, y * (0.75 + 0.25 * y) + 0.1 * x * z), z * z * (3 - 2 * z)))
                }
            }
        }
        return CubeLUT(cube: cube, size: size, name: name)
    }

    private let corrections = EditDocument(
        light: LightAdjustments(exposure: 0.7, contrast: 20),
        color: ColorAdjustments(vibrance: 25, saturation: 30),
        adjustments: [.temperatureTint(temp: 5600, tint: 6)]
    )

    private func document(
        _ base: EditDocument, look lut: CubeLUT?, intensity: Double = 1
    ) -> EditDocument {
        var document = base
        if let lut { document.lut = LUTSettings(lutID: lut.lutID, intensity: intensity) }
        return document
    }

    private func preview(
        _ engine: RenderEngine, _ document: EditDocument, lut: CubeLUT?,
        quality: RenderQuality = .preview
    ) async throws -> [UInt8] {
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: CGSize(width: 64, height: 64), quality: quality,
            output: .raster, space: .sRGB)
        let image = await engine.makeCGImage(request)
        return try Pixels.bytes(of: try XCTUnwrap(image))
    }

    // MARK: - Engine evaluates the pipeline order

    func testEngineRendersLookOverCorrectionsAtFullScale() async throws {
        let engine = RenderEngine()
        let lut = curvedLUT()
        let document = document(
            EditDocument(
                light: corrections.light, color: corrections.color,
                effects: EffectsAdjustments(texture: 25), adjustments: corrections.adjustments),
            look: lut, intensity: 0.8)
        let rendered = await engine.makeCGImage(
            source: source, document: document, lut: lut, scale: .full, space: .current)
        let viaEngine = try XCTUnwrap(rendered)
        let graph = try XCTUnwrap(
            RenderPipeline.buildImage(
                source: source, document: document, lut: lut, scale: .full, space: .current))
        assertPixelsEqual(
            try Pixels.bytes(of: viaEngine), try Pixels.bytes(of: graph),
            "the engine must evaluate corrections → Look → finishing unchanged")
    }

    // MARK: - Processing-prefix invalidation

    /// Either side of the Look is part of the prefix identity: a different Look over the same
    /// corrections, and different corrections under the same Look, each miss; a revisit hits and
    /// returns the first frame's pixels.
    func testPrefixInvalidatesOnBothSidesOfTheLookAndRevisitsHit() async throws {
        let engine = RenderEngine()
        let lutA = curvedLUT(name: "a", gamma: 3)
        let lutB = curvedLUT(name: "b", gamma: 1.6)
        let a = document(corrections, look: lutA)
        let otherLook = document(corrections, look: lutB)
        var otherCorrections = corrections
        otherCorrections.light.exposure = -0.4
        let otherCorr = document(otherCorrections, look: lutA)

        let first = try await preview(engine, a, lut: lutA)
        let afterFirst = await engine.workStatistics().processingPrefixMaterializations
        let lookChanged = try await preview(engine, otherLook, lut: lutB)
        let correctionChanged = try await preview(engine, otherCorr, lut: lutA)
        let afterChanges = await engine.workStatistics().processingPrefixMaterializations
        assertPixelsDiffer(first, lookChanged, byAtLeast: 4, "a new Look must not reuse the prefix")
        assertPixelsDiffer(first, correctionChanged, byAtLeast: 4, "new corrections must not reuse it")
        XCTAssertEqual(afterChanges - afterFirst, 2, "each change is one new prefix")

        let hitsBefore = await engine.cacheStatistics().processingPrefix.hits
        let revisit = try await preview(engine, a, lut: lutA)
        let hitsAfter = await engine.cacheStatistics().processingPrefix.hits
        assertPixelsEqual(first, revisit, "revisiting the first state reproduces its pixels")
        XCTAssertGreaterThan(hitsAfter, hitsBefore, "the revisit must hit the retained prefix")
        let afterRevisit = await engine.workStatistics().processingPrefixMaterializations
        XCTAssertEqual(afterRevisit, afterChanges, "a revisit materializes nothing")
    }

    /// Finishing (local/crop/vignette/grain) changes sit outside the prefix: they reuse it.
    func testFinishingEditsReuseThePrefix() async throws {
        let engine = RenderEngine()
        let lut = curvedLUT()
        let base = document(corrections, look: lut)
        _ = try await preview(engine, base, lut: lut)
        let afterFirst = await engine.workStatistics().processingPrefixMaterializations
        var grainy = base
        grainy.effects.grain = GrainAdjustments(amount: 50)
        grainy.effects.vignette = VignetteAdjustments(amount: -30)
        _ = try await preview(engine, grainy, lut: lut)
        let afterGrain = await engine.workStatistics().processingPrefixMaterializations
        XCTAssertEqual(afterGrain, afterFirst, "vignette/grain must not rebuild the graded prefix")
    }

    // MARK: - Save as Look samples the canvas order

    /// A cube saved from `corrections + Look` reproduces the canvas's `Look(corrections(x))` when
    /// applied as a lone Look, and not the previous `corrections(Look(x))`.
    func testSaveAsLookSamplesCorrectionsThenLook() throws {
        let lut = smoothLUT()
        // Moderate corrections keep the corrected image inside the Look's [0, 1] domain. Past it the
        // table clamps (a kink no lattice reproduces exactly); that limit is measured and
        // documented in LOOKS.md, not what this test pins.
        let gentle = EditDocument(
            light: LightAdjustments(exposure: 0.25, contrast: 12),
            color: ColorAdjustments(saturation: 10),
            adjustments: [.temperatureTint(temp: 6000, tint: 3)])
        let document = document(gentle, look: lut)
        let conversion = try LookLUTConverter.convert(document: document, lut: lut, size: 33)
        XCTAssertEqual(
            conversion.supportMatrix.entries.map(\.id),
            ["light", "color", "adjustment-0", "look"])
        let saved = CubeLUT(
            cube: conversion.cube, size: conversion.size, name: "saved",
            authoringSpace: conversion.workingSpace)

        let engineGraph = try XCTUnwrap(
            RenderPipeline.buildImage(
                source: source, document: document, lut: lut, scale: .full))
        let viaSaved = try XCTUnwrap(
            RenderPipeline.buildImage(
                source: source, document: self.document(EditDocument(), look: saved), lut: saved,
                scale: .full))
        let expected = try Pixels.bytes(of: engineGraph)
        let actual = try Pixels.bytes(of: viaSaved)
        let worst = zip(expected, actual).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 6, "the saved cube must stand in for corrections + Look")

        let developed = try XCTUnwrap(
            CIImage(
                contentsOf: sourceURL, options: ImageDecoder.orientedLoadOptions))
        let oldOrder = RenderPipeline.buildGradedImage(
            developed: try XCTUnwrap(lut.apply(to: developed, intensity: 1)),
            document: gentle, lut: nil)
        assertPixelsDiffer(
            try Pixels.bytes(of: oldOrder), actual, byAtLeast: 4,
            "the saved cube is not the previous Look-first order")
    }

    // MARK: - Look browser candidates

    /// A candidate renders what the canvas would show if that Look were chosen, and a browsing pass
    /// over several Looks reuses the single developed source.
    func testLookCandidatesMatchTheCanvasAndShareTheDevelopedSource() async throws {
        let engine = RenderEngine()
        let looks = [curvedLUT(name: "c1", gamma: 3), curvedLUT(name: "c2", gamma: 2)]
        let size = CGSize(width: 64, height: 48)
        for look in looks {
            let request = LookPreviewRequest(
                source: source, document: corrections, look: look, targetSize: size)
            let candidateImage = await engine.makeLookPreviewCGImage(request)
            let canvasImage = await engine.makeCGImage(request.renderRequest)
            let candidate = try XCTUnwrap(candidateImage)
            let canvas = try XCTUnwrap(canvasImage)
            assertPixelsEqual(
                try Pixels.bytes(of: candidate), try Pixels.bytes(of: canvas),
                "a candidate must equal the canvas with that Look chosen")
        }
        let stats = await engine.cacheStatistics()
        XCTAssertGreaterThan(
            stats.developedSource.hits + stats.thumbnailDevelopedSource.hits, 0,
            "candidates over one photo share its developed source")
    }

    // MARK: - RAW (optional lane)

    private func rawSource() throws -> ImageSource {
        let url = try XCTUnwrap(Fixtures.localRAWURLs.first, "no local RAW; see Fixtures.localRAWURLs")
        return ImageSource(url: url, nativeExtent: CGSize(width: 4000, height: 3000))
    }

    /// RGB-only finishing and Look changes must not re-decode the RAW: the decoder is asked once.
    func testRGBOnlyChangesDoNotRedecodeTheRAW() async throws {
        let raw: ImageSource
        do { raw = try rawSource() } catch { throw XCTSkip("no local RAW; see Fixtures.localRAWURLs") }
        let engine = RenderEngine()
        let lutA = curvedLUT(name: "a", gamma: 3)
        let lutB = curvedLUT(name: "b", gamma: 1.6)
        func render(_ document: EditDocument, _ lut: CubeLUT?) async throws {
            let request = RenderRequest(
                source: raw, document: document, lut: lut,
                targetSize: CGSize(width: 384, height: 384), quality: .preview)
            let image = await engine.makeCGImage(request)
            _ = try XCTUnwrap(image)
        }
        var base = EditDocument(light: LightAdjustments(contrast: 20), color: ColorAdjustments(saturation: 20))
        try await render(document(base, look: lutA), lutA)
        let afterFirst = await engine.cacheStatistics().developedSource.misses
        try await render(document(base, look: lutB), lutB)
        try await render(document(base, look: lutA, intensity: 0.4), lutA)
        base.color.saturation = 45
        try await render(document(base, look: lutA), lutA)
        base.effects.grain = GrainAdjustments(amount: 40)
        try await render(document(base, look: lutA), lutA)
        let afterEdits = await engine.cacheStatistics().developedSource.misses
        XCTAssertEqual(afterEdits, afterFirst, "RGB-only edits must reuse the developed RAW")
    }
}
