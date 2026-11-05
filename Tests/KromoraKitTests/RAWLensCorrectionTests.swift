import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1177: camera-dependent RAW lens correction.
///
/// Kromora has no lens-profile engine of its own. `CIRAWFilter.isLensCorrectionSupported` and
/// `isLensCorrectionEnabled` are the only controls Apple exposes, and the header does not say whether
/// they cover geometry, chromatic aberration, peripheral illumination, or some subset. The tests here
/// pin the policy (`nil` leaves Apple's per-image default; a saved value is honoured only where the
/// decoder supports it; preview and export share it) and, against local camera files, measure what
/// the switch actually changes so the outcome is evidence rather than inference from appearance.
///
/// The methods that read `realworldtest/` are in the optional lane (`scripts/ci-tests.sh optional`).
final class RAWLensCorrectionTests: XCTestCase {

    // MARK: - Measurement

    private struct Probe {
        var name: String
        var supported: Bool
        var initialEnabled: Bool
        var effectiveEnabled: Bool
        var decoderVersion: String
        var supportedVersions: String
        var nativeSize: CGSize
        var fullExtent: CGRect
    }

    private func sources() throws -> [(url: URL, source: ImageSource)] {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAW; see Fixtures.localRAWURLs") }
        return urls.map { ($0, ImageSource(url: $0, nativeExtent: .zero)) }
    }

    private func probe(_ url: URL, settings: RAWDevelopSettings = .neutral) throws -> Probe {
        let initial = try XCTUnwrap(CIRAWFilter(imageURL: url))
        let effective = try XCTUnwrap(CIRAWFilter(imageURL: url))
        settings.apply(to: effective)
        let source = ImageSource(url: url, nativeExtent: .zero)
        let full = try XCTUnwrap(
            RenderPipeline.developedSource(source, rawDevelop: settings, scale: .full))
        return Probe(
            name: url.lastPathComponent,
            supported: initial.isLensCorrectionSupported,
            initialEnabled: initial.isLensCorrectionEnabled,
            effectiveEnabled: effective.isLensCorrectionEnabled,
            decoderVersion: "\(initial.decoderVersion)",
            supportedVersions: initial.supportedDecoderVersions.map { "\($0)" }.joined(separator: ","),
            nativeSize: initial.nativeSize,
            fullExtent: full.extent
        )
    }

    /// RGBAf pixels of `image` re-centred on the origin and cropped to `size`, so two renders whose
    /// extents differ by a lens-correction crop or pad can be compared about the optical centre.
    private func centred(_ image: CIImage, size: CGSize) throws -> [Float] {
        let e = image.extent
        let shifted = image.transformed(
            by: CGAffineTransform(translationX: size.width / 2 - e.midX, y: size.height / 2 - e.midY))
        let w = Int(size.width), h = Int(size.height)
        var buffer = [Float](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        buffer.withUnsafeMutableBytes {
            Pixels.context.render(
                shifted, toBitmap: $0.baseAddress!, rowBytes: w * 16,
                bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: space)
        }
        return buffer
    }

    private struct Stats {
        var cornerToCenter = 0.0
        /// Mean (R−G)/G and (B−G)/G over the outer ring: a coarse lateral-CA/vignette colour proxy.
        var ringRG = 0.0
        var ringBG = 0.0
    }

    private func radius(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Double {
        let dx = (Double(x) + 0.5 - Double(w) / 2) / (Double(w) / 2)
        let dy = (Double(y) + 0.5 - Double(h) / 2) / (Double(h) / 2)
        return (dx * dx + dy * dy).squareRoot() / 2.0.squareRoot()
    }

    private func stats(_ p: [Float], _ w: Int, _ h: Int) -> Stats {
        var centre = 0.0, centreN = 0.0, corner = 0.0, cornerN = 0.0
        var rg = 0.0, bg = 0.0, ringN = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Double(p[i]), g = Double(p[i + 1]), b = Double(p[i + 2])
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let rad = radius(x, y, w, h)
                if rad < 0.15 { centre += luma; centreN += 1 }
                if rad > 0.9 { corner += luma; cornerN += 1 }
                if rad > 0.8, g > 1e-4 { rg += (r - g) / g; bg += (b - g) / g; ringN += 1 }
            }
        }
        return Stats(
            cornerToCenter: (corner / max(cornerN, 1)) / max(centre / max(centreN, 1), 1e-9),
            ringRG: rg / max(ringN, 1), ringBG: bg / max(ringN, 1))
    }

