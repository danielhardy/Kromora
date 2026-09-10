import CoreGraphics
import Foundation

// MARK: - Selective Auto-owned regional correction layers (KRMA-348)

///
/// A local correction is created only when regional evidence shows the global proposal cannot
/// improve an important region without damaging another. Every layer below is an ordinary,
/// editable mask recipe rendered through the existing `LocalMaskRenderer` path, so preview and
/// export agree and the layers survive save/reopen through `EditDocument` unchanged.
///
/// Deliberate non-goals: no inferred sky mask exists anywhere here (bright/blue pixels alone
/// never create a layer), no saliency-only subject choice (person/foreground evidence is
/// preferred), and no duplicate mask implementation (recipes reference the stable semantic
/// targets the coordinator already produces; the face matte itself is landmark-derived, see
/// `FaceLandmarkMask`).
enum AutoRegionalPurpose: String, Sendable, Codable, CaseIterable, Equatable {
    case subjectLift
    case backgroundProtection
    case colorCorrection

    /// At most three Auto-owned layers may ever exist on a document (acceptance criterion).
    static let maximumLayers = 3

    /// Ownership marker. A layer whose name carries this prefix is Auto-owned; a user edit that
    /// renames the layer releases it back to the photographer, and planning never touches it
    /// again. Duplicate prevention is a name check against this prefix (see `hasAutoLayers`).
    static let ownedNamePrefix = "Auto — "

    /// Stable, purpose-describing names in a fixed order so repeated Auto runs neither duplicate
    /// nor reorder existing Auto-owned layers.
    var layerName: String {
        switch self {
        case .subjectLift: return Self.ownedNamePrefix + "Subject"
        case .backgroundProtection: return Self.ownedNamePrefix + "Background"
        case .colorCorrection: return Self.ownedNamePrefix + "Color"
        }
    }

    var semanticTarget: SemanticTarget {
        switch self {
        case .subjectLift: return .subject
        case .backgroundProtection: return .background
        case .colorCorrection: return .subject
        }
    }
}

/// Named policy constants for the regional planner. Thresholds live here rather than inline so
/// tests and future tuning review one registry.
enum AutoRegionalThresholds {
    /// A mask covering less than 2% of the frame is detail work, not a regional correction.
    static let minimumCoverage: Float = 0.02
    /// A mask covering more than 90% of the frame is effectively global; the global proposal
    /// already owns that correction.
    static let maximumCoverage: Float = 0.90
    /// Regional evidence below this confidence is reported, never acted on.
    static let minimumConfidence: Float = 0.25
    /// Minimum share of mask support in the soft transition band. A rectangle-derived matte has
    /// a transition fraction near zero and is rejected here, which is what keeps hard-edged
    /// face boxes out of the Auto path even if one ever reaches it.
    static let minimumTransitionFraction: Float = 0.02
    /// Above this subject/background intersection-over-union the two mattes no longer separate
    /// the regions they claim, and any masked correction would land on both.
    static let maximumOverlap: Float = 0.5
    /// Post-global subject median below this is still dark enough to warrant a lift.
    static let subjectDarkMedian: Float = 0.32
    /// Post-global background median above this (or highlight clipping above
    /// `backgroundClipping`) is still bright enough to warrant protection.
    static let backgroundBrightMedian: Float = 0.60
    static let backgroundClipping: Float = 0.02
    /// Minimum absolute signed cast that warrants a localized color correction.
    static let minimumCastStrength: Float = 0.15
    /// Minimum share of the mask's bounds area that must survive the active crop. Below this
    /// the matte was computed for a framing the photographer has since discarded.
    static let minimumCropOverlap: Double = 0.5
}

/// Post-global regional tone facts for one region. These describe the rendered edit after the
/// global proposal, not the source: a region the global pass already fixed must not earn a
/// layer. Values are unit-interval `Float`s matching `ToneStatistics` conventions.
struct AutoRegionalToneEvidence: Sendable, Codable, Equatable {
    /// Post-global perceptual median (p50).
    var median: Float
    var highlightClipping: Float
    var shadowClipping: Float
    /// Signed cast estimate, -1...1 (negative warms, positive cools); 0 is neutral.
    var cast: Float

    init(median: Float, highlightClipping: Float = 0, shadowClipping: Float = 0, cast: Float = 0) {
        self.median = Self.unit(median)
        self.highlightClipping = Self.unit(highlightClipping)
        self.shadowClipping = Self.unit(shadowClipping)
        self.cast = Self.signedUnit(cast)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func signedUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -1), 1)
    }
}

