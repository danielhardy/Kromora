import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1174 and KRMA-1180 through the real `RenderEngine`. The RAW methods need a local camera file
/// (see `Fixtures.localRAWURLs`) and are in the optional lane; the standard-image method runs in the
/// serial render lane. Each RAW method runs once per decoder calibration family present locally
/// (tone-curve ARW/Bayer DNG, local-tone-map ProRAW), so a family mix is exercised whenever the
/// fixture folder holds both.
final class RAWExposureRoutingRenderTests: TempDirectoryTestCase {

    private let box = CGSize(width: 384, height: 384)

    /// The first local RAW of each calibration family, so both mappings are covered when present.
    private func rawSources() async throws -> [ImageSource] {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAW; see Fixtures.localRAWURLs") }
        let engine = RenderEngine()
        var seen = Set<Double>()
        var sources: [ImageSource] = []
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 4000, height: 3000))
            let ratio = RAWExposureRouting.stopsPerSliderStop(
                decoder: await engine.rawCapabilities(for: source))
            if seen.insert(ratio).inserted { sources.append(source) }
        }
        return sources
    }

    private func decoderExposure(
        _ engine: RenderEngine, _ source: ImageSource, sliderEV: Double
    ) async -> Double {
        RAWExposureRouting.decoderExposure(
            forSliderEV: sliderEV, decoder: await engine.rawCapabilities(for: source))
    }

    private func label(_ source: ImageSource) -> String {
        if case .url(let url) = source.backing { return url.lastPathComponent }
        return "data"
    }

    private func isLinearFamily(_ engine: RenderEngine, _ source: ImageSource) async -> Bool {
        await engine.rawCapabilities(for: source)?.isLocalToneMapSupported == true
    }

    private func bytes(
        _ engine: RenderEngine, _ source: ImageSource, _ document: EditDocument,
        lut: CubeLUT? = nil, quality: RenderQuality = .preview, size: CGSize? = nil
    ) async throws -> [UInt8] {
        let request = RenderRequest(
            source: source, document: document, lut: lut, targetSize: size ?? box, quality: quality)
        let image = await engine.makeCGImage(request)
        return try Pixels.bytes(of: try XCTUnwrap(image))
    }

    private func meanLuma(_ pixels: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0.0
        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
            count += 1
        }
        return sum / count
    }

    // MARK: - RAW

    /// The slider and an explicit decoder value of the same size must be one operation: the slider
    /// document renders exactly like the document that spells the decoder exposure directly.
    func testSliderExposureIsAppliedOnceThroughTheDecoder() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let slider = try await bytes(engine, source, EditDocument(light: LightAdjustments(exposure: 1)))
            let decoder = try await bytes(
                engine, source,
                EditDocument(
                    rawDevelop: RAWDevelopSettings(
                        exposure: await decoderExposure(engine, source, sliderEV: 1))))
            let neutral = try await bytes(engine, source, EditDocument())
            assertPixelsEqual(slider, decoder, "slider exposure must be exactly the decoder exposure")
            assertPixelsDiffer(slider, neutral, "precondition: exposure must change the frame")
            XCTAssertGreaterThan(meanLuma(slider), meanLuma(neutral))
        }
    }

    func testExplicitDecoderExposureAndSliderCombineWithoutDoubleApplication() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let combined = try await bytes(
                engine, source,
                EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.5), light: LightAdjustments(exposure: 1)))
            let total = 0.5 + (await decoderExposure(engine, source, sliderEV: 1))
            let spelled = try await bytes(
                engine, source, EditDocument(rawDevelop: RAWDevelopSettings(exposure: total)))
            assertPixelsEqual(combined, spelled, "explicit + calibrated slider is one \(total)-stop exposure")
        }
    }

    /// Decoder exposure and RGB exposure both precede the Look now. On a tone-curve decoder they are
    /// different operations (the decoder applies its tone curve after exposure) and must not render
    /// alike; on a local-tone-map decoder the calibrated decoder stop *is* an RGB stop.
    func testRAWExposureIsAppliedBeforeTheLook() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let lut = TestImages.warmLUT()
            var document = EditDocument(light: LightAdjustments(exposure: 1))
            document.lut = LUTSettings(lutID: LUTID(raw: "warm"), intensity: 1)

            let routed = try await bytes(engine, source, document, lut: lut)
            let decoderThenLook = try await bytes(
                engine, source,
                EditDocument(
                    rawDevelop: RAWDevelopSettings(
                        exposure: await decoderExposure(engine, source, sliderEV: 1)),
                    lut: document.lut), lut: lut)
            let rgbThenLook = try await bytes(
                engine, source,
                EditDocument(adjustments: [.exposure(ev: 1)], lut: document.lut), lut: lut)
            assertPixelsEqual(routed, decoderThenLook, "exposure must precede the Look")
            if await isLinearFamily(engine, source) {
                XCTAssertEqual(
                    meanLuma(routed), meanLuma(rgbThenLook), accuracy: 2,
                    "a linear decoder stop and an RGB stop land on the same brightness under a Look")
            } else {
                assertPixelsDiffer(routed, rgbThenLook, "decoder-then-Look is not RGB-EV-then-Look")
            }
        }
    }

    /// KRMA-1180: below the shoulder, the calibrated slider lands on the RGB path's midtone brightness
    /// for either family, with and without a Look. This is a brightness match, not a pixel match.
    func testCalibratedSliderMatchesRGBMidtonesWithLooksOffAndOn() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let lut = TestImages.warmLUT()
            let look = LUTSettings(lutID: LUTID(raw: "warm"), intensity: 1)
            for withLook in [false, true] {
                let lutArgument = withLook ? lut : nil
                for ev in [-2.0, -1.0, 1.0] {
                    var routed = EditDocument(light: LightAdjustments(exposure: ev))
                    var rgb = EditDocument(adjustments: [.exposure(ev: ev)])
                    if withLook {
                        routed.lut = look
                        rgb.lut = look
                    }
                    let a = meanLuma(try await bytes(engine, source, routed, lut: lutArgument))
                    let b = meanLuma(try await bytes(engine, source, rgb, lut: lutArgument))
                    XCTAssertEqual(
                        a / b, 1, accuracy: 0.2,
                        "\(label(source)) \(ev) EV look=\(withLook): decoder \(a) vs RGB \(b)")
                }
            }
        }
    }

    /// A Look-browser candidate is a small render of the same routed document.
    func testLookCandidateSizedRenderFollowsTheRoutedDocument() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let lut = TestImages.warmLUT()
            let look = LUTSettings(lutID: LUTID(raw: "warm"), intensity: 0.7)
            let candidate = CGSize(width: 96, height: 96)
            let slider = try await bytes(
                engine, source,
                EditDocument(light: LightAdjustments(exposure: -1), lut: look), lut: lut,
                size: candidate)
            let spelled = try await bytes(
                engine, source,
                EditDocument(
                    rawDevelop: RAWDevelopSettings(
                        exposure: await decoderExposure(engine, source, sliderEV: -1)),
                    lut: look), lut: lut, size: candidate)
            assertPixelsEqual(slider, spelled, "candidate render must route exposure like the preview")
        }
    }

    func testInteractiveAndSettledFramesAgreeOnBrightness() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let document = EditDocument(light: LightAdjustments(exposure: -1.5))
            let interactive = try await bytes(engine, source, document, quality: .interactive)
            let settled = try await bytes(engine, source, document, quality: .preview)
            XCTAssertEqual(meanLuma(interactive), meanLuma(settled), accuracy: 3, label(source))
        }
    }

    func testHistogramAndExportFollowTheRoutedDocument() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            let slider = EditDocument(light: LightAdjustments(exposure: 1))
            let decoder = EditDocument(
                rawDevelop: RAWDevelopSettings(
                    exposure: await decoderExposure(engine, source, sliderEV: 1)))
            let scale = RenderScale.preview(maxSize: box)

            let sliderHistogram = await engine.histogram(
                source: source, document: slider, lut: nil, scale: scale, space: .current, maxDimension: 128)
            let decoderHistogram = await engine.histogram(
                source: source, document: decoder, lut: nil, scale: scale, space: .current, maxDimension: 128)
            let neutralHistogram = await engine.histogram(
                source: source, document: EditDocument(), lut: nil, scale: scale, space: .current, maxDimension: 128)
            XCTAssertEqual(try XCTUnwrap(sliderHistogram), try XCTUnwrap(decoderHistogram), label(source))
            XCTAssertNotEqual(try XCTUnwrap(sliderHistogram), try XCTUnwrap(neutralHistogram), label(source))

            let exportedSlider = try await engine.encode(
                source: source, document: slider, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
            let exportedDecoder = try await engine.encode(
                source: source, document: decoder, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
            assertPixelsEqual(
                try Pixels.bytes(of: try Pixels.decode(exportedSlider)),
                try Pixels.bytes(of: try Pixels.decode(exportedDecoder)),
                "export must route exposure exactly as preview does (\(label(source)))")
        }
    }

    /// Moving the slider must invalidate the developed source, and revisiting a value must hit it.
    func testSliderMovesInvalidateAndRevisitsReuseTheDevelopedSource() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            func render(_ ev: Double) async throws {
                _ = try await bytes(engine, source, EditDocument(light: LightAdjustments(exposure: ev)))
            }
            try await render(0.5)
            let afterFirst = await engine.cacheStatistics().developedSource
            try await render(1.0)
            let afterMove = await engine.cacheStatistics().developedSource
            XCTAssertGreaterThan(afterMove.misses, afterFirst.misses, "a new exposure is a new developed source")
            try await render(0.5)
            let afterRevisit = await engine.cacheStatistics().developedSource
            XCTAssertGreaterThan(afterRevisit.hits, afterMove.hits, "a revisited exposure reuses its developed source")
        }
    }

    /// The decoder state that picks the calibration is read from the live session, so it adds no
    /// second filter construction, and ticks keep reusing the one interactive filter.
    func testInteractiveExposureTicksReuseOneDecoderFilter() async throws {
        for source in try await rawSources() {
            let engine = RenderEngine()
            for ev in [0.2, 0.4, 0.6, 0.8] {
                _ = try await bytes(
                    engine, source, EditDocument(light: LightAdjustments(exposure: ev)), quality: .interactive)
            }
            let work = await engine.workStatistics()
            XCTAssertLessThanOrEqual(
                work.rawFilterConstructions, 1, "ticks must reuse the interactive RAW session (\(label(source)))")
            XCTAssertEqual(work.rawOutputRequests, 4)
        }
    }

    /// A settled render of another photo must neither evict the interactive session nor change the
    /// calibration the first photo routes with.
    func testCalibrationIsPerFileAndDoesNotChurnTheSession() async throws {
        let sources = try await rawSources()
        guard sources.count > 1 else { throw XCTSkip("needs one RAW of each calibration family") }
        let engine = RenderEngine()
        let first = sources[0]
        let second = sources[1]
        let document = EditDocument(light: LightAdjustments(exposure: 1))
        _ = try await bytes(engine, first, document, quality: .interactive)
        let firstSettled = try await bytes(engine, first, document)
        _ = try await bytes(engine, second, document)  // other family, settled
        let again = try await bytes(engine, first, document)
        assertPixelsEqual(firstSettled, again, "the other file's calibration must not leak")
        let spelled = try await bytes(
            engine, first,
            EditDocument(
                rawDevelop: RAWDevelopSettings(exposure: await decoderExposure(engine, first, sliderEV: 1))))
        assertPixelsEqual(again, spelled, "slider equals the first file's own calibrated spelling")
    }

    /// KRMA-1180: an edit holding both Light exposure and an explicit RAW exposure is saved to a
    /// package, reopened under a new lease, and rendered. It must still combine them once, for either
    /// family, against the unchanged stored schema.
    func testPackageReopenedEditCombinesLightAndExplicitRAWExposureOnce() async throws {
        let root = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: root)
        let standIn = tempDirectory.appendingPathComponent("photo.jpg")
        try Data("source".utf8).write(to: standIn)
        let lease = try PortablePackageLease.acquire(at: root)
        let imported = try package.importSources([.init(url: standIn)], lease: lease)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        let reference = EditSourceReference(
            assetID: PhotoAssetID(rawValue: "portable:\(assetID.raw)"),
            portableIdentity: PortablePhotoIdentity(
                assetID: assetID, sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")))
        let stored = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.4), light: LightAdjustments(exposure: 1))
        try await EditDocumentStore(package: package, lease: lease).save(stored, for: reference)
        try lease.release()

        let reopenedLease = try PortablePackageLease.acquire(at: root)
        defer { try? reopenedLease.release() }
        let loaded = await EditDocumentStore(package: package, lease: reopenedLease).load(for: reference)
        XCTAssertTrue(loaded.found)
        XCTAssertEqual(loaded.document, stored)

        for source in try await rawSources() {
            let engine = RenderEngine()
            let rendered = try await bytes(engine, source, loaded.document)
            let combined = 0.4 + (await decoderExposure(engine, source, sliderEV: 1))
            let spelled = try await bytes(
                engine, source, EditDocument(rawDevelop: RAWDevelopSettings(exposure: combined)))
            assertPixelsEqual(rendered, spelled, "\(label(source)): light + explicit is one \(combined)-stop exposure")
            let explicitOnly = try await bytes(
                engine, source, EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.4)))
            assertPixelsDiffer(rendered, explicitOnly, "precondition: the Light exposure contributes")
        }
    }

    // MARK: - Standard images

    func testStandardImageExposureStaysRGBAndIgnoresDecoderExposure() async throws {
        let url = try Fixtures.writeJPEG(
            width: 96, height: 64, orientation: 1, named: "routing.jpg", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        XCTAssertEqual(source.kind, .standard)
        let engine = RenderEngine()

        let neutral = try await bytes(engine, source, EditDocument())
        let lifted = try await bytes(engine, source, EditDocument(light: LightAdjustments(exposure: 1)))
        let decoderOnly = try await bytes(
            engine, source, EditDocument(rawDevelop: RAWDevelopSettings(exposure: 2)))
        assertPixelsDiffer(lifted, neutral, "RGB exposure must still brighten a standard image")
        XCTAssertGreaterThan(meanLuma(lifted), meanLuma(neutral))
        assertPixelsEqual(decoderOnly, neutral, "decoder settings never reach a standard image")

        let viaPipeline = try XCTUnwrap(
            RenderPipeline.buildImage(
                source: source, document: EditDocument(light: LightAdjustments(exposure: 1)),
                lut: nil, scale: .full))
        XCTAssertEqual(viaPipeline.extent.size, CGSize(width: 96, height: 64))
    }
}
