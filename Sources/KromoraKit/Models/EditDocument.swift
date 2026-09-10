import Foundation

/// The look, as a value.
///
/// This is the spine of Phase 2. Today Kromora holds a *baked* `processedImage`; after the migration it
/// holds one of these and rebuilds the image from it on demand. Being a `Codable`, `Sendable`,
/// `Equatable` value is what buys undo, presets, per-image edits, and a clean actor boundary all at
/// once — none of which a baked bitmap can give. See `docs/ENGINEERING_GUIDE.md`
///
/// **An empty document is the identity transform.** `EditDocument()` must render the source
/// unchanged; that invariant is what lets the migration introduce the new spine under the old
/// behaviour without moving a pixel.
struct EditDocument: Codable, Sendable, Equatable {

    /// Schema version, present from the very first release.
    ///
    /// Nothing reads it yet. It exists now because retrofitting a version field onto documents
    /// already written to disk means guessing what an unversioned one meant — and `EditDocument` is
    /// `Codable` precisely so it can be persisted later (§8.8).
    var version: Int = EditDocument.currentVersion

    /// Only meaningful for a RAW source; ignored for standard images, which have no develop stage.
    var rawDevelop: RAWDevelopSettings = .neutral

    /// Photographer-facing global tone controls. Missing from an older document means neutral.
    var light: LightAdjustments = .neutral

    /// Photographer-facing global colour controls. Missing from an older document means neutral.
    var color: ColorAdjustments = .neutral

    /// Photographer-facing global Effects controls. Missing from an older document means neutral.
    var effects: EffectsAdjustments = .neutral

    /// Non-destructive framing in normalized, oriented-image coordinates.
    var crop: CropAdjustments = .neutral

    /// Non-destructive quarter-turn rotation, applied before crop and other spatial edits.
    var rotation: ImageRotation = .zero

    /// Ordered tone/colour stages. Order matters and duplicates are allowed — see `AdjustmentNode`.
    var adjustments: [AdjustmentNode] = []

    /// Which LUT, at what strength.
    var lut: LUTSettings = .none

    /// Ordered, non-destructive local adjustment recipes. Mask pixels are derived at render time;
    /// only semantic intent, vectors, and analytic geometry live in the document.
    var localAdjustments: [LocalAdjustmentLayer] = []

    /// Metadata from the last successful content-aware Auto run. It has no rendering effect and
    /// is excluded from `renderingHash`, so it can be used for repeat-run no-op detection without
    /// invalidating image caches.
    var lastAutoRunFingerprint: AutoRunFingerprint?

    /// v2 added the local-mask field. v3 adds the image rotation field. Missing fields decode to
    /// their neutral values so existing edit records remain readable and are upgraded on save.
    static let currentVersion = 4

    init(
        version: Int = EditDocument.currentVersion,
        rawDevelop: RAWDevelopSettings = .neutral,
        light: LightAdjustments = .neutral,
        color: ColorAdjustments = .neutral,
        effects: EffectsAdjustments = .neutral,
        crop: CropAdjustments = .neutral,
        rotation: ImageRotation = .zero,
        adjustments: [AdjustmentNode] = [],
        lut: LUTSettings = .none,
        localAdjustments: [LocalAdjustmentLayer] = [],
        lastAutoRunFingerprint: AutoRunFingerprint? = nil
    ) {
        self.version = version
        self.rawDevelop = rawDevelop
        self.light = light
        self.color = color
        self.effects = effects
        self.crop = crop
        self.rotation = rotation
        self.adjustments = adjustments
        self.lut = lut
        self.localAdjustments = localAdjustments
        self.lastAutoRunFingerprint = lastAutoRunFingerprint
    }

    /// True when this document would leave the source untouched.
    var isIdentity: Bool {
        rawDevelop.isNeutral && light.isIdentity && color.isIdentity && effects.isIdentity && crop.isIdentity &&
            rotation == .zero &&
            adjustments.allSatisfy(\.isIdentity) && lut.isIdentity && localAdjustments.allSatisfy(\.isIdentity)
    }

    /// True when the document contains an edit that changes the photographer-facing look.
    /// RAW develop settings intentionally do not count: the comparison baseline keeps the
    /// developed source, so a develop-only comparison would show identical pixels.
    var hasVisibleLookEdits: Bool {
        !light.isIdentity || !color.isIdentity || !effects.isIdentity || !crop.isIdentity || rotation != .zero ||
            !adjustments.allSatisfy(\.isIdentity) || !lut.isIdentity || localAdjustments.contains(where: \.hasVisibleLook)
    }

    /// True when a visible local adjustment depends on a semantic mask provider. This is the
    /// admission check for the progressive preview path; vector and brush masks can still be
    /// evaluated in the first frame without waiting for Vision.
    var hasSemanticMasks: Bool {
        localAdjustments.contains { layer in
            layer.isEnabled && layer.amount > 0 && layer.components.contains { component in
                component.isUsable && component.source.semanticDefinition != nil
            }
        }
    }

    /// Stable SHA-256 identity for caches, undo diagnostics, and persistence comparisons. Auto
    /// review metadata is intentionally excluded because it has no effect on rendered pixels.
    var editHash: String { renderingHash }

    /// Stable visible-edit identity. Auto provenance is review metadata, not a render input.
    var renderingHash: String {
        var copy = self
        copy.lastAutoRunFingerprint = nil
        return RenderCacheHash.digest(copy)
    }