/// Mask-side facts for one region, derived from the `RegionMask` plus its `NormalizedMask`
/// pixels. Tests construct these directly; production builds them with
/// `AutoRegionalCorrections.facts(for:confidence:bounds:pixels:)`.
struct AutoRegionalMaskFacts: Sendable, Equatable {
    var coverage: Float
    var confidence: Float
    var bounds: NormalizedRect?
    /// Share of supporting pixels in the soft (0.05...0.95) band. Feathered mattes score well
    /// above zero; hard rectangle mattes score near zero and are rejected.
    var transitionFraction: Float

    init(coverage: Float, confidence: Float, bounds: NormalizedRect?, transitionFraction: Float) {
        self.coverage = min(max(coverage.isFinite ? coverage : 0, 0), 1)
        self.confidence = min(max(confidence.isFinite ? confidence : 0, 0), 1)
        self.bounds = bounds
        self.transitionFraction = min(max(transitionFraction.isFinite ? transitionFraction : 0, 0), 1)
    }
}

/// The pure input to regional planning: post-global evidence plus the framing the matte must
/// still align with. `crop` is the active crop in normalized source coordinates, or `nil` for
/// the full frame.
struct AutoRegionalPlanInput: Sendable, Equatable {
    var subjectTone: AutoRegionalToneEvidence?
    var subjectMask: AutoRegionalMaskFacts?
    var prefersPersonTarget: Bool
    var backgroundTone: AutoRegionalToneEvidence?
    var backgroundMask: AutoRegionalMaskFacts?
    /// Pixel-level overlap between the subject and background mattes, when both are available.
    /// Computed with `intersectionOverUnion`; `nil` means it could not be computed (different
    /// resolutions or a missing matte), which is itself a skip reason when both regions are
    /// otherwise actionable.
    var subjectBackgroundOverlap: Float?
    var colorCast: Float
    var crop: NormalizedRect?
    var existingLayerNames: [String]

    init(
        subjectTone: AutoRegionalToneEvidence? = nil,
        subjectMask: AutoRegionalMaskFacts? = nil,
        prefersPersonTarget: Bool = false,
        backgroundTone: AutoRegionalToneEvidence? = nil,
        backgroundMask: AutoRegionalMaskFacts? = nil,
        subjectBackgroundOverlap: Float? = nil,
        colorCast: Float = 0,
        crop: NormalizedRect? = nil,
        existingLayerNames: [String] = []
    ) {
        self.subjectTone = subjectTone
        self.subjectMask = subjectMask
        self.prefersPersonTarget = prefersPersonTarget
        self.backgroundTone = backgroundTone
        self.backgroundMask = backgroundMask
        self.subjectBackgroundOverlap = subjectBackgroundOverlap
        self.colorCast = colorCast.isFinite ? min(max(colorCast, -1), 1) : 0
        self.crop = crop
        self.existingLayerNames = existingLayerNames
    }
}

/// The planning result: ordinary editable layers plus a human-readable note per purpose
/// recording why a layer was added or skipped. Notes surface in the Auto summary so a skipped
/// layer is an explained decision, not a silent absence.
struct AutoRegionalPlan: Sendable, Equatable {
    var layers: [LocalAdjustmentLayer]
    var notes: [String]

    init(layers: [LocalAdjustmentLayer] = [], notes: [String] = []) {
        self.layers = layers
        self.notes = notes
    }
}

enum AutoRegionalCorrections {
    /// Whether the document already carries Auto-owned layers. Planning is duplicate-safe: when
    /// this is true the planner emits no layers and explains why, so repeated Auto runs never
    /// stack a second Subject lift on top of the first.
    static func hasAutoLayers(existingLayerNames: [String]) -> Bool {
        existingLayerNames.contains { $0.hasPrefix(AutoRegionalPurpose.ownedNamePrefix) }
    }

