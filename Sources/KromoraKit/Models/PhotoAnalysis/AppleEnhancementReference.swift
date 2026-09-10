import CoreGraphics
import CoreImage
import Foundation

/// Core Image automatic-enhancement reference fitting (KRMA-346).
///
/// Apple ships an on-device automatic enhancement analysis with Core Image
/// (`CIImage.autoAdjustmentFilters()`): given an image it suggests a small stack of
/// value-configured filters — typically `CIToneCurve`, `CIHighlightShadowAdjust`, and
/// `CIVibrance` (probed on the macOS 26 SDK; red-eye/face filters appear only when faces are
/// detected and crop/level filters only when explicitly opted in). This file treats that Apple
/// output as a **reference proposal, not authoritative truth and not a persisted filter chain**:
///
/// - `AppleAutoAdjustmentDescribing` / `CIAutoAdjustmentDescriptor` is the sole Core Image
///   boundary. `CIImage`/`CIFilter`/`CIContext` never escape it: the descriptor consumes
///   `RenderedPixelSamples` (a `Sendable` value, already the KRMA-343 currency) and returns
///   `AppleReferenceRender` — value-only suggested effects plus value-only reference pixels.
///   No network, no third-party dependency, no image object crossing into policy.
/// - `AppleReferenceFitter` is pure and deterministic. It compares the reference render against
///   the baseline render and maps the measured delta onto Kromora's existing exposure/tone/
///   color/white-balance controls through the same ranges and photographic directions the
///   coordinated policy (KRMA-345) uses. Unsupported effects (red-eye correction, face balance,
///   crop, …) are omitted and reported, never approximated.
/// - `AppleEnhancementReferenceAdapter` orchestrates: it renders the **analysis-view** document
///   (`AutoCandidateEvaluation.analysisDocument`, which excludes LUT/grading/grain/decorative
///   vignette) as the fitting baseline, then applies the fitted values onto the **complete**
///   document — so existing Looks/LUTs, grading, curves, mixer, masks, crop, and decorative
///   effects survive byte-for-byte — and returns a bounded value-only proposal with provenance
///   and confidence, or an explicit unavailable result that never blocks native proposals.
///
/// What this ticket does NOT own: candidate selection (KRMA-347), local corrections (KRMA-348),
/// or any claim that the Apple reference is perceptually superior. Confidence is capped for
/// exactly that reason: the reference informs, it does not decide.

// MARK: - Value-only Apple suggestion

/// One Apple enhancement suggestion as a value. `.toneCurve` carries no parameters: a monotonic
/// master curve has no Kromora counterpart in v1 (the policy never synthesizes curves), so its
/// intent is always fitted through the Light sliders via the reference pixels, never stored.
enum AppleSuggestedEffect: Codable, Sendable, Equatable {
    /// `CIVibrance`, `-1…1`. Positive lifts muted color.
    case vibrance(amount: Double)
    /// `CIToneCurve`. Fitted through exposure/highlights/shadows/whites/blacks/contrast.
    case toneCurve
    /// `CIHighlightShadowAdjust`. Amounts are `0…1` as reported by the filter.
    case highlightShadow(highlight: Double, shadow: Double)
    /// Anything Kromora has no control for (red-eye, face balance, crop, …). Omitted and
    /// reported — never approximated, never persisted.
    case unsupported(name: String)

    /// True when Kromora can express the intent through an editable control.
    var isSupported: Bool {
        switch self {
        case .vibrance, .toneCurve, .highlightShadow: return true
        case .unsupported: return false
        }
    }

    var filterName: String {
        switch self {
        case .vibrance: return "CIVibrance"
        case .toneCurve: return "CIToneCurve"
        case .highlightShadow: return "CIHighlightShadowAdjust"
        case .unsupported(let name): return name
        }
    }
}

/// The Apple suggestion for one baseline render: the filter names in application order plus the
/// value-only effect for each. Empty `effects` means Apple suggested nothing for this image —
/// a normal outcome, reported as `.noEnhancementSuggested`, not a failure.
struct AppleReferenceIntent: Codable, Sendable, Equatable {
    let effects: [AppleSuggestedEffect]

    init(effects: [AppleSuggestedEffect] = []) {
        self.effects = effects
    }

    var filterNames: [String] { effects.map(\.filterName) }

    var supportedEffects: [AppleSuggestedEffect] { effects.filter(\.isSupported) }

    var omittedNames: [String] {
        effects.compactMap {
            if case .unsupported(let name) = $0 { return name }
            return nil
        }
    }

    var isEmpty: Bool { effects.isEmpty }
}

/// Value-only Apple reference: what Apple suggested plus the reference pixels with the
/// suggestion applied. `samples` is `nil` when the reference could not be rendered even though
/// filters were suggested — the fitter then falls back to filter-intent mapping for the
/// directly mappable effects and omits the rest.
struct AppleReferenceRender: Sendable, Equatable {
    let intent: AppleReferenceIntent
    let samples: RenderedPixelSamples?

    init(intent: AppleReferenceIntent, samples: RenderedPixelSamples? = nil) {
        self.intent = intent
        self.samples = samples
    }
}

// MARK: - Core Image boundary

/// The Core Image automatic-enhancement seam. Non-throwing by contract: implementations report
/// `nil` when the suggestion cannot be produced rather than failing the Auto pipeline that
/// requested it. The single input/output currency is `RenderedPixelSamples`, so every consumer
/// stays unit-testable without image objects and no `CIImage`/`CIFilter` ever crosses into
/// policy, persistence, or the user's edit.
protocol AppleAutoAdjustmentDescribing: Sendable {
    /// Apple's suggested enhancement for `samples`, with the suggestion applied as reference
    /// pixels when renderable. `nil` means unavailable (malformed image or Core Image failure);
    /// an empty intent with `nil` samples means Apple suggested no enhancement.
    func reference(for samples: RenderedPixelSamples) -> AppleReferenceRender?
}