    /// Mean absolute RGB difference inside and outside the central 50 % radius.
    private func radialDiff(_ a: [Float], _ b: [Float], _ w: Int, _ h: Int) -> (inner: Double, outer: Double) {
        var inner = 0.0, innerN = 0.0, outer = 0.0, outerN = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let d = Double(abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])) / 3
                if radius(x, y, w, h) < 0.5 { inner += d; innerN += 1 } else { outer += d; outerN += 1 }
            }
        }
        return (inner / max(innerN, 1), outer / max(outerN, 1))
    }

    private func develop(
        _ source: ImageSource, lens: Bool?, scale: RenderScale
    ) throws -> CIImage {
        try XCTUnwrap(
            RenderPipeline.developedSource(
                source, rawDevelop: RAWDevelopSettings(lensCorrectionEnabled: lens), scale: scale))
    }

    // MARK: - Evidence (optional lane)

    /// Records, for every local RAW, what Apple reports and what flipping the one switch changes at
    /// full-resolution extents and at a measured preview size. Prints a table; asserts only the
    /// invariants that must hold for the policy to be sound.
    func testProbeReportsTheDecoderSwitchAndWhatItChanges() throws {
        for (url, source) in try sources() {
            let info = try probe(url)
            var report = """

                === \(info.name) ===
                decoderVersion \(info.decoderVersion) (supported: \(info.supportedVersions)) nativeSize \(Int(info.nativeSize.width))x\(Int(info.nativeSize.height))
                isLensCorrectionSupported \(info.supported) initialEnabled \(info.initialEnabled) effective(neutral) \(info.effectiveEnabled)
                neutral full extent \(info.fullExtent)

                """
            XCTAssertEqual(info.initialEnabled, info.effectiveEnabled, "neutral settings must not move the per-image default")

            if info.supported {
                let on = try develop(source, lens: true, scale: .full)
                let off = try develop(source, lens: false, scale: .full)
                report += "full extent on  \(on.extent)\nfull extent off \(off.extent)\n"

                let box = CGSize(width: 1500, height: 1500)
                let previewOn = try develop(source, lens: true, scale: .preview(maxSize: box))
                let previewOff = try develop(source, lens: false, scale: .preview(maxSize: box))
                report += "preview extent on \(previewOn.extent) off \(previewOff.extent)\n"
                let w = Int(min(previewOn.extent.width, previewOff.extent.width))
                let h = Int(min(previewOn.extent.height, previewOff.extent.height))
                let size = CGSize(width: w, height: h)
                let a = try centred(previewOn, size: size)
                let b = try centred(previewOff, size: size)
                let on1 = stats(a, w, h), off1 = stats(b, w, h)
                let diff = radialDiff(a, b, w, h)
                report += String(
                    format: "corner/centre luma  on %.4f  off %.4f\nouter-ring (R-G)/G  on %.5f off %.5f; (B-G)/G on %.5f off %.5f\nmean |on-off|  inner %.5f  outer %.5f\n",
                    on1.cornerToCenter, off1.cornerToCenter, on1.ringRG, off1.ringRG, on1.ringBG, off1.ringBG,
                    diff.inner, diff.outer)
            }
            print(report)
        }
    }

    // MARK: - Policy (optional lane: needs a real decoder)

    /// A document that leaves the lens switch unset renders exactly like one that spells out Apple's
    /// own per-image default, so `nil` really is "defer to the decoder" and not a hidden third state.
    func testUnsetLensCorrectionEqualsTheDecodersOwnDefault() throws {
        for (url, source) in try sources() {
            let info = try probe(url)
            let box = CGSize(width: 600, height: 600)
            let unset = try develop(source, lens: nil, scale: .preview(maxSize: box))
            let explicit = try develop(source, lens: info.initialEnabled, scale: .preview(maxSize: box))
            XCTAssertEqual(unset.extent, explicit.extent, info.name)
            let w = Int(unset.extent.width), h = Int(unset.extent.height)
            let a = try centred(unset, size: CGSize(width: w, height: h))
            let b = try centred(explicit, size: CGSize(width: w, height: h))
            XCTAssertEqual(radialDiff(a, b, w, h).outer, 0, accuracy: 1e-4, info.name)
        }
    }

    /// Where the decoder supports correction, a saved override reaches it: the opposite of the
    /// default changes the rendered frame. Where it does not, the saved value is inert.
    func testSavedOverrideIsHonouredOnlyWhereSupported() throws {
        for (url, source) in try sources() {
            let info = try probe(url)
            let box = CGSize(width: 600, height: 600)
            let flipped = try develop(source, lens: !info.initialEnabled, scale: .preview(maxSize: box))
            let unset = try develop(source, lens: nil, scale: .preview(maxSize: box))
            let w = Int(min(flipped.extent.width, unset.extent.width))
            let h = Int(min(flipped.extent.height, unset.extent.height))
            let size = CGSize(width: w, height: h)
            let diff = radialDiff(try centred(flipped, size: size), try centred(unset, size: size), w, h)
            if info.supported {
                XCTAssertGreaterThan(diff.outer, 0, "\(info.name): overriding the default must change the frame")
            } else {
                XCTAssertEqual(flipped.extent, unset.extent, info.name)
                XCTAssertEqual(diff.outer, 0, accuracy: 1e-6, "\(info.name): unsupported override must be inert")
            }
        }
    }

    /// Preview and export see the same correction: the preview extent is the full extent times the
    /// scale factor (within a pixel of rounding) for both the default and an explicit override, so a
    /// lens-correction crop cannot make the preview geometry drift from the export.
    func testPreviewAndFullExtentsAgreeUnderEitherSetting() throws {
        for (url, source) in try sources() {
            let info = try probe(url)
            for lens in [nil, true, false] as [Bool?] where info.supported || lens == nil {
                let full = try develop(source, lens: lens, scale: .full)
                let preview = try develop(source, lens: lens, scale: .preview(maxSize: CGSize(width: 800, height: 800)))
                let factor = preview.extent.width / full.extent.width
                XCTAssertEqual(
                    preview.extent.height, full.extent.height * factor, accuracy: 2,
                    "\(info.name) lens=\(String(describing: lens)): preview aspect must match export")
            }
        }
    }

    // MARK: - Engine session (the interactive path)

    /// The interactive session mutates one long-lived filter; resetting the override to `nil` must
    /// restore the decoder's own default rather than leave the last override latched.
    func testInteractiveSessionRestoresTheDefaultWhenTheOverrideIsCleared() async throws {
        for (url, source) in try sources() {
            let info = try probe(url)
            guard info.supported else { continue }
            let engine = RenderEngine()
            let box = CGSize(width: 500, height: 500)
            func bytes(_ lens: Bool?) async throws -> [UInt8] {
                let document = EditDocument(rawDevelop: RAWDevelopSettings(lensCorrectionEnabled: lens))
                let request = RenderRequest(source: source, document: document, targetSize: box, quality: .interactive)
                let image = await engine.makeCGImage(request)
                return try Pixels.bytes(of: try XCTUnwrap(image))
            }
            let before = try await bytes(nil)
            let overridden = try await bytes(!info.initialEnabled)
            let after = try await bytes(nil)
            assertPixelsDiffer(before, overridden, "\(info.name): the override must reach the interactive filter")
            assertPixelsEqual(before, after, "\(info.name): clearing the override must restore the default")
        }
    }
}