    /// Pure regional planning. Never throws: missing evidence degrades to notes, never to a
    /// layer built on guessing.
    static func plan(_ input: AutoRegionalPlanInput) -> AutoRegionalPlan {
        var layers: [LocalAdjustmentLayer] = []
        var notes: [String] = []

        if hasAutoLayers(existingLayerNames: input.existingLayerNames) {
            notes.append("Regional corrections skipped: Auto-owned layers already exist.")
            return AutoRegionalPlan(layers: [], notes: notes)
        }

        let subjectValidation = validate(
            input.subjectMask, role: "subject", crop: input.crop
        )
        let backgroundValidation = validate(
            input.backgroundMask, role: "background", crop: input.crop
        )

        // Subject and background mattes that do not separate cannot carry opposing corrections.
        // Overlapping people fall out here: either matte pair keeps its evidence, but neither
        // earns a layer that would land on both regions.
        let overlap: Float? = (input.subjectMask != nil && input.backgroundMask != nil)
            ? input.subjectBackgroundOverlap : nil
        if input.subjectMask != nil, input.backgroundMask != nil, overlap == nil {
            notes.append(
                "Regional corrections skipped: subject/background separation could not be verified."
            )
            return AutoRegionalPlan(layers: [], notes: notes)
        }
        if let overlap, overlap > AutoRegionalThresholds.maximumOverlap {
            notes.append(
                "Regional corrections skipped: subject and background masks overlap "
                    + "(\(Int((overlap * 100).rounded()))% shared support)."
            )
            return AutoRegionalPlan(layers: [], notes: notes)
        }

        let subjectTarget: SemanticTarget = input.prefersPersonTarget ? .person : .subject

        if let tone = input.subjectTone, input.subjectMask != nil {
            if !subjectValidation.usable {
                notes.append(
                    "Subject lift skipped: \(subjectValidation.reasons.joined(separator: "; "))."
                )
            } else if tone.median >= AutoRegionalThresholds.subjectDarkMedian {
                notes.append("Subject lift skipped: the global proposal already lifted the subject.")
            } else {
                layers.append(subjectLiftLayer(target: subjectTarget, tone: tone))
                notes.append("Subject lift added (masked to \(subjectTarget.rawValue)).")
            }
        } else {
            notes.append("Subject lift skipped: no subject evidence after the global proposal.")
        }

        if let tone = input.backgroundTone, input.backgroundMask != nil {
            if !backgroundValidation.usable {
                notes.append(
                    "Background protection skipped: "
                        + "\(backgroundValidation.reasons.joined(separator: "; "))."
                )
            } else if tone.median < AutoRegionalThresholds.backgroundBrightMedian,
                      tone.highlightClipping <= AutoRegionalThresholds.backgroundClipping {
                notes.append(
                    "Background protection skipped: the global proposal kept background highlights."
                )
            } else {
                layers.append(backgroundProtectionLayer(tone: tone))
                notes.append("Background protection added (masked to background).")
            }
        } else {
            notes.append(
                "Background protection skipped: no background evidence after the global proposal."
            )
        }

        if abs(input.colorCast) >= AutoRegionalThresholds.minimumCastStrength {
            if input.subjectMask != nil, subjectValidation.usable {
                layers.append(colorCorrectionLayer(target: subjectTarget, cast: input.colorCast))
                notes.append("Localized color correction added (masked to \(subjectTarget.rawValue)).")
            } else {
                notes.append(
                    "Localized color correction skipped: "
                        + "\(subjectValidation.reasons.joined(separator: "; "))."
                )
            }
        } else {
            notes.append("Localized color correction skipped: no material regional cast.")
        }

        layers = Array(layers.prefix(AutoRegionalPurpose.maximumLayers))
        return AutoRegionalPlan(layers: layers, notes: notes)
    }

    /// Append the planned layers to a document. The layers are ordinary recipes, so rendering,
    /// persistence, and the inspector treat them exactly like user-created ones.
    static func applying(_ plan: AutoRegionalPlan, to document: EditDocument) -> EditDocument {
        guard !plan.layers.isEmpty else { return document }
        var updated = document
        var layers = document.localAdjustments
        for generated in plan.layers {
            guard let provenance = generated.autoProvenance else { continue }
            if let index = layers.firstIndex(where: {
                $0.isAutoOwned && $0.autoProvenance?.stableIdentity == provenance.stableIdentity
            }) {
                var replacement = generated
                replacement.id = layers[index].id
                layers[index] = replacement
            } else if !layers.contains(where: {
                $0.autoProvenance?.stableIdentity == provenance.stableIdentity
            }) {
                layers.append(generated)
            }
        }
        updated.localAdjustments = layers
        return updated
    }

    // MARK: - Mask evidence helpers

    /// Build planner facts from a resolved matte. `confidence` and `bounds` come from the
    /// `RegionMask`; coverage and the feathered-boundary check come from the pixels.
    static func facts(
        pixels: NormalizedMask, confidence: Float, bounds: NormalizedRect?
    ) -> AutoRegionalMaskFacts {
        AutoRegionalMaskFacts(
            coverage: pixels.coverage,
            confidence: confidence,
            bounds: bounds,
            transitionFraction: transitionFraction(of: pixels)
        )
    }

