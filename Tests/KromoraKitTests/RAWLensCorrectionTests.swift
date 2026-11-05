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

    // MARK: - Full-resolution registration (KRMA-1181)

    /// Luma (or one colour channel) of a `size` square patch of `image` at `origin`, full resolution.
    private func patch(_ image: CIImage, origin: CGPoint, size: Int, channel: Int?) throws -> [Float] {
        var buffer = [Float](repeating: 0, count: size * size * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        buffer.withUnsafeMutableBytes {
            Pixels.context.render(
                image, toBitmap: $0.baseAddress!, rowBytes: size * 16,
                bounds: CGRect(x: origin.x, y: origin.y, width: CGFloat(size), height: CGFloat(size)),
                format: .RGBAf, colorSpace: space)
        }
        return (0..<size * size).map { i in
            let r = buffer[i * 4], g = buffer[i * 4 + 1], b = buffer[i * 4 + 2]
            switch channel {
            case 0: return r
            case 1: return g
            case 2: return b
            default: return 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
        }
    }

    /// 4× box downsample of a square patch, for the coarse registration pass.
    private func downsampled(_ p: [Float], size: Int) -> [Float] {
        let n = size / 4
        var out = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                var sum: Float = 0
                for dy in 0..<4 { for dx in 0..<4 { sum += p[(y * 4 + dy) * size + x * 4 + dx] } }
                out[y * n + x] = sum / 16
            }
        }
        return out
    }

    /// Sub-pixel shift (dx, dy) of `moving` relative to `reference`, found by maximising normalised
    /// cross-correlation of the central window over integer shifts within ±`range`, then a parabolic
    /// refinement. Returns nil for a textureless patch or a weak correlation peak.
    private func registrationShift(
        reference: [Float], moving: [Float], size: Int, window: Int, range: Int, minScore: Double = 0.8
    ) -> (dx: Double, dy: Double, score: Double)? {
        let lo = (size - window) / 2
        func score(_ sx: Int, _ sy: Int) -> Double {
            var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0
            for y in 0..<window {
                for x in 0..<window {
                    let a = Double(reference[(lo + y) * size + lo + x])
                    let b = Double(moving[(lo + y + sy) * size + lo + x + sx])
                    sa += a; sb += b; saa += a * a; sbb += b * b; sab += a * b
                }
            }
            let n = Double(window * window)
            let va = saa - sa * sa / n, vb = sbb - sb * sb / n
            guard va > 1e-6, vb > 1e-6 else { return -1 }
            return (sab - sa * sb / n) / (va * vb).squareRoot()
        }
        var best = (sx: 0, sy: 0, s: -2.0)
        var grid = [[Double]](repeating: [Double](repeating: -2, count: 2 * range + 1), count: 2 * range + 1)
        for sy in -range...range {
            for sx in -range...range {
                let s = score(sx, sy)
                grid[sy + range][sx + range] = s
                if s > best.s { best = (sx, sy, s) }
            }
        }
        guard best.s > minScore else { return nil }
        func refine(_ m: Double, _ c: Double, _ p: Double) -> Double {
            let d = m - 2 * c + p
            return abs(d) < 1e-12 ? 0 : 0.5 * (m - p) / d
        }
        var fx = 0.0, fy = 0.0
        if abs(best.sx) < range, abs(best.sy) < range {
            let c = best.s
            fx = refine(grid[best.sy + range][best.sx - 1 + range], c, grid[best.sy + range][best.sx + 1 + range])
            fy = refine(grid[best.sy - 1 + range][best.sx + range], c, grid[best.sy + 1 + range][best.sx + range])
        }
        return (Double(best.sx) + fx, Double(best.sy) + fy, best.s)
    }

    /// KRMA-1181: dense full-resolution registration of the lens-correction-on render against the
    /// off render. Geometric remapping (distortion) appears as a displacement field that grows with
    /// radius; a pure illumination change registers at ~0 everywhere. The same scene content serves as
    /// the "straight edges": every patch is registered directly, which measures the displacement
    /// without fitting lines or needing a calibration target.
    ///
    /// Patches are matched on a 4× box downsample (quarter-resolution NCC with parabolic sub-pixel
    /// refinement, ±96 full-resolution px). A full-resolution refinement was tried and dropped: the
    /// local magnification of a distortion correction (a few percent) deforms the window enough to
    /// break an exact match, while the coarse estimate is already accurate to a couple of pixels
    /// against displacements of tens of pixels. Matches with NCC ≤ 0.9, or pinned at the search
    /// limit, are discarded. R and B are also registered against G inside each render so the change
    /// in lateral chromatic aberration is reported separately from geometry.
    func testFullResolutionRegistrationOfEnabledAgainstDisabled() throws {
        let coarseSize = 640, coarseWindow = 256, coarseRange = 24
        let caSize = 160, caWindow = 64, caRange = 6
        for (url, source) in try sources() {
            let info = try probe(url)
            guard info.supported else {
                print("=== \(info.name): lens correction unsupported; nothing to register ===")
                continue
            }
            let on = try develop(source, lens: true, scale: .full)
            let off = try develop(source, lens: false, scale: .full)
            XCTAssertEqual(on.extent, off.extent, info.name)
            let e = on.extent
            let offAligned = off.transformed(
                by: CGAffineTransform(translationX: e.midX - off.extent.midX, y: e.midY - off.extent.midY))
            let halfDiagonal = (e.width * e.width / 4 + e.height * e.height / 4).squareRoot()

            struct Sample {
                var radius: Double
                /// Where the corrected render puts a scene point, relative to the uncorrected render,
                /// along the outward radial direction (px, positive = pushed outward).
                var outward: Double
                var tangential: Double
                var caRG: (on: Double, off: Double)?
                var caBG: (on: Double, off: Double)?
            }
            var samples: [Sample] = []
            var trace = ""
            let columns = 11, rows = 7
            for j in 0..<rows {
                for i in 0..<columns {
                    // Patch centres reach 96 % of each half-extent so the corners are measured.
                    let u = (Double(i) / Double(columns - 1) * 2 - 1) * 0.96
                    let v = (Double(j) / Double(rows - 1) * 2 - 1) * 0.96
                    let px = u * e.width / 2, py = v * e.height / 2
                    let norm = (px * px + py * py).squareRoot()
                    let rx = norm > 0 ? px / norm : 0, ry = norm > 0 ? py / norm : 0
                    func origin(_ size: Int) -> CGPoint {
                        CGPoint(x: (e.midX + px - Double(size) / 2).rounded(), y: (e.midY + py - Double(size) / 2).rounded())
                    }
                    let o = origin(coarseSize)
                    let ref = downsampled(try patch(on, origin: o, size: coarseSize, channel: nil), size: coarseSize)
                    let mov = downsampled(try patch(offAligned, origin: o, size: coarseSize, channel: nil), size: coarseSize)
                    guard let c = registrationShift(
                        reference: ref, moving: mov, size: coarseSize / 4, window: coarseWindow / 4,
                        range: coarseRange, minScore: -1)
                    else { continue }
                    let dx = c.dx * 4, dy = c.dy * 4
                    let pinned = abs(c.dx) >= Double(coarseRange) - 0.5 || abs(c.dy) >= Double(coarseRange) - 0.5
                    trace += String(
                        format: "  u %+.2f v %+.2f shift dx %+.2f dy %+.2f ncc %.3f%@\n", u, v, dx, dy, c.score,
                        c.score <= 0.9 || pinned ? " (discarded)" : "")
                    guard c.score > 0.9, !pinned else { continue }

                    // `off` content sits at on's position plus (dx, dy); the corrected render therefore
                    // moves the scene by −(dx, dy). Positive `outward` = pushed away from the centre.
                    let oc = origin(caSize)
                    func channelShift(_ image: CIImage, _ channel: Int) throws -> Double? {
                        let g = try patch(image, origin: oc, size: caSize, channel: 1)
                        let m = try patch(image, origin: oc, size: caSize, channel: channel)
                        guard let r = registrationShift(
                            reference: g, moving: m, size: caSize, window: caWindow, range: caRange)
                        else { return nil }
                        return r.dx * rx + r.dy * ry
                    }
                    func pair(_ channel: Int) throws -> (on: Double, off: Double)? {
                        guard let a = try channelShift(on, channel), let b = try channelShift(offAligned, channel)
                        else { return nil }
                        return (a, b)
                    }
                    samples.append(Sample(
                        radius: norm / halfDiagonal, outward: -(dx * rx + dy * ry),
                        tangential: -(-dx * ry + dy * rx), caRG: try pair(0), caBG: try pair(2)))
                }
            }

            var report = "\n=== \(info.name) full \(Int(e.width))x\(Int(e.height)); \(samples.count)/\(columns * rows) patches registered ===\n"
            let bands: [(String, ClosedRange<Double>)] = [
                ("0.0-0.2", 0...0.2), ("0.2-0.4", 0.2...0.4), ("0.4-0.6", 0.4...0.6),
                ("0.6-0.8", 0.6...0.8), ("0.8-1.0", 0.8...1.0)
            ]
            for (name, band) in bands {
                let inBand = samples.filter { band.contains($0.radius) }
                guard !inBand.isEmpty else { report += "r \(name): no registered patches\n"; continue }
                // Medians: a mismatched patch (flat sky, repeated texture) must not drag a band.
                func median(_ v: [Double]) -> Double {
                    let sorted = v.sorted()
                    return v.isEmpty ? .nan : sorted[sorted.count / 2]
                }
                let outward = median(inBand.map(\.outward))
                let tangential = median(inBand.map(\.tangential))
                let relative = median(inBand.map { $0.outward / max($0.radius * halfDiagonal, 1) }) * 100
                let rg = inBand.compactMap(\.caRG), bg = inBand.compactMap(\.caBG)
                func mean(_ v: [Double]) -> Double { v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count) }
                report += String(
                    format: "r %@ n=%d: median outward %+.2f px (%+.2f %% of radius), tangential %+.2f px; radial R-G on %+.3f off %+.3f, B-G on %+.3f off %+.3f (n=%d)\n",
                    name, inBand.count, outward, relative, tangential,
                    mean(rg.map(\.on)), mean(rg.map(\.off)), mean(bg.map(\.on)), mean(bg.map(\.off)), rg.count)
            }
            print(report + "per-patch trace (u, v = fraction of half-extent; shift = off relative to on, px):\n" + trace)
            XCTAssertFalse(samples.isEmpty, "\(info.name): no patch had enough texture to register")
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
