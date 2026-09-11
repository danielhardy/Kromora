import Foundation

/// User-visible milestones for one content-aware Auto run. The callback is deliberately value-only
/// so the editor can publish progress without exposing analysis or renderer objects.
enum AutoEnhancementPhase: Sendable, Equatable {
    case analyzing
    case renderingCandidates
    case validating
}

/// The owner of a local layer. Auto-created recipes remain ordinary editable layers; this
/// marker only controls whether a later Auto run may replace them.
enum AutoLayerOwnership: String, Codable, Sendable, Equatable {
    case user
    case auto
}

/// Stable provenance for a generated local layer. It intentionally contains no mask pixels.
struct AutoLayerProvenance: Codable, Sendable, Equatable {
    let purpose: AutoRegionalPurpose
    let algorithmVersion: Int
    let generationID: String

    init(
        purpose: AutoRegionalPurpose,
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        generationID: String = ""
    ) {
        self.purpose = purpose
        self.algorithmVersion = max(1, algorithmVersion)
        self.generationID = generationID
    }

    /// The identity used to reconcile a generated layer across Auto runs. The generation ID is
    /// diagnostic provenance for one run; it must not make a new run append a duplicate layer.
    var stableIdentity: String { purpose.rawValue }
}

/// The inputs that identify a successful Auto result. The document hash is the visible edit
/// state, excluding this metadata, so storing the fingerprint cannot make the fingerprint stale.
struct AutoRunFingerprint: Codable, Sendable, Equatable, Hashable {
    let sourceFingerprint: String
    let documentHash: String
    let algorithmVersion: Int
    let renderIdentity: String

    init(
        sourceFingerprint: String,
        documentHash: String,
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        renderIdentity: String = RenderIdentity.current
    ) {
        self.sourceFingerprint = sourceFingerprint
        self.documentHash = documentHash
        self.algorithmVersion = max(1, algorithmVersion)
        self.renderIdentity = renderIdentity
    }

    static func make(
        source: ImageSource,
        document: EditDocument,
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        renderIdentity: String = RenderIdentity.current
    ) -> Self {
        Self(
            sourceFingerprint: source.cacheFingerprint,
            documentHash: document.renderingHash,
            algorithmVersion: algorithmVersion,
            renderIdentity: renderIdentity
        )
    }

    func matches(
        source: ImageSource,
        document: EditDocument,
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        renderIdentity: String = RenderIdentity.current
    ) -> Bool {
        self
            == Self.make(
                source: source, document: document,
                algorithmVersion: algorithmVersion, renderIdentity: renderIdentity
            )
    }

    /// A compact value useful for diagnostics and persisted reports without leaking a path.
    var digest: String {
        RenderCacheHash.digest(self)
    }
}

/// Versioned identity of the render implementation. Bumping it invalidates only Auto result
/// fingerprints; it does not rewrite the user's edit or unrelated render caches.
enum RenderIdentity {
    static let current = "Kromora.RenderPipeline.v3"
}

/// Pixel validation facts retained with the accepted result. These are deliberately scalar and
/// Codable so the review UI and support diagnostics never need to retain image objects.
struct AutoValidationMeasurements: Codable, Sendable, Equatable {
    let globalExposure: Double
    let regionExposure: Double
    let clipping: Double
    let neutral: Double
    let saturation: Double
    let score: Double
    let rejected: Bool

    init(
        globalExposure: Double = 0,
        regionExposure: Double = 0,
        clipping: Double = 0,
        neutral: Double = 0,
        saturation: Double = 0,
        score: Double = 0,
        rejected: Bool = false
    ) {
        self.globalExposure = Self.finite(globalExposure)
        self.regionExposure = Self.finite(regionExposure)
        self.clipping = Self.finite(clipping)
        self.neutral = Self.finite(neutral)
        self.saturation = Self.finite(saturation)
        self.score = Self.finite(score)
        self.rejected = rejected
    }

    init(score: AutoCandidateScore) {
        self.init(
            globalExposure: score.globalExposure,
            regionExposure: score.regionExposure,
            clipping: score.clipping,
            neutral: score.neutral,
            saturation: score.saturation,
            score: score.total,
            rejected: score.rejected
        )
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}

/// One durable, reviewable Auto outcome. It carries a complete document rather than a patch so
/// application can be atomic and undo can retain the ordinary before-document snapshot.
struct AutoEnhancementResult: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable, Equatable {
        case improved
        case unchanged
        case noCandidate
        case cancelled
        case staleRevision
        case renderUnavailable
    }