/// Production descriptor around `CIImage.autoAdjustmentFilters()`.
///
/// All Core Image objects are method-local: the `CIImage` is built from the sample bytes, the
/// suggested filters are chained onto it, and a locally created `CIContext` reads the reference
/// pixels back. Nothing non-`Sendable` is stored, so the struct itself is `Sendable` even though
/// its method body drives Core Image — the same confinement shape as `VisionSceneClassifier`.
struct CIAutoAdjustmentDescriptor: AppleAutoAdjustmentDescribing {
    init() {}

    func reference(for samples: RenderedPixelSamples) -> AppleReferenceRender? {
        guard let base = Self.ciImage(from: samples) else { return nil }
        let filters = base.autoAdjustmentFilters()
        let intent = AppleReferenceIntent(effects: filters.map {
            Self.effect(forFilterName: $0.name, values: Self.numericInputs(of: $0))
        })
        guard !intent.isEmpty else {
            return AppleReferenceRender(intent: intent, samples: nil)
        }
        let referenceSamples = Self.apply(filters: filters, to: base, space: samples.space)
        return AppleReferenceRender(intent: intent, samples: referenceSamples)
    }

    /// Pure filter-name → value-effect mapping, so the intent vocabulary is pinned by unit tests
    /// without rendering. Unknown filters are always `.unsupported`, never guessed at.
    static func effect(
        forFilterName name: String, values: [String: Double]
    ) -> AppleSuggestedEffect {
        switch name {
        case "CIVibrance":
            return .vibrance(amount: Self.finite(values["inputAmount"] ?? 0))
        case "CIToneCurve":
            return .toneCurve
        case "CIHighlightShadowAdjust":
            return .highlightShadow(
                highlight: Self.finite(values["inputHighlightAmount"] ?? 1, fallback: 1),
                shadow: Self.finite(values["inputShadowAmount"] ?? 0)
            )
        default:
            return .unsupported(name: name)
        }
    }

    private static func finite(_ value: Double, fallback: Double = 0) -> Double {
        value.isFinite ? value : fallback
    }

    // MARK: - Private Core Image plumbing (never escapes this type)

    private static func numericInputs(of filter: CIFilter) -> [String: Double] {
        var values: [String: Double] = [:]
        for key in filter.inputKeys where key != kCIInputImageKey as String {
            if let number = filter.value(forKey: key) as? NSNumber {
                let value = number.doubleValue
                if value.isFinite { values[key] = value }
            }
        }
        return values
    }