    /// Share of supporting pixels in the soft band. Feathered mattes distribute a visible share
    /// of their support across the transition; hard-edged mattes concentrate support at exactly
    /// 0 and 1.
    static func transitionFraction(of mask: NormalizedMask) -> Float {
        guard !mask.values.isEmpty else { return 0 }
        var support = 0
        var soft = 0
        for value in mask.values where value > 0.001 {
            support += 1
            if value > 0.05, value < 0.95 { soft += 1 }
        }
        guard support > 0 else { return 0 }
        return Float(soft) / Float(support)
    }

    /// Intersection-over-union of mask support (alpha > 0.5). Returns `nil` when the mattes have
    /// different resolutions, which the planner treats as unverifiable separation rather than
    /// as zero overlap.
    static func intersectionOverUnion(_ lhs: NormalizedMask, _ rhs: NormalizedMask) -> Float? {
        guard lhs.size == rhs.size, !lhs.values.isEmpty else { return nil }
        var intersection = 0
        var union = 0
        for (left, right) in zip(lhs.values, rhs.values) {
            let leftOn = left > 0.5
            let rightOn = right > 0.5
            if leftOn, rightOn { intersection += 1 }
            if leftOn || rightOn { union += 1 }
        }
        guard union > 0 else { return 0 }
        return Float(intersection) / Float(union)
    }

    /// Intersect a matte with person/foreground support so face content cannot bleed past the
    /// segmented boundary. Returns `nil` on resolution mismatch so callers skip rather than
    /// combine mattes from different framings.
    static func intersectedWithSupport(
        _ mask: NormalizedMask, support: NormalizedMask?
    ) -> NormalizedMask? {
        guard let support else { return mask }
        guard mask.size == support.size else { return nil }
        return try? MaskOperations.intersect(mask, support)
    }

    // MARK: - Validation

    struct MaskValidation: Sendable, Equatable {
        var usable: Bool
        var reasons: [String]
    }

    /// Validate one matte: coverage band, confidence floor, feathered boundary, and
    /// crop/orientation alignment. A `nil` matte yields an unusable validation with a reason so
    /// the planner degrades to a note instead of a guess.
    static func validate(
        _ facts: AutoRegionalMaskFacts?, role: String, crop: NormalizedRect?
    ) -> MaskValidation {
        guard let facts else {
            return MaskValidation(usable: false, reasons: ["no \(role) mask available"])
        }
        var reasons: [String] = []
        if facts.coverage < AutoRegionalThresholds.minimumCoverage {
            reasons.append("\(role) mask covers too little of the frame")
        }
        if facts.coverage > AutoRegionalThresholds.maximumCoverage {
            reasons.append("\(role) mask is effectively global")
        }
        if facts.confidence < AutoRegionalThresholds.minimumConfidence {
            reasons.append("\(role) mask confidence is too low")
        }
        if facts.transitionFraction < AutoRegionalThresholds.minimumTransitionFraction {
            reasons.append("\(role) mask boundary is not feathered")
        }
        if let bounds = facts.bounds, let crop, !cropAligned(bounds: bounds, crop: crop) {
            reasons.append("\(role) mask does not align with the active crop")
        } else if facts.bounds == nil {
            reasons.append("\(role) mask location is unknown")
        }
        return MaskValidation(usable: reasons.isEmpty, reasons: reasons)
    }

    /// Whether the matte's bounds still describe the active framing. The matte and the crop
    /// share normalized source coordinates, so a crop that discards most of the matte's support
    /// means the matte predates the framing (or the orientation handling drifted).
    static func cropAligned(bounds: NormalizedRect, crop: NormalizedRect) -> Bool {
        let boundsArea = bounds.width * bounds.height
        guard boundsArea > 0 else { return false }
        let width = max(0, min(bounds.maxX, crop.maxX) - max(bounds.minX, crop.minX))
        let height = max(0, min(bounds.maxY, crop.maxY) - max(bounds.minY, crop.minY))
        let overlap = (width * height) / boundsArea
        return overlap >= AutoRegionalThresholds.minimumCropOverlap
    }

    // MARK: - Layer recipes