    /// Applies a value produced by a normal editor control. Auto metadata is invalidated when a
    /// visible edit changes, and a touched Auto layer becomes user-owned before it is persisted.
    static func markingManualEdits(from old: Self, to proposed: Self) -> Self {
        guard old.renderingHash != proposed.renderingHash else { return proposed }
        var updated = proposed
        updated.lastAutoRunFingerprint = nil
        for index in updated.localAdjustments.indices {
            guard let oldLayer = old.localAdjustments.first(where: { $0.id == updated.localAdjustments[index].id }),
                  oldLayer.isAutoOwned,
                  oldLayer != updated.localAdjustments[index] else { continue }
            updated.localAdjustments[index].markUserOwned()
        }
        return updated
    }

    /// Reconciles the Auto-generated recipes in a candidate with the current document. Stable
    /// purpose identity updates an existing Auto layer in place, while any user-owned layer is
    /// protected from replacement. User layers not mentioned by the candidate are byte-for-byte
    /// retained.
    static func applyingAutoResult(_ result: AutoEnhancementResult, to current: Self) -> Self {
        guard result.status == .improved else { return current }
        var applied = result.proposedDocument
        let generated = applied.localAdjustments.filter(\.isAutoOwned)
        var reconciled = current.localAdjustments
        for generatedLayer in generated {
            guard let purpose = generatedLayer.autoProvenance?.purpose else { continue }
            if let index = reconciled.firstIndex(where: {
                $0.isAutoOwned && $0.autoProvenance?.purpose == purpose
            }) {
                var replacement = generatedLayer
                replacement.id = reconciled[index].id
                reconciled[index] = replacement
            } else if !reconciled.contains(where: {
                $0.autoProvenance?.purpose == purpose
            }) {
                reconciled.append(generatedLayer)
            }
        }
        applied.localAdjustments = reconciled
        if let fingerprint = result.fingerprint { applied.lastAutoRunFingerprint = fingerprint }
        return applied
    }

    /// What "the original" means for A/B comparison: **develop applied, nothing else**.
    ///
    /// `docs/ENGINEERING_GUIDE.md` asked whether the comparison baseline should be develop-applied or
    /// the decoder's neutral defaults, and recommended develop-applied — holding Space should show
    /// the same photograph without the *look*, not a different rendering of the negative. This
    /// implements that.
    ///
    /// Light is also removed because it is a global edit stage, while `rawDevelop` is retained as
    /// the camera/decode baseline for the same source.
    ///
    /// Sharing `rawDevelop` with the full document is also what keeps the A/B swap cheap: the
    /// engine's developed-source memo is keyed on it, so both sides of the comparison hit the same
    /// entry instead of re-developing the RAW on every Space press.
    var originalForComparison: EditDocument {
        EditDocument(
            version: version, rawDevelop: rawDevelop, light: .neutral, color: .neutral,
            effects: .neutral, crop: crop, rotation: rotation,
            adjustments: [], lut: .none, localAdjustments: []
        )
    }

    /// The explicit before-image state used by both Space-hold and side-by-side comparison.
    var comparisonBaseline: EditDocument { originalForComparison }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version, rawDevelop, light, color, effects, crop, rotation, adjustments, lut,
             localAdjustments, lastAutoRunFingerprint
    }

    /// Decoded field by field rather than by synthesis, for two reasons.
    ///
    /// Synthesized `Decodable` ignores property defaults: a document missing any key would fail
    /// outright, so adding a field in v2 would break v1 documents. `decodeIfPresent` makes an absent
    /// field mean "the default", which is what every added field will want.
    ///
    /// And a document from a *newer* schema is rejected rather than silently narrowed. Loading a v2
    /// document into a v1 build would drop whatever v2 added, and the next save would write that loss
    /// back to disk. Refusing to open it is recoverable; quietly discarding an edit is not.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Edit was saved by a newer version of Kromora (schema \(version); this build reads \(Self.currentVersion))."
            )
        }
        // Reading an older document is a migration: its missing v2 local layer field is the
        // neutral empty array, and the next save writes the current schema number.
        self.version = version < Self.currentVersion ? Self.currentVersion : version
        self.rawDevelop = try container.decodeIfPresent(RAWDevelopSettings.self, forKey: .rawDevelop) ?? .neutral
        self.light = try container.decodeIfPresent(LightAdjustments.self, forKey: .light) ?? .neutral
        self.color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .neutral
        self.effects = try container.decodeIfPresent(EffectsAdjustments.self, forKey: .effects) ?? .neutral
        self.crop = try container.decodeIfPresent(CropAdjustments.self, forKey: .crop) ?? .neutral
        self.rotation = try container.decodeIfPresent(ImageRotation.self, forKey: .rotation) ?? .zero
        self.adjustments = try container.decodeIfPresent([AdjustmentNode].self, forKey: .adjustments) ?? []
        self.lut = try container.decodeIfPresent(LUTSettings.self, forKey: .lut) ?? .none
        self.localAdjustments = try container.decodeIfPresent([LocalAdjustmentLayer].self, forKey: .localAdjustments) ?? []
        self.lastAutoRunFingerprint = try container.decodeIfPresent(
            AutoRunFingerprint.self, forKey: .lastAutoRunFingerprint
        )
    }
}
