import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renderer-backed Auto candidate evaluation (KRMA-342).
///
/// This is the trust foundation for every later Auto decision: instead of a CSS or synthetic
/// approximation, candidates are rendered through the real `RenderEngine` seam
/// (`RenderEngining.makeCGImage`, which shares `buildImage` with preview and export) at an
/// evaluation scale, then compared as actual pixels.
///
/// What this ticket owns:
/// - an analysis-view document transform that temporarily excludes LUTs, grading, grain, and
///   decorative vignette for correction proposals (the complete edit is retained for final
///   candidate evaluation);
/// - a reusable evaluation seam that renders unchanged / proposed / complete documents with
///   matching orientation, crop geometry, and color-space handling;
/// - real before/after pixels, a difference image, and actual mask overlays;
/// - a value-only report (fixture identity, revision, scale, changed controls, measurements,
///   render failures) written outside the committed source tree.
///
/// What this ticket does NOT own: Auto policy or candidate selection (KRMA-345/347), scene
/// evidence (KRMA-344), or measurements of the current render (KRMA-343).
enum AutoCandidateEvaluation {
    /// Long edge used for evaluation renders. Matches the analysis default (768px) so later
    /// measurement and policy tickets evaluate what analysis actually saw.
    static let evaluationLongEdge = 768

    /// Target box that fits `nativeExtent` inside the evaluation long edge without upscaling.
    static func targetSize(for nativeExtent: CGSize, longEdge: Int = evaluationLongEdge) -> CGSize {
        guard nativeExtent.width > 0, nativeExtent.height > 0,
              nativeExtent.width.isFinite, nativeExtent.height.isFinite,
              longEdge > 0
        else { return nativeExtent }
        let longest = max(nativeExtent.width, nativeExtent.height)
        let scale = min(1, CGFloat(longEdge) / longest)
        return CGSize(width: nativeExtent.width * scale, height: nativeExtent.height * scale)
    }

    /// The Auto analysis view of a complete edit: LUT, color grading, grain, and decorative
    /// vignette are excluded so correction proposals are fit against photographic tone/color
    /// rather than a creative finish. Crop, rotation, RAW develop, light, vibrance/saturation,
    /// mixer, detail effects (texture/clarity/dehaze), curves, ordered adjustments, and local
    /// masks are retained so geometry and photographic intent survive the view transform.
    static func analysisDocument(from complete: EditDocument) -> EditDocument {
        var view = complete
        view.lut = .none
        view.color.grading = .neutral
        view.effects.grain = .neutral
        view.effects.vignette = .neutral
        return view
    }

    /// Names of the photographer-facing controls that differ between two documents, for the
    /// human/agent-readable report. Order is stable; empty means the proposal is a no-op.
    static func changedControls(baseline: EditDocument, candidate: EditDocument) -> [String] {
        var changed: [String] = []
        if baseline.rawDevelop != candidate.rawDevelop { changed.append("rawDevelop") }
        if baseline.light != candidate.light { changed.append("light") }
        if baseline.color.vibrance != candidate.color.vibrance
            || baseline.color.saturation != candidate.color.saturation
        { changed.append("color.vibranceSaturation") }
        if baseline.color.mixer != candidate.color.mixer { changed.append("color.mixer") }
        if baseline.color.grading != candidate.color.grading { changed.append("color.grading") }
        if baseline.effects.texture != candidate.effects.texture
            || baseline.effects.clarity != candidate.effects.clarity
            || baseline.effects.dehaze != candidate.effects.dehaze
        { changed.append("effects.detail") }
        if baseline.effects.vignette != candidate.effects.vignette { changed.append("effects.vignette") }
        if baseline.effects.grain != candidate.effects.grain { changed.append("effects.grain") }
        if baseline.crop != candidate.crop { changed.append("crop") }
        if baseline.rotation != candidate.rotation { changed.append("rotation") }
        if baseline.adjustments != candidate.adjustments { changed.append("adjustments") }
        if baseline.lut != candidate.lut { changed.append("lut") }
        if baseline.localAdjustments != candidate.localAdjustments { changed.append("localAdjustments") }
        return changed
    }
}

/// One rendered document inside an evaluation: PNG bytes plus the pixel extent actually produced.
struct AutoEvaluatedRender: Sendable, Equatable {
    let pngData: Data
    let width: Int
    let height: Int

    var isEmpty: Bool { pngData.isEmpty || width <= 0 || height <= 0 }
}