/// KRMA-1177 policy that needs no camera file: the saved lens value is tri-state and survives a
/// round trip, and the control is offered only where the decoder reports support.
final class RAWLensCorrectionPolicyTests: XCTestCase {

    private func roundTrip(_ settings: RAWDevelopSettings) throws -> RAWDevelopSettings {
        try JSONDecoder().decode(RAWDevelopSettings.self, from: JSONEncoder().encode(settings))
    }

    /// `nil` (defer to Apple's per-image default) must stay distinct from an explicit `false`, or an
    /// untouched document would silently pin correction off the first time it was saved.
    func testUnsetOnAndOffSurviveAPackageRoundTripAsDistinctValues() throws {
        XCTAssertNil(try roundTrip(.neutral).lensCorrectionEnabled)
        XCTAssertEqual(try roundTrip(RAWDevelopSettings(lensCorrectionEnabled: true)).lensCorrectionEnabled, true)
        XCTAssertEqual(try roundTrip(RAWDevelopSettings(lensCorrectionEnabled: false)).lensCorrectionEnabled, false)
        XCTAssertTrue(RAWDevelopSettings().isNeutral, "an unset lens value is the neutral default")
        XCTAssertFalse(RAWDevelopSettings(lensCorrectionEnabled: false).isNeutral)
    }

    func testTheControlFollowsTheDecodersSupportFlag() {
        XCTAssertTrue(RAWCapabilities(isLensCorrectionSupported: true).supports(.lensCorrection))
        XCTAssertFalse(RAWCapabilities(isLensCorrectionSupported: false).supports(.lensCorrection))
    }
}