    static func subjectLiftLayer(
        target: SemanticTarget, tone: AutoRegionalToneEvidence
    ) -> LocalAdjustmentLayer {
        // Lift scales with how dark the subject remains: a median at the threshold earns a
        // whisper, a near-black subject earns the full conservative lift. The ceiling keeps the
        // correction inside the global guardrails the coordinator already enforces.
        let shortfall = max(
            0, Double(AutoRegionalThresholds.subjectDarkMedian - tone.median)
        )
        let exposure = min(0.7, 0.15 + shortfall * 2.5)
        let shadows = min(35, 8 + shortfall * 120)
        return LocalAdjustmentLayer(
            name: AutoRegionalPurpose.subjectLift.layerName,
            components: [semanticComponent(target: target)],
            adjustments: LocalAdjustments(exposure: exposure, shadows: shadows),
            ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
    }

    static func backgroundProtectionLayer(
        tone: AutoRegionalToneEvidence
    ) -> LocalAdjustmentLayer {
        // Compress only: highlights come down in proportion to measured clipping, whites follow
        // at half strength. No lift component exists here by construction, so this layer cannot
        // brighten the region it protects even if the photographer raises its amount.
        let highlights = -min(60, 15 + Double(tone.highlightClipping) * 900)
        let whites = highlights * 0.5
        return LocalAdjustmentLayer(
            name: AutoRegionalPurpose.backgroundProtection.layerName,
            components: [semanticComponent(target: .background)],
            adjustments: LocalAdjustments(highlights: highlights, whites: whites),
            ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .backgroundProtection)
        )
    }

    static func colorCorrectionLayer(target: SemanticTarget, cast: Float) -> LocalAdjustmentLayer {
        // Counter-steer the measured cast toward neutral. The ±8K window around the 6500K
        // neutral point is deliberately small: this corrects a residual cast, it never imposes
        // a look.
        let temperature = 6500 - Double(cast) * 800
        return LocalAdjustmentLayer(
            name: AutoRegionalPurpose.colorCorrection.layerName,
            components: [semanticComponent(target: target)],
            adjustments: LocalAdjustments(temperature: temperature),
            ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .colorCorrection)
        )
    }

    private static func semanticComponent(target: SemanticTarget) -> MaskComponent {
        MaskComponent(
            source: .semantic(SemanticMaskDefinition(
                target: target,
                // A light recipe-level feather rides on top of the already-feathered matte so
                // the correction dissolves into the surrounding tones even if the matte's own
                // transition is narrow.
                edgeFeather: 0.15,
                generationVersion: SemanticMaskDefinition.currentGenerationVersion
            ))
        )
    }
}

// MARK: - Feathered landmark-derived face mattes

/// Builds face mattes from Vision face-landmark points instead of detector bounding boxes.
///
/// A rectangle matte covers forehead, ears, and background with full weight and then cuts to
/// zero at the box edge; any correction masked to it visibly stamps the box onto the photo.
/// The landmark matte instead fits an ellipse to the observed facial-feature points, expands it
/// to cover the whole face, and feathers the boundary, so weight follows the face and dissolves
/// before the surrounding tones begin. Callers intersect the result with person/foreground
/// support (see `intersectedWithSupport`) so overlapping people keep their own mattes.
enum FaceLandmarkMask {
    enum BuildError: Error, Sendable, Equatable {
        case insufficientPoints
        case invalidDimensions
    }

    /// Rasterize one face matte. Points are normalized upper-left source coordinates (convert
    /// Vision output with `NormalizedPoint.fromVision` first). The ellipse is fit to the
    /// feature-point bbox expanded to whole-face extent, then feathered so the transition
    /// fraction reads well above `AutoRegionalThresholds.minimumTransitionFraction`.
    static func rasterize(
        points: [NormalizedPoint], size: PixelDimensions, featherRadius: Int = 2
    ) throws -> NormalizedMask {
        guard size.width > 0, size.height > 0 else { throw BuildError.invalidDimensions }
        guard points.count >= 3 else { throw BuildError.insufficientPoints }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else {
            throw BuildError.insufficientPoints
        }

        // Landmark points span the inner features (brows to mouth). Expand to whole-face extent:
        // sideways past the cheeks, upward past the forehead, downward past the chin.
        let featureWidth = maxX - minX
        let featureHeight = maxY - minY
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2 + featureHeight * 0.08
        let radiusX = featureWidth * 0.85
        let radiusY = featureHeight * 1.05

        var values = [Float](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            let normalizedY = (Double(y) + 0.5) / Double(size.height)
            for x in 0..<size.width {
                let normalizedX = (Double(x) + 0.5) / Double(size.width)
                let ellipse =
                    pow((normalizedX - centerX) / radiusX, 2)
                    + pow((normalizedY - centerY) / radiusY, 2)
                // A soft analytic falloff bakes the feather into the matte itself: full weight
                // inside 70% of the ellipse radius, dissolving to zero at the boundary.
                let falloff = 1 - (sqrt(ellipse) - 0.7) / 0.3
                values[y * size.width + x] = Float(min(max(falloff, 0), 1))
            }
        }
        let solid = try NormalizedMask(size: size, values: values)
        return try MaskOperations.feather(solid, radius: max(1, featherRadius))
    }
}