/// Value-only evaluation report. Codable so the generated artifact is machinable; Sendable so it
/// can cross the render-actor boundary. Pixel buffers are never stored here — PNGs live beside
/// the JSON artifact.
struct AutoEvaluationReport: Codable, Sendable, Equatable {
    struct Measurements: Codable, Sendable, Equatable {
        /// Mean per-channel absolute difference over the shared extent, 0…1.
        let meanAbsoluteDifference: Double
        /// Maximum single-channel absolute difference, 0…1.
        let maxDifference: Double
        /// Fraction of pixels whose max-channel difference exceeds 1/255.
        let changedPixelFraction: Double
    }

    let fixtureID: String
    let sourceFingerprint: String
    let baseDocumentHash: String
    let proposedDocumentHash: String
    /// Hash of the complete edit when supplied (final candidate evaluation); nil when the
    /// evaluation only compared base vs. analysis-view proposal.
    let completeDocumentHash: String?
    let renderWidth: Int
    let renderHeight: Int
    let colorSpace: String
    let targetLongEdge: Int
    let changedControls: [String]
    let analysisViewChangedControls: [String]
    let measurements: Measurements?
    /// Per-role render failures. A missing render is recorded here and never presented as a
    /// successful candidate.
    let renderFailures: [String]
    /// Roles for which a mask overlay was produced (subset of base/proposed/complete).
    let maskOverlays: [String]

    var hasFailures: Bool { !renderFailures.isEmpty }