    let status: Status
    let proposedDocument: EditDocument
    let algorithmVersion: Int
    let changedControls: [AutoPolicyControl]
    let confidence: Float
    let reasons: [String]
    let validationMeasurements: AutoValidationMeasurements
    let candidateProvenance: AutoCandidateProvenance?
    let fingerprint: AutoRunFingerprint?
    let generatedLayerIDs: [UUID]
    /// Bounded per-stage latency record (KRMA-352). Value-only diagnostics; never read by
    /// selection, apply, or persistence — attaching it cannot change candidate behavior.
    let timings: AutoRunTimings

    init(
        status: Status = .improved,
        proposedDocument: EditDocument,
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        changedControls: [AutoPolicyControl] = [],
        confidence: Float = 0,
        reasons: [String] = [],
        validationMeasurements: AutoValidationMeasurements = .init(),
        candidateProvenance: AutoCandidateProvenance? = nil,
        fingerprint: AutoRunFingerprint? = nil,
        generatedLayerIDs: [UUID] = [],
        timings: AutoRunTimings = .zero
    ) {
        self.status = status
        self.proposedDocument = proposedDocument
        self.algorithmVersion = max(1, algorithmVersion)
        self.changedControls = changedControls.sorted { $0.rawValue < $1.rawValue }
        self.confidence = min(max(confidence.isFinite ? confidence : 0, 0), 1)
        self.reasons = reasons
        self.validationMeasurements = validationMeasurements
        self.candidateProvenance = candidateProvenance
        self.fingerprint = fingerprint
        self.generatedLayerIDs = generatedLayerIDs
        self.timings = timings
    }

    /// Compatibility spelling for callers that treat the result as the selected document.
    var document: EditDocument { proposedDocument }
    var candidate: AutoCandidateProvenance? { candidateProvenance }
    var isNoOp: Bool {
        status != .improved || (changedControls.isEmpty && generatedLayerIDs.isEmpty)
    }

    func applying(to current: EditDocument) -> EditDocument {
        EditDocument.applyingAutoResult(self, to: current)
    }
}

extension AutoEnhancementResult {
    static func from(
        _ coordinator: AutoEnhancementCoordinatorResult,
        current: EditDocument,
        confidence: Float,
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        renderIdentity: String = RenderIdentity.current,
        source: ImageSource,
        regionalNotes: [String] = [],
        timings: AutoRunTimings = .zero
    ) -> Self {
        let changed: [AutoPolicyControl]
        if coordinator.status == .improved {
            changed = autoChangedControls(from: current, to: coordinator.document)
        } else {
            changed = []
        }
        let fingerprint: AutoRunFingerprint?
        if coordinator.status == .improved {
            fingerprint = AutoRunFingerprint(
                sourceFingerprint: source.cacheFingerprint,
                documentHash: coordinator.document.renderingHash,
                algorithmVersion: algorithmVersion,
                renderIdentity: renderIdentity
            )
        } else {
            fingerprint = nil
        }
        return Self(
            status: Status(rawValue: coordinator.status.rawValue) ?? .noCandidate,
            proposedDocument: coordinator.document,
            algorithmVersion: algorithmVersion,
            changedControls: changed,
            confidence: confidence,
            reasons: [coordinator.message]
                + regionalNotes
                + coordinator.candidateNotes.values.sorted(),
            validationMeasurements: .init(score: coordinator.selectedScore ?? .acceptable),
            candidateProvenance: coordinator.provenance,
            fingerprint: fingerprint,
            generatedLayerIDs: coordinator.document.localAdjustments.filter(\.isAutoOwned)
                .map(\.id),
            timings: timings
        )
    }
}

private func autoChangedControls(from old: EditDocument, to new: EditDocument)
    -> [AutoPolicyControl]
{
    AutoPolicyControl.allCases.filter { control in
        switch control {
        case .exposure: return old.light.exposure != new.light.exposure
        case .contrast: return old.light.contrast != new.light.contrast
        case .highlights: return old.light.highlights != new.light.highlights
        case .shadows: return old.light.shadows != new.light.shadows
        case .whites: return old.light.whites != new.light.whites
        case .blacks: return old.light.blacks != new.light.blacks
        case .vibrance: return old.color.vibrance != new.color.vibrance
        case .saturation: return old.color.saturation != new.color.saturation
        case .dehaze: return old.effects.dehaze != new.effects.dehaze
        case .temperature:
            let oldValue =
                old.rawDevelop.neutralTemperature
                ?? AdjustmentControl.temperature.value(in: old.adjustments)
            let newValue =
                new.rawDevelop.neutralTemperature
                ?? AdjustmentControl.temperature.value(in: new.adjustments)
            return oldValue != newValue
        case .tint:
            let oldValue =
                old.rawDevelop.neutralTint ?? AdjustmentControl.tint.value(in: old.adjustments)
            let newValue =
                new.rawDevelop.neutralTint ?? AdjustmentControl.tint.value(in: new.adjustments)
            return oldValue != newValue
        }
    }
}