    private static func ciImage(from samples: RenderedPixelSamples) -> CIImage? {
        guard !samples.isEmpty else { return nil }
        let colorSpace = samples.space.cgColorSpace
        guard let provider = CGDataProvider(data: Data(samples.bytes) as CFData),
              let cgImage = CGImage(
                  width: samples.width, height: samples.height,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: samples.width * 4, space: colorSpace,
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider, decode: nil,
                  shouldInterpolate: false, intent: .defaultIntent
              )
        else { return nil }
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    private static func apply(
        filters: [CIFilter], to base: CIImage, space: WorkingSpace
    ) -> RenderedPixelSamples? {
        var image = base
        for filter in filters {
            filter.setValue(image, forKey: kCIInputImageKey)
            // A filter that cannot produce output (missing face features, degenerate input) is
            // skipped with its input carried forward; it is already recorded in the intent, and
            // the fitter reports unsupported effects as omitted.
            guard let output = filter.outputImage else { continue }
            image = output
        }
        guard image.extent.width.isFinite, image.extent.height.isFinite,
              image.extent.width > 0, image.extent.height > 0
        else { return nil }
        let context = CIContext(options: [.workingColorSpace: space.cgColorSpace])
        guard let rendered = context.createCGImage(image, from: image.extent) else { return nil }
        let width = rendered.width
        let height = rendered.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let captured = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard let baseAddress = pointer.baseAddress,
                  let outputContext = CGContext(
                      data: baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            outputContext.draw(rendered, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard captured else { return nil }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: space)
    }
}

// MARK: - Proposal and result values

/// Where the fitted values came from and what was left out. Persisted with the proposal so a
/// later review can tell "Apple-informed daylight lift" from "native policy only" without pixels.
struct AppleReferenceProvenance: Codable, Sendable, Equatable {
    /// The suggestion was fitted by comparing reference pixels (`renderCompare`) or, when the
    /// reference could not be rendered, by mapping directly expressible filter inputs
    /// (`filterIntent`).
    enum FitMethod: String, Codable, Sendable, Equatable {
        case renderCompare
        case filterIntent
    }

    let algorithmVersion: Int
    let sourceKind: AutoSourceKind
    let space: WorkingSpace
    /// Apple filter names in application order — provenance only, never applied to the edit.
    let filterNames: [String]
    /// Suggested or measured effects Kromora has no control for, with the reason each was left out.
    let omittedEffects: [String]
    let fitMethod: FitMethod
    /// Mean per-channel absolute baseline-vs-reference difference, `0…1`. Zero means Apple would
    /// leave the analysis view untouched.
    let referenceStrength: Double
    /// Hash of the analysis-view document actually fitted, and of the complete document the
    /// fitted values were applied onto. Differing hashes are the normal case (the complete edit
    /// keeps its finish); equal hashes mean the complete edit already was the analysis view.
    let analysisDocumentHash: String
    let completeDocumentHash: String

    init(
        algorithmVersion: Int = AppleEnhancementReferenceAdapter.algorithmVersion,
        sourceKind: AutoSourceKind,
        space: WorkingSpace,
        filterNames: [String] = [],
        omittedEffects: [String] = [],
        fitMethod: FitMethod,
        referenceStrength: Double = 0,
        analysisDocumentHash: String = "",
        completeDocumentHash: String = ""
    ) {
        self.algorithmVersion = algorithmVersion
        self.sourceKind = sourceKind
        self.space = space
        self.filterNames = filterNames
        self.omittedEffects = omittedEffects
        self.fitMethod = fitMethod
        self.referenceStrength = Self.unit(referenceStrength)
        self.analysisDocumentHash = analysisDocumentHash
        self.completeDocumentHash = completeDocumentHash
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// One Apple-informed, fully editable proposal: the complete document with fitted values plus
/// exactly what changed and why. Carries no `CIFilter`, no `CIImage`, no filter chain — only
/// Kromora control values through the existing mappings.
struct AppleReferenceProposal: Codable, Sendable, Equatable {
    let algorithmVersion: Int
    let document: EditDocument
    let changes: [AutoPolicyControl: AutoControlChange]
    /// Capped below 1 by construction: the Apple output is a reference, not a verdict.
    let confidence: Float
    let provenance: AppleReferenceProvenance
    /// Fraction of the suggested movement left unapplied by bounds and user-edit restraint,
    /// `0…1`. Bounded, never estimated from pixels the fitter did not measure.
    let residualError: Double
    let notes: String

    init(
        algorithmVersion: Int = AppleEnhancementReferenceAdapter.algorithmVersion,
        document: EditDocument,
        changes: [AutoControlChange],
        confidence: Float,
        provenance: AppleReferenceProvenance,
        residualError: Double,
        notes: String = ""
    ) {
        self.algorithmVersion = algorithmVersion
        self.document = document
        var mapped: [AutoPolicyControl: AutoControlChange] = [:]
        for change in changes { mapped[change.control] = change }
        self.changes = mapped
        self.confidence = Self.unit(confidence)
        self.provenance = provenance
        self.residualError = Self.unitDouble(residualError)
        self.notes = notes
    }

    var isNoOp: Bool { changes.isEmpty }

    var changedControls: [AutoPolicyControl] {
        changes.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func unitDouble(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Machine-readable unavailable reasons. Every failure degrades to "no Apple reference" so the
/// coordinator falls through to native proposals; none of them blocks Auto.
enum AppleReferenceUnavailableCode: String, Codable, Sendable, Equatable, CaseIterable {
    /// The OS/runtime combination does not support Core Image automatic enhancement.
    case unsupportedOS
    /// The analysis-view edit could not be rendered for fitting.
    case renderUnavailable
    /// The source has no measurable extent, or the rendered samples are malformed.
    case malformedImage
    /// Core Image produced no suggestion object at all, or the suggestion could not be read.
    case coreImageFailure
    /// Apple suggested no enhancement for this image — a normal outcome, not an error.
    case noEnhancementSuggested
    /// Apple suggested filters, but nothing maps onto a Kromora control.
    case noActionableDelta
    /// The request was cancelled.
    case cancelled
}

/// The adapter outcome: either an editable proposal or an explicit unavailable result.
enum AppleReferenceResult: Sendable, Equatable {
    case proposed(AppleReferenceProposal)
    case unavailable(code: AppleReferenceUnavailableCode, message: String)

    var proposal: AppleReferenceProposal? {
        if case .proposed(let proposal) = self { return proposal }
        return nil
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

// MARK: - Pure fitter

/// Pure deterministic fitting of an Apple reference onto Kromora controls (no renderer, no
/// Core Image, no Vision). The primary path compares reference pixels against baseline pixels
/// and maps the measured delta through the existing control ranges; the fallback path maps
/// directly expressible filter inputs when the reference could not be rendered.
///
/// White-balance direction is pinned to the policy's (KRMA-345): `CIRAWFilter`
/// neutral-temperature runs photographic (raising warms) while the standard-image
/// `temperatureTint` node is inverted about D65 (raising cools). Fitting *reproduces* Apple's
/// shift rather than correcting a cast, so the signs run opposite to the policy's — a warmer
/// Apple reference *raises* the RAW temperature and *lowers* the standard temperature.
enum AppleReferenceFitter {
    struct Fit: Sendable, Equatable {
        var changes: [AutoControlChange]
        var omitted: [String]
        var residualError: Double
        var confidence: Float
        var strength: Double
        var method: AppleReferenceProvenance.FitMethod
    }

    /// Fit `reference` (baseline + Apple suggestion) onto `current`'s controls.
    ///
    /// - Parameters:
    ///   - baseline: analysis-view render the suggestion was derived from.
    ///   - reference: Apple's suggestion applied, or `nil` when unrenderable (intent-only path).
    ///   - intent: the value-only Apple suggestion, for provenance and the intent-only path.
    ///   - current: the document whose controls move. Callers pass the *complete* edit so the
    ///     finish survives; the returned changes apply onto it.
    ///   - sourceKind: selects the RAW vs. standard white-balance mapping.
    ///   - scene/signalConfidence: optional gating evidence. `nil` means "no evidence", which
    ///     only gates the frame-mixed white-balance veto (via the measured hue facts), never
    ///     the tone fit.
    ///   - asShotTemperature/asShotTint: RAW base values when the document has none yet.
    static func fit(
        baseline: RenderedPixelSamples,
        reference: RenderedPixelSamples?,
        intent: AppleReferenceIntent,
        current: EditDocument,
        sourceKind: AutoSourceKind,
        scene: SceneCharacteristics? = nil,
        signalConfidence: AutoSignalConfidence? = nil,
        asShotTemperature: Double? = nil,
        asShotTint: Double? = nil
    ) -> Fit {
        if let reference, !reference.isEmpty, !baseline.isEmpty {
            return fitByRenderCompare(
                baseline: baseline, reference: reference, intent: intent, current: current,
                sourceKind: sourceKind, scene: scene, signalConfidence: signalConfidence,
                asShotTemperature: asShotTemperature, asShotTint: asShotTint
            )
        }
        return fitByFilterIntent(
            intent: intent, current: current, sourceKind: sourceKind,
            signalConfidence: signalConfidence,
            asShotTemperature: asShotTemperature, asShotTint: asShotTint
        )
    }

    // MARK: Render-compare path

    private static func fitByRenderCompare(
        baseline: RenderedPixelSamples,
        reference: RenderedPixelSamples,
        intent: AppleReferenceIntent,
        current: EditDocument,
        sourceKind: AutoSourceKind,
        scene: SceneCharacteristics?,
        signalConfidence: AutoSignalConfidence?,
        asShotTemperature: Double?,
        asShotTint: Double?
    ) -> Fit {
        let baseTone: ToneStatistics
        let refTone: ToneStatistics
        do {
            baseTone = try RenderedPixelAnalyzer.tone(from: baseline).perceptual
            refTone = try RenderedPixelAnalyzer.tone(from: reference).perceptual
        } catch {
            return Fit(
                changes: [], omitted: ["reference-tone-unmeasurable"],
                residualError: 1, confidence: 0, strength: 0, method: .renderCompare
            )
        }
        let baseColor = RenderedPixelAnalyzer.correlatedColor(from: baseline)
        let refColor = RenderedPixelAnalyzer.correlatedColor(from: reference)
        let strength = meanAbsoluteDifference(baseline, reference)

        var changes: [AutoControlChange] = []
        var omitted: [String] = intent.omittedNames.map { "\($0) (no Kromora control)" }
        // Suggested vs. applied movement in normalized units, for the bounded residual.
        var suggestedTotal = 0.0
        var appliedTotal = 0.0

        func record(
            _ control: AutoPolicyControl,
            suggested: Double,
            currentValue: Double,
            range: ClosedRange<Double>,
            noOpThreshold: Double,
            reason: String,
            evidence: String,
            confidence: Float
        ) {
            guard suggested.isFinite, abs(suggested) >= noOpThreshold else { return }
            suggestedTotal += abs(suggested)
            // User-edit restraint (same rule as the coordinated policy): a control already
            // moved past half its range is left alone; any other non-neutral control moves at
            // half strength toward the fitted value.
            let halfRange = (range.upperBound - range.lowerBound) / 2
            if halfRange > 0, abs(currentValue) > halfRange * 0.5 {
                omitted.append("\(control.rawValue) (user-owned past half range)")
                return
            }
            var delta = suggested
            if currentValue != 0 { delta *= 0.5 }
            let proposed = bounded(currentValue + delta, range)
            let applied = proposed - currentValue
            guard abs(applied) >= noOpThreshold else { return }
            appliedTotal += abs(applied)
            changes.append(AutoControlChange(
                control: control, previous: currentValue, proposed: proposed,
                confidence: confidence, reason: reason, evidence: evidence
            ))
        }

        let toneConfidence = fitConfidence(signalConfidence: signalConfidence, kind: .tone)
        let colorConfidence = fitConfidence(signalConfidence: signalConfidence, kind: .color)

        // Exposure reproduces the median placement Apple chose, in the policy's ±1.25 EV envelope.
        let baseMedian = max(Double(baseTone.p50), 0.03)
        let refMedian = max(Double(refTone.p50), 0.03)
        let exposureDelta = bounded(log2(refMedian / baseMedian), -1.25...1.25)
        if exposureDelta.isFinite, abs(exposureDelta) >= 0.05 {
            suggestedTotal += abs(exposureDelta)
            let exposureRange = LightAdjustments.exposureRange
            let halfRange = (exposureRange.upperBound - exposureRange.lowerBound) / 2
            if abs(current.light.exposure) > halfRange * 0.5 {
                omitted.append("exposure (user-owned past half range)")
            } else {
                var delta = exposureDelta
                if current.light.exposure != 0 { delta *= 0.5 }
                let proposed = bounded(current.light.exposure + delta, exposureRange)
                if abs(proposed - current.light.exposure) >= 0.05 {
                    appliedTotal += abs(proposed - current.light.exposure)
                    changes.append(AutoControlChange(
                        control: .exposure, previous: current.light.exposure, proposed: proposed,
                        confidence: toneConfidence,
                        reason: "Reproduces the Apple reference median placement.",
                        evidence: "baseP50=\(format(baseTone.p50)) refP50=\(format(refTone.p50))"
                    ))
                }
            }
        }

        // Tails correct the residual Apple left after its own global placement, damped the same
        // way the coordinated policy damps tails after exposure — overlapping sliders must not
        // double-apply one Apple curve move.
        let residualScale = max(0.5, 1 - abs(exposureDelta) * 0.25)
        let highlightDelta = (Double(refTone.p95) - Double(baseTone.p95)) * 100 * Double(residualScale)
        record(
            .highlights, suggested: highlightDelta, currentValue: current.light.highlights,
            range: LightAdjustments.highlightsRange, noOpThreshold: 1,
            reason: "Reproduces the Apple reference bright-tail placement.",
            evidence: "baseP95=\(format(baseTone.p95)) refP95=\(format(refTone.p95))",
            confidence: toneConfidence
        )
        let shadowDelta = (Double(refTone.p10) - Double(baseTone.p10)) * 100 * Double(residualScale)
        record(
            .shadows, suggested: shadowDelta, currentValue: current.light.shadows,
            range: LightAdjustments.shadowsRange, noOpThreshold: 1,
            reason: "Reproduces the Apple reference dark-tail placement.",
            evidence: "baseP10=\(format(baseTone.p10)) refP10=\(format(refTone.p10))",
            confidence: toneConfidence
        )
        let whiteDelta = (Double(refTone.p95) - Double(baseTone.p95)) * 62 * Double(residualScale)
        record(
            .whites, suggested: whiteDelta, currentValue: current.light.whites,
            range: LightAdjustments.whitesRange, noOpThreshold: 1,
            reason: "Reproduces the Apple reference white-point placement.",
            evidence: "baseP95=\(format(baseTone.p95)) refP95=\(format(refTone.p95))",
            confidence: toneConfidence
        )
        let blackDelta = (Double(refTone.p05) - Double(baseTone.p05)) * 48 * Double(residualScale)
        record(
            .blacks, suggested: blackDelta, currentValue: current.light.blacks,
            range: LightAdjustments.blacksRange, noOpThreshold: 1,
            reason: "Reproduces the Apple reference black-point placement.",
            evidence: "baseP05=\(format(baseTone.p05)) refP05=\(format(refTone.p05))",
            confidence: toneConfidence
        )
        let baseSpread = Double(baseTone.p95 - baseTone.p05)
        let refSpread = Double(refTone.p95 - refTone.p05)
        let contrastDelta = (refSpread - baseSpread) * 46 * Double(residualScale)
        record(
            .contrast, suggested: contrastDelta, currentValue: current.light.contrast,
            range: LightAdjustments.contrastRange, noOpThreshold: 1,
            reason: "Reproduces the Apple reference dynamic-range placement.",
            evidence: "baseSpread=\(format(baseTone.p95 - baseTone.p05)) refSpread=\(format(refTone.p95 - refTone.p05))",
            confidence: toneConfidence
        )

        // White balance reproduces Apple's neutral-axis shift with the correct per-path
        // direction. Vetoed when the frame is mixed or the scene makes a "correction" more
        // likely to erase intent than to reproduce Apple (same vetoes as the policy).
        let sceneValue = scene ?? SceneCharacteristics()
        let warmDelta = Double((refColor.meanRGB.x - refColor.meanRGB.z)
            - (baseColor.meanRGB.x - baseColor.meanRGB.z))
        let greenDelta = Double((refColor.meanRGB.y - (refColor.meanRGB.x + refColor.meanRGB.z) / 2)
            - (baseColor.meanRGB.y - (baseColor.meanRGB.x + baseColor.meanRGB.z) / 2))
        let wbVetoed = baseColor.isMixed
            || sceneValue.monochromeLikelihood > 0.6
            || sceneValue.mixedLightLikelihood > 0.5
        if wbVetoed, abs(warmDelta) > 0.02 || abs(greenDelta) > 0.015 {
            omitted.append("white-balance (mixed/monochrome evidence)")
        } else if !wbVetoed {
            // Reproduction signs (opposite to the correcting policy): a warmer Apple reference
            // raises the photographic RAW temperature and lowers the inverted standard one.
            let rawTempDelta = bounded(warmDelta * 6000, -2500...2500)
            let standardTempDelta = bounded(-warmDelta * 6000, -1500...1500)
            let tintDelta = bounded(greenDelta * 300, -30...30)
            switch sourceKind {
            case .raw:
                let baseTemp = current.rawDevelop.neutralTemperature ?? asShotTemperature
                let baseTint = current.rawDevelop.neutralTint ?? asShotTint ?? 0
                if let baseTemp, abs(rawTempDelta) >= 50 {
                    recordWBRaw(
                        &changes, suggestedTotal: &suggestedTotal,
                        appliedTotal: &appliedTotal,
                        control: .temperature, suggested: rawTempDelta, base: baseTemp,
                        proposed: bounded(baseTemp + rawTempDelta, 2000...50000),
                        reason: "Reproduces the Apple reference neutral-axis shift (RAW).",
                        evidence: "warmDelta=\(format(Float(warmDelta)))",
                        confidence: colorConfidence
                    )
                }
                if abs(tintDelta) >= 2 {
                    recordWBRaw(
                        &changes, suggestedTotal: &suggestedTotal,
                        appliedTotal: &appliedTotal,
                        control: .tint, suggested: tintDelta, base: baseTint,
                        proposed: bounded(baseTint + tintDelta, -150...150),
                        reason: "Reproduces the Apple reference tint shift (RAW).",
                        evidence: "greenDelta=\(format(Float(greenDelta)))",
                        confidence: colorConfidence
                    )
                }
                if baseTemp == nil, abs(rawTempDelta) >= 50 {
                    omitted.append("temperature (no RAW base temperature)")
                }
            case .standard:
                let baseTemp = AdjustmentControl.temperature.value(in: current.adjustments)
                let baseTint = AdjustmentControl.tint.value(in: current.adjustments)
                if abs(standardTempDelta) >= 50 {
                    recordWBStandard(
                        &changes, suggestedTotal: &suggestedTotal, appliedTotal: &appliedTotal,
                        control: .temperature, suggested: standardTempDelta, base: baseTemp,
                        proposed: bounded(baseTemp + standardTempDelta, 2000...11000),
                        reason: "Reproduces the Apple reference neutral-axis shift (standard).",
                        evidence: "warmDelta=\(format(Float(warmDelta)))",
                        confidence: colorConfidence
                    )
                }
                if abs(tintDelta) >= 2 {
                    recordWBStandard(
                        &changes, suggestedTotal: &suggestedTotal, appliedTotal: &appliedTotal,
                        control: .tint, suggested: tintDelta, base: baseTint,
                        proposed: bounded(baseTint + tintDelta, -150...150),
                        reason: "Reproduces the Apple reference tint shift (standard).",
                        evidence: "greenDelta=\(format(Float(greenDelta)))",
                        confidence: colorConfidence
                    )
                }
            }
        }

        // Color reproduces Apple's saturation shift, restrained like the policy. Dehaze, mixer,
        // grading, and curves are never fitted from an Apple reference: Core Image automatic
        // enhancement does not dehaze, and the master curve stays unsynthesized in v1.
        let colorVetoed = baseColor.isMixed
            || sceneValue.monochromeLikelihood > 0.5
            || sceneValue.sunsetWarmLikelihood > 0.6
            || sceneValue.nightLikelihood > 0.6
        if colorVetoed {
            if abs(Double(refColor.saturationMedian) - Double(baseColor.saturationMedian)) > 0.05 {
                omitted.append("color (intent-preserving scene)")
            }
        } else {
            let saturationDelta = (Double(refColor.saturationMedian) - Double(baseColor.saturationMedian)) * 100
            record(
                .saturation, suggested: saturationDelta, currentValue: current.color.saturation,
                range: ColorAdjustments.saturationRange, noOpThreshold: 2,
                reason: "Reproduces the Apple reference saturation shift.",
                evidence: "baseSat=\(format(baseColor.saturationMedian)) refSat=\(format(refColor.saturationMedian))",
                confidence: colorConfidence
            )
            let vibranceDelta = (Double(refColor.saturationMedian) - Double(baseColor.saturationMedian)) * 60
            let vibranceRange = 0.0...18.0
            if vibranceDelta.isFinite, abs(vibranceDelta) >= 2, current.color.vibrance < 18 {
                suggestedTotal += abs(vibranceDelta)
                let proposed = bounded(current.color.vibrance + vibranceDelta, vibranceRange)
                if abs(proposed - current.color.vibrance) >= 2 {
                    appliedTotal += abs(proposed - current.color.vibrance)
                    changes.append(AutoControlChange(
                        control: .vibrance, previous: current.color.vibrance, proposed: proposed,
                        confidence: colorConfidence,
                        reason: "Reproduces the Apple reference muted-color lift.",
                        evidence: "baseSat=\(format(baseColor.saturationMedian)) refSat=\(format(refColor.saturationMedian))",
                    ))
                }
            }
        }

        let residual = suggestedTotal > 0
            ? bounded(1 - appliedTotal / suggestedTotal, 0...1)
            : (omitted.isEmpty ? 0 : 1)
        let confidence = confidenceFor(
            strength: strength, omittedCount: omitted.count,
            signalConfidence: signalConfidence
        )
        return Fit(
            changes: changes, omitted: omitted, residualError: residual,
            confidence: confidence, strength: strength, method: .renderCompare
        )
    }

    // MARK: Intent-only path

    /// Fallback when Apple suggested filters but the reference could not be rendered. Only
    /// directly expressible filter inputs map; a tone curve without pixels is omitted (there is
    /// no curve control to hold it), and confidence stays low — intent without evidence.
    private static func fitByFilterIntent(
        intent: AppleReferenceIntent,
        current: EditDocument,
        sourceKind: AutoSourceKind,
        signalConfidence: AutoSignalConfidence?,
        asShotTemperature: Double?,
        asShotTint: Double?
    ) -> Fit {
        var changes: [AutoControlChange] = []
        var omitted: [String] = intent.omittedNames.map { "\($0) (no Kromora control)" }
        var suggestedTotal = 0.0
        var appliedTotal = 0.0
        let confidenceScale: Float = signalConfidence.map { 0.5 + 0.5 * $0.overall } ?? 0.75

        for effect in intent.supportedEffects {
            switch effect {
            case .vibrance(let amount):
                let suggested = bounded(amount * 100, -100...100)
                guard abs(suggested) >= 2 else { continue }
                suggestedTotal += abs(suggested)
                let proposed = bounded(
                    current.color.vibrance + suggested, ColorAdjustments.vibranceRange
                )
                if abs(proposed - current.color.vibrance) >= 2 {
                    appliedTotal += abs(proposed - current.color.vibrance)
                    changes.append(AutoControlChange(
                        control: .vibrance, previous: current.color.vibrance,
                        proposed: proposed, confidence: 0.4 * confidenceScale,
                        reason: "Apple CIVibrance intent, applied without reference pixels.",
                        evidence: "inputAmount=\(format(Float(amount)))"
                    ))
                }
            case .highlightShadow(let highlight, let shadow):
                let shadowSuggested = bounded(shadow * 40, -8...38)
                if abs(shadowSuggested) >= 1 {
                    suggestedTotal += abs(shadowSuggested)
                    let proposed = bounded(
                        current.light.shadows + shadowSuggested, LightAdjustments.shadowsRange
                    )
                    if abs(proposed - current.light.shadows) >= 1 {
                        appliedTotal += abs(proposed - current.light.shadows)
                        changes.append(AutoControlChange(
                            control: .shadows, previous: current.light.shadows,
                            proposed: proposed, confidence: 0.4 * confidenceScale,
                            reason: "Apple shadow-lift intent, applied without reference pixels.",
                            evidence: "inputShadowAmount=\(format(Float(shadow)))"
                        ))
                    }
                }
                let highlightSuggested = bounded((highlight - 1) * 40, -38...8)
                if abs(highlightSuggested) >= 1 {
                    suggestedTotal += abs(highlightSuggested)
                    let proposed = bounded(
                        current.light.highlights + highlightSuggested,
                        LightAdjustments.highlightsRange
                    )
                    if abs(proposed - current.light.highlights) >= 1 {
                        appliedTotal += abs(proposed - current.light.highlights)
                        changes.append(AutoControlChange(
                            control: .highlights, previous: current.light.highlights,
                            proposed: proposed, confidence: 0.4 * confidenceScale,
                            reason: "Apple highlight intent, applied without reference pixels.",
                            evidence: "inputHighlightAmount=\(format(Float(highlight)))"
                        ))
                    }
                }
            case .toneCurve:
                omitted.append("tone-curve (needs reference pixels)")
            case .unsupported:
                break // Already recorded in `omitted` above.
            }
        }

        let residual = suggestedTotal > 0
            ? bounded(1 - appliedTotal / suggestedTotal, 0...1)
            : (omitted.isEmpty ? 0 : 1)
        return Fit(
            changes: changes, omitted: omitted, residualError: residual,
            confidence: changes.isEmpty ? 0 : 0.4 * confidenceScale,
            strength: 0, method: .filterIntent
        )
    }

    // MARK: - Helpers

    private enum FitSignal { case tone, color }

    private static func fitConfidence(
        signalConfidence: AutoSignalConfidence?, kind: FitSignal
    ) -> Float {
        let base: Float
        switch kind {
        case .tone: base = signalConfidence?.globalTone ?? 0.7
        case .color: base = signalConfidence?.colorNeutral ?? 0.7
        }
        // The reference informs but never decides: cap below 1 even at full signal confidence.
        return min(max(base, 0), 1) * 0.75
    }

    /// Reference-strength confidence: a near-identical reference carries no information, a
    /// strong one is informative but still capped — Apple is a reference, not a verdict.
    /// Omitted effects reduce confidence; missing signals scale it without erasing the fit.
    static func confidenceFor(
        strength: Double, omittedCount: Int, signalConfidence: AutoSignalConfidence?
    ) -> Float {
        guard strength.isFinite, strength >= 0.005 else { return 0.1 }
        var confidence = min(0.75, 0.35 + strength * 8)
        confidence -= Double(min(omittedCount, 6)) * 0.05
        if let signalConfidence {
            confidence *= Double(0.5 + 0.5 * signalConfidence.overall)
        }
        guard confidence.isFinite else { return 0.1 }
        return Float(min(max(confidence, 0.1), 0.75))
    }

    /// Mean per-channel absolute difference over the shared top-left extent, `0…1`. Coarse by
    /// design: it sizes the reference strength for confidence, it never decides a slider.
    static func meanAbsoluteDifference(
        _ baseline: RenderedPixelSamples, _ reference: RenderedPixelSamples
    ) -> Double {
        guard !baseline.isEmpty, !reference.isEmpty else { return 0 }
        let width = min(baseline.width, reference.width)
        let height = min(baseline.height, reference.height)
        guard width > 0, height > 0 else { return 0 }
        var total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let baseOffset = (y * baseline.width + x) * 4
                let refOffset = (y * reference.width + x) * 4
                for channel in 0..<3 {
                    total += abs(
                        Double(baseline.bytes[baseOffset + channel])
                            - Double(reference.bytes[refOffset + channel])
                    ) / 255
                }
            }
        }
        let value = total / Double(width * height * 3)
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func recordWBRaw(
        _ changes: inout [AutoControlChange],
        suggestedTotal: inout Double,
        appliedTotal: inout Double,
        control: AutoPolicyControl,
        suggested: Double,
        base: Double,
        proposed: Double,
        reason: String,
        evidence: String,
        confidence: Float
    ) {
        suggestedTotal += abs(suggested)
        let applied = proposed - base
        guard abs(applied) >= (control == .temperature ? 50 : 2) else { return }
        // The RAW develop pair has no half-range user restraint: an explicit as-shot base is
        // absolute Kelvin, and overriding it by a fitted delta is the whole operation.
        appliedTotal += abs(applied)
        changes.append(AutoControlChange(
            control: control, previous: base, proposed: proposed,
            confidence: confidence, reason: reason, evidence: evidence
        ))
    }

    private static func recordWBStandard(
        _ changes: inout [AutoControlChange],
        suggestedTotal: inout Double,
        appliedTotal: inout Double,
        control: AutoPolicyControl,
        suggested: Double,
        base: Double,
        proposed: Double,
        reason: String,
        evidence: String,
        confidence: Float
    ) {
        suggestedTotal += abs(suggested)
        let applied = proposed - base
        guard abs(applied) >= (control == .temperature ? 50 : 2) else { return }
        appliedTotal += abs(applied)
        changes.append(AutoControlChange(
            control: control, previous: base, proposed: proposed,
            confidence: confidence, reason: reason, evidence: evidence
        ))
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - Adapter

/// Orchestrates one Apple-reference proposal: availability gate, analysis-view baseline render,
/// Core Image suggestion, pure fit, and application onto the complete edit.
///
/// The adapter owns no policy of its own — every number comes from `AppleReferenceFitter` — and
/// it persists nothing: callers receive a value-only `AppleReferenceResult` and decide (in
/// KRMA-347) whether the reference becomes a candidate. Any failure returns an explicit
/// `.unavailable` so native proposals proceed unblocked.
struct AppleEnhancementReferenceAdapter: Sendable {
    static let algorithmVersion = 1
    static let analysisLongEdge = 768

    let engine: any RenderEngining & CurrentEditSampling
    let descriptor: any AppleAutoAdjustmentDescribing
    let space: WorkingSpace
    /// Test seam for the OS/runtime gate. `nil` (production) consults `isSupportedRuntime`.
    let availabilityOverride: Bool?

    init(
        engine: any RenderEngining & CurrentEditSampling,
        descriptor: any AppleAutoAdjustmentDescribing = CIAutoAdjustmentDescriptor(),
        space: WorkingSpace = .sRGB,
        availabilityOverride: Bool? = nil
    ) {
        self.engine = engine
        self.descriptor = descriptor
        self.space = space
        self.availabilityOverride = availabilityOverride
    }

    /// Core Image automatic enhancement has shipped since OS X 10.8 / iOS 5, so on the macOS 14
    /// deployment target the gate is always open in practice. It stays explicit — with an
    /// injectable override — because the ticket requires an unavailable path on unsupported
    /// OS/runtime combinations, and an unconditional `true` cannot be tested.
    static var isSupportedRuntime: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    var isAvailable: Bool {
        availabilityOverride ?? Self.isSupportedRuntime
    }

    /// Produce one Apple-informed proposal for `document` over `source`.
    ///
    /// The fitting baseline is the analysis view (LUT/grading/grain/decorative vignette
    /// excluded); the fitted values apply onto `document` unchanged otherwise, so the complete
    /// edit — Looks, grading, curves, mixer, masks, crop, decorative effects — is restored for
    /// final evaluation. `lut` selects the active Look for the baseline render.
    func referenceProposal(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT? = nil,
        sourceKind: AutoSourceKind,
        scene: SceneCharacteristics? = nil,
        signalConfidence: AutoSignalConfidence? = nil,
        asShotTemperature: Double? = nil,
        asShotTint: Double? = nil
    ) async -> AppleReferenceResult {
        guard isAvailable else {
            return .unavailable(
                code: .unsupportedOS,
                message: "Core Image automatic enhancement is unavailable on this OS/runtime."
            )
        }
        guard source.nativeExtent.width >= 1, source.nativeExtent.height >= 1,
              source.nativeExtent.width.isFinite, source.nativeExtent.height.isFinite
        else {
            return .unavailable(code: .malformedImage, message: "The source has no measurable extent.")
        }
        if Task.isCancelled {
            return .unavailable(code: .cancelled, message: "The reference request was cancelled.")
        }

        let analysisDocument = AutoCandidateEvaluation.analysisDocument(from: document)
        guard let baseline = await engine.renderedSamples(
            source: source, document: analysisDocument, lut: lut,
            targetLongEdge: Self.analysisLongEdge, space: space
        ), !baseline.isEmpty else {
            return .unavailable(
                code: .renderUnavailable,
                message: "The analysis-view edit could not be rendered for fitting."
            )
        }
        if Task.isCancelled {
            return .unavailable(code: .cancelled, message: "The reference request was cancelled.")
        }
        guard let reference = descriptor.reference(for: baseline) else {
            return .unavailable(
                code: .coreImageFailure,
                message: "Core Image returned no enhancement suggestion."
            )
        }
        if reference.intent.isEmpty, reference.samples == nil {
            return .unavailable(
                code: .noEnhancementSuggested,
                message: "Core Image suggested no enhancement for this image."
            )
        }

        let fit = AppleReferenceFitter.fit(
            baseline: baseline, reference: reference.samples, intent: reference.intent,
            current: document, sourceKind: sourceKind, scene: scene,
            signalConfidence: signalConfidence, asShotTemperature: asShotTemperature,
            asShotTint: asShotTint
        )
        guard !fit.changes.isEmpty else {
            let detail = fit.omitted.isEmpty
                ? "the reference matches the current edit"
                : "omitted: \(fit.omitted.joined(separator: "; "))"
            return .unavailable(
                code: .noActionableDelta,
                message: "Nothing in the Apple reference maps onto a Kromora control (\(detail))."
            )
        }

        var proposed = document
        apply(fit.changes, to: &proposed, sourceKind: sourceKind)
        let provenance = AppleReferenceProvenance(
            sourceKind: sourceKind, space: space,
            filterNames: reference.intent.filterNames,
            omittedEffects: fit.omitted, fitMethod: fit.method,
            referenceStrength: fit.strength,
            analysisDocumentHash: analysisDocument.editHash,
            completeDocumentHash: document.editHash
        )
        return .proposed(AppleReferenceProposal(
            document: proposed,
            changes: fit.changes,
            confidence: fit.confidence,
            provenance: provenance,
            residualError: fit.residualError,
            notes: "Apple Core Image reference fitted through editable Kromora controls; "
                + "no Core Image filter is stored in the edit."
        ))
    }

    // MARK: - Application onto the complete edit

    /// Applies fitted changes onto the complete document. Only the v1 fitted controls move —
    /// the six Light sliders, vibrance/saturation, and white balance through the existing
    /// RAW/standard mapping. Everything else (LUT, grading, grain, vignette, curves, mixer,
    /// crop, rotation, ordered nodes, local masks) is untouched by construction.
    private func apply(
        _ changes: [AutoControlChange], to document: inout EditDocument,
        sourceKind: AutoSourceKind
    ) {
        for change in changes {
            switch (change.control, sourceKind) {
            case (.exposure, _): document.light.exposure = change.proposed
            case (.contrast, _): document.light.contrast = change.proposed
            case (.highlights, _): document.light.highlights = change.proposed
            case (.shadows, _): document.light.shadows = change.proposed
            case (.whites, _): document.light.whites = change.proposed
            case (.blacks, _): document.light.blacks = change.proposed
            case (.vibrance, _): document.color.vibrance = change.proposed
            case (.saturation, _): document.color.saturation = change.proposed
            case (.temperature, .raw): document.rawDevelop.neutralTemperature = change.proposed
            case (.tint, .raw): document.rawDevelop.neutralTint = change.proposed
            case (.temperature, .standard):
                document.adjustments = AdjustmentControl.temperature.setting(
                    change.proposed, in: document.adjustments
                )
            case (.tint, .standard):
                document.adjustments = AdjustmentControl.tint.setting(
                    change.proposed, in: document.adjustments
                )
            case (.dehaze, _):
                // The fitter never emits dehaze; ignore defensively so a future fitter version
                // cannot smuggle an unfitted control through this switch.
                break
            }
        }
    }
}