    /// Markdown summary for the agent/human-readable artifact.
    func markdown() -> String {
        var lines = [
            "# Auto candidate evaluation — \(fixtureID)",
            "",
            "- source: `\(sourceFingerprint.prefix(16))…`",
            "- base: `\(baseDocumentHash.prefix(12))` proposed: `\(proposedDocumentHash.prefix(12))`"
                + (completeDocumentHash.map { " complete: `\($0.prefix(12))`" } ?? ""),
            "- render: \(renderWidth)×\(renderHeight) (\(colorSpace), long edge \(targetLongEdge))",
            "- changed controls: \(changedControls.isEmpty ? "none (no-op)" : changedControls.joined(separator: ", "))",
            "- analysis-view delta: \(analysisViewChangedControls.isEmpty ? "none" : analysisViewChangedControls.joined(separator: ", "))",
        ]
        if let measurements {
            lines.append(
                "- diff: mean \(String(format: "%.5f", measurements.meanAbsoluteDifference)), "
                    + "max \(String(format: "%.4f", measurements.maxDifference)), "
                    + "changed \(String(format: "%.2f%%", measurements.changedPixelFraction * 100))"
            )
        } else {
            lines.append("- diff: unavailable (render failure)")
        }
        lines.append(
            "- failures: \(renderFailures.isEmpty ? "none" : renderFailures.joined(separator: ", "))"
        )
        lines.append(
            "- mask overlays: \(maskOverlays.isEmpty ? "none" : maskOverlays.joined(separator: ", "))"
        )
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Renderer-backed evaluator. The engine is injected as `any RenderEngining` so tests can drive
/// the whole seam against a document-dependent double without a GPU, while production passes
/// `RenderEngine.shared` (or any configured `RenderEngine`).
struct AutoCandidateEvaluator: Sendable {
    let targetLongEdge: Int
    let space: WorkingSpace

    init(targetLongEdge: Int = AutoCandidateEvaluation.evaluationLongEdge, space: WorkingSpace = .current) {
        self.targetLongEdge = max(1, targetLongEdge)
        self.space = space
    }

    struct Evaluation: Sendable {
        let report: AutoEvaluationReport
        let base: AutoEvaluatedRender?
        let proposed: AutoEvaluatedRender?
        let complete: AutoEvaluatedRender?
        let diffPNG: Data?
        let maskOverlays: [String: Data]
    }

    /// Render base, proposed, and (when supplied) complete documents through the real pipeline
    /// seam, then compare base vs. proposed as actual pixels.
    func evaluate(
        fixtureID: String,
        source: ImageSource,
        baseDocument: EditDocument,
        proposedDocument: EditDocument,
        completeDocument: EditDocument? = nil,
        lut: CubeLUT? = nil,
        engine: any RenderEngining
    ) async -> Evaluation {
        let targetSize = AutoCandidateEvaluation.targetSize(
            for: baseDocument.rotation.orientedExtent(source.nativeExtent),
            longEdge: targetLongEdge
        )
        let base = await render(source: source, document: baseDocument, lut: lut,
                                targetSize: targetSize, engine: engine)
        let proposed = await render(source: source, document: proposedDocument, lut: lut,
                                    targetSize: targetSize, engine: engine)
        let complete: AutoEvaluatedRender?
        if let completeDocument {
            complete = await render(source: source, document: completeDocument, lut: lut,
                                    targetSize: targetSize, engine: engine)
        } else {
            complete = nil
        }

        var failures: [String] = []
        if base == nil { failures.append("base") }
        if proposed == nil { failures.append("proposed") }
        if completeDocument != nil, complete == nil { failures.append("complete") }

        let measurements: AutoEvaluationReport.Measurements?
        let diffPNG: Data?
        if let base, let proposed {
            let comparison = Self.compare(base: base, proposed: proposed)
            measurements = comparison.measurements
            diffPNG = comparison.diffPNG
        } else {
            measurements = nil
            diffPNG = nil
        }

        var overlays: [String: Data] = [:]
        var overlayRoles: [String] = []
        for (role, document, render) in [
            ("base", baseDocument, base),
            ("proposed", proposedDocument, proposed),
            ("complete", completeDocument, complete),
        ] as [(String, EditDocument?, AutoEvaluatedRender?)] {
            guard let document, render != nil, !document.localAdjustments.isEmpty else { continue }
            if let png = await maskOverlay(
                source: source, document: document, targetSize: targetSize, engine: engine
            ) {
                overlays[role] = png
                overlayRoles.append(role)
            }
        }

        let analysisView = AutoCandidateEvaluation.analysisDocument(from: baseDocument)
        let report = AutoEvaluationReport(
            fixtureID: fixtureID,
            sourceFingerprint: source.cacheFingerprint,
            baseDocumentHash: baseDocument.editHash,
            proposedDocumentHash: proposedDocument.editHash,
            completeDocumentHash: completeDocument?.editHash,
            renderWidth: base?.width ?? proposed?.width ?? 0,
            renderHeight: base?.height ?? proposed?.height ?? 0,
            colorSpace: space.rawValue,
            targetLongEdge: targetLongEdge,
            changedControls: AutoCandidateEvaluation.changedControls(
                baseline: baseDocument, candidate: proposedDocument
            ),
            analysisViewChangedControls: AutoCandidateEvaluation.changedControls(
                baseline: analysisView, candidate: proposedDocument
            ),
            measurements: measurements,
            renderFailures: failures,
            maskOverlays: overlayRoles
        )
        return Evaluation(
            report: report, base: base, proposed: proposed, complete: complete,
            diffPNG: diffPNG, maskOverlays: overlays
        )
    }

    /// Preview/export parity probe: the preview raster and the encoded-then-decoded export path
    /// must agree on pixel extent for the same document. Both go through the shared `buildImage`
    /// graph and differ only in quality/output policy, so a mismatch is structural, not cosmetic.
    func checkPreviewExportParity(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT? = nil,
        engine: any RenderEngining
    ) async -> Bool {
        let targetSize = AutoCandidateEvaluation.targetSize(
            for: document.rotation.orientedExtent(source.nativeExtent),
            longEdge: targetLongEdge
        )
        let previewRequest = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: targetSize, quality: .preview, output: .raster, space: space
        )
        guard let preview = await engine.makeCGImage(previewRequest) else { return false }
        let exportRequest = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: targetSize, quality: .export, output: .raster, space: space
        )
        guard let export = await engine.makeCGImage(exportRequest) else { return false }
        return preview.width == export.width && preview.height == export.height
            && preview.width > 0 && preview.height > 0
    }

    // MARK: - Private rendering helpers (CGImage never escapes)

    private func render(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        targetSize: CGSize,
        engine: any RenderEngining
    ) async -> AutoEvaluatedRender? {
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: targetSize, quality: .preview, output: .raster, space: space
        )
        guard let image = await engine.makeCGImage(request) else { return nil }
        guard let png = Self.pngData(for: image) else { return nil }
        return AutoEvaluatedRender(pngData: png, width: image.width, height: image.height)
    }

    private func maskOverlay(
        source: ImageSource,
        document: EditDocument,
        targetSize: CGSize,
        engine: any RenderEngining
    ) async -> Data? {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        guard let layer = document.localAdjustments.first else { return nil }
        let request = MaskOverlayRequest(
            source: source,
            layers: document.localAdjustments,
            selectedLayerID: layer.id,
            soloLayerID: nil,
            targetSize: PixelDimensions(width: width, height: height),
            quality: .preview,
            style: MaskOverlayStyle(inspection: .colorWash, red: 1, green: 0.2, blue: 0.2)
        )
        guard let image = await engine.makeMaskOverlayImage(request) else { return nil }
        return Self.pngData(for: image)
    }

    struct PixelComparison: Sendable {
        let measurements: AutoEvaluationReport.Measurements
        let diffPNG: Data?
    }

    /// Compare two renders as RGBA8 pixels over their shared extent. Pure and deterministic so
    /// the math is unit-testable without a renderer.
    static func compare(base: AutoEvaluatedRender, proposed: AutoEvaluatedRender) -> PixelComparison {
        guard let basePixels = Self.rgba8Pixels(pngData: base.pngData),
              let proposedPixels = Self.rgba8Pixels(pngData: proposed.pngData),
              basePixels.width > 0, basePixels.height > 0,
              basePixels.width == proposedPixels.width,
              basePixels.height == proposedPixels.height
        else {
            return PixelComparison(
                measurements: AutoEvaluationReport.Measurements(
                    meanAbsoluteDifference: 0, maxDifference: 0, changedPixelFraction: 0
                ),
                diffPNG: nil
            )
        }
        let count = basePixels.width * basePixels.height
        var total: Double = 0
        var maxDiff: Double = 0
        var changed = 0
        var diffBytes = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            var pixelMax: Double = 0
            for channel in 0..<3 {
                let a = Double(basePixels.bytes[i * 4 + channel]) / 255
                let b = Double(proposedPixels.bytes[i * 4 + channel]) / 255
                let d = abs(a - b)
                total += d
                maxDiff = max(maxDiff, d)
                pixelMax = max(pixelMax, d)
                diffBytes[i * 4 + channel] = UInt8((d * 255).rounded())
            }
            diffBytes[i * 4 + 3] = 255
            if pixelMax > 1 / 255 { changed += 1 }
        }
        let measurements = AutoEvaluationReport.Measurements(
            meanAbsoluteDifference: total / Double(count * 3),
            maxDifference: maxDiff,
            changedPixelFraction: Double(changed) / Double(count)
        )
        return PixelComparison(measurements: measurements, diffPNG: Self.pngData(
            width: basePixels.width, height: basePixels.height, rgba8: diffBytes
        ))
    }

    struct RGBA8Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    static func rgba8Pixels(pngData: Data) -> RGBA8Pixels? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return rgba8Pixels(image: image)
    }

    static func rgba8Pixels(image: CGImage) -> RGBA8Pixels? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBA8Pixels(bytes: bytes, width: width, height: height)
    }

    static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func pngData(width: Int, height: Int, rgba8: [UInt8]) -> Data? {
        guard width > 0, height > 0, rgba8.count == width * height * 4 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let bytes = rgba8
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return nil }
        _ = bytes
        return pngData(for: image)
    }

    // MARK: - Artifact output (outside the committed tree)

    /// Write an evaluation to `artifacts/auto-evaluation/<fixtureID>/`: unchanged/proposed/
    /// complete/diff PNGs, available mask overlays, `report.json`, and a human-readable
    /// `report.md`. Returns the directory URL.
    @discardableResult
    func writeArtifact(
        _ evaluation: Evaluation,
        fixtureID: String,
        directory: URL
    ) throws -> URL {
        let outputDir = directory.appendingPathComponent(fixtureID, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        if let base = evaluation.base {
            try base.pngData.write(to: outputDir.appendingPathComponent("unchanged.png"))
        }
        if let proposed = evaluation.proposed {
            try proposed.pngData.write(to: outputDir.appendingPathComponent("proposed.png"))
        }
        if let complete = evaluation.complete {
            try complete.pngData.write(to: outputDir.appendingPathComponent("complete.png"))
        }
        if let diff = evaluation.diffPNG {
            try diff.write(to: outputDir.appendingPathComponent("diff.png"))
        }
        for (role, png) in evaluation.maskOverlays {
            try png.write(to: outputDir.appendingPathComponent("mask-overlay-\(role).png"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evaluation.report).write(
            to: outputDir.appendingPathComponent("report.json")
        )
        try evaluation.report.markdown().write(
            to: outputDir.appendingPathComponent("report.md"),
            atomically: true, encoding: .utf8
        )
        return outputDir
    }
}
