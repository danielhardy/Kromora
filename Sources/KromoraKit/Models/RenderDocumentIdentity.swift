import Foundation

/// Definition digests preserve source values alongside component IDs because persisted edit data
/// may contain duplicate IDs. A repeated ID must not make distinct mask sources share a cache key.
struct RenderMaskComponentDigests: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        let id: UUID
        let source: MaskSource
        let definitionHash: String
    }

    private(set) var entries: [Entry] = []

    mutating func append(id: UUID, source: MaskSource, definitionHash: String) {
        entries.append(Entry(id: id, source: source, definitionHash: definitionHash))
    }

    func definitionHash(for component: MaskComponent) -> String? {
        definitionHash(for: component.id, source: component.source)
    }

    func definitionHash(for id: UUID, source: MaskSource) -> String? {
        let matchingID = entries.filter { $0.id == id }
        if let exact = matchingID.first(where: { $0.source == source }) {
            return exact.definitionHash
        }
        // Non-finite values compare unequal to themselves. When the component ID is unique, its
        // stored digest is still unambiguous and must remain usable as an uncached identity.
        return matchingID.count == 1 ? matchingID[0].definitionHash : nil
    }
}

/// Session-tier identity for an `EditDocument`: one deterministic SHA-256 digest per render-relevant
/// component, plus a whole-document key composed from them.
///
/// This is deliberately a distinct, non-`Codable` type. It is session-only by contract, so it can
/// never be stored in a persisted structure or passed where a durable `EditDocument.editHash` is
/// expected. See `docs/RENDER_KEY_PLAN.md`.
struct RenderDocumentIdentity: Sendable, Equatable {
    /// `RAWDevelopSettings`, the developed-source key.
    let rawDevelop: String
    /// The processing-prefix upstream inputs with the temperature/tint stage retained.
    let prefixUpstream: String
    /// The processing-prefix upstream inputs with the temperature/tint stage removed.
    let prefixUpstreamWithoutWhiteBalance: String
    /// `localAdjustments`, the post-local prefix key.
    let localAdjustments: String
    /// `RenderEngine.MaskRecipeIdentity`, the semantic-mask restart fence.
    let maskRecipe: String
    /// Definition digest of each mask component's `MaskSource`, matched by ID and source value.
    let maskComponents: RenderMaskComponentDigests
    /// Whole-document session key, composed from the component digests and the fields no
    /// component covers (crop, rotation, full effects).
    let sessionKey: String

    /// `RenderCacheHash.digest(RAWDevelopSettings.neutral)`, for renders that develop with no edit.
    static let neutralRAWDevelop = RenderCacheHash.digest(RAWDevelopSettings.neutral)

    /// Component definition digests for layers that have no document identity (the mask overlay).
    /// `onlyComponentID` restricts digesting to that component, so an isolated overlay request
    /// never hashes unrelated definitions.
    static func maskComponentDigests(
        for layers: [LocalAdjustmentLayer], onlyComponentID: UUID? = nil
    ) -> RenderMaskComponentDigests {
        var digests = RenderMaskComponentDigests()
        for layer in layers {
            for component in layer.components
            where onlyComponentID == nil || component.id == onlyComponentID {
                digests.append(
                    id: component.id, source: component.source,
                    definitionHash: BrushStrokeDigest.definitionDigest(of: component.source)
                )
            }
        }
        return digests
    }

    /// Cold build: digests every component. Memo misses produce exactly this value.
    init(_ document: EditDocument) {
        self.init(inputs: Inputs(document), reusing: [])
    }

    fileprivate init(inputs: Inputs, reusing entries: [RenderDocumentIdentityMemo.Entry]) {
        func digest<V: Equatable & Encodable>(
            _ value: V, _ input: KeyPath<Inputs, V>, _ output: KeyPath<RenderDocumentIdentity, String>
        ) -> String {
            for entry in entries where entry.inputs[keyPath: input] == value {
                let remembered = entry.identity[keyPath: output]
                if !Self.isEncodingFailure(remembered) { return remembered }
            }
            return RenderCacheHash.sessionDigest(value)
        }

        rawDevelop = digest(inputs.rawDevelop, \.rawDevelop, \.rawDevelop)
        prefixUpstream = digest(inputs.prefixUpstream, \.prefixUpstream, \.prefixUpstream)
        // With no temperature/tint node the two synthetic documents are equal, so one digest serves.
        prefixUpstreamWithoutWhiteBalance = inputs.prefixUpstream == inputs.prefixUpstreamWithoutWhiteBalance
            && !Self.isEncodingFailure(prefixUpstream)
            ? prefixUpstream
            : digest(
                inputs.prefixUpstreamWithoutWhiteBalance, \.prefixUpstreamWithoutWhiteBalance,
                \.prefixUpstreamWithoutWhiteBalance)
        localAdjustments = digest(inputs.localAdjustments, \.localAdjustments, \.localAdjustments)
        maskRecipe = digest(inputs.maskRecipe, \.maskRecipe, \.maskRecipe)

        var components = RenderMaskComponentDigests()
        for component in inputs.maskSources {
            let rememberedHash = entries.lazy.compactMap { entry -> String? in
                guard entry.inputs.maskSources.contains(component),
                      let remembered = entry.identity.maskComponents.definitionHash(
                        for: component.id, source: component.source
                      ),
                      !Self.isEncodingFailure(remembered) else { return nil }
                return remembered
            }.first
            components.append(
                id: component.id, source: component.source,
                definitionHash: rememberedHash ?? BrushStrokeDigest.definitionDigest(of: component.source)
            )
        }
        maskComponents = components

        let remainder = digest(inputs.remainder, \.remainder, \.remainderDigest)
        remainderDigest = remainder
        sessionKey = RenderCacheHash.digest(Data(
            [rawDevelop, prefixUpstream, localAdjustments, remainder].joined(separator: "|").utf8
        ))
    }

    /// `RenderCacheHash.digest` returns a unique `encoding-failed:` value for an unencodable
    /// document (a `NaN` field). `Array.==` short-circuits on shared storage, so `==` alone would
    /// call such a value equal to itself; a failed digest is therefore never reused.
    private static func isEncodingFailure(_ digest: String) -> Bool {
        digest.hasPrefix("encoding-failed:")
    }

    /// Digest of the fields outside every other component; kept so memo reuse can find it.
    fileprivate let remainderDigest: String

    /// The equatable values each digest was computed from.
    struct Inputs: Sendable, Equatable {
        struct Remainder: Codable, Sendable, Equatable {
            let crop: CropAdjustments
            let rotation: ImageRotation
            let effects: EffectsAdjustments
        }

        struct MaskComponentSource: Sendable, Equatable {
            let id: UUID
            let source: MaskSource
        }

        let rawDevelop: RAWDevelopSettings
        let prefixUpstream: EditDocument
        let prefixUpstreamWithoutWhiteBalance: EditDocument
        let localAdjustments: [LocalAdjustmentLayer]
        let maskRecipe: RenderEngine.MaskRecipeIdentity
        let maskSources: [MaskComponentSource]
        let remainder: Remainder

        init(_ document: EditDocument) {
            rawDevelop = document.rawDevelop
            prefixUpstream = Self.prefixDocument(document, includeWhiteBalance: true)
            prefixUpstreamWithoutWhiteBalance = Self.prefixDocument(document, includeWhiteBalance: false)
            localAdjustments = document.localAdjustments
            maskRecipe = RenderEngine.MaskRecipeIdentity(document.localAdjustments)
            var sources: [MaskComponentSource] = []
            for layer in document.localAdjustments {
                for component in layer.components {
                    sources.append(MaskComponentSource(id: component.id, source: component.source))
                }
            }
            maskSources = sources
            remainder = Remainder(
                crop: document.crop, rotation: document.rotation, effects: document.effects)
        }

        /// The synthetic document `RenderEngine.prefixDocumentHash` digests today. Retouch is
        /// included because it is composited into the developed image the prefix cache stores.
        private static func prefixDocument(_ document: EditDocument, includeWhiteBalance: Bool) -> EditDocument {
            let adjustments = includeWhiteBalance
                ? document.adjustments
                : document.adjustments.filter {
                    if case .temperatureTint = $0 { return false }
                    return true
                }
            return EditDocument(
                version: document.version, rawDevelop: .neutral, light: document.light,
                color: document.color,
                effects: EffectsAdjustments(
                    texture: document.effects.texture, clarity: document.effects.clarity,
                    dehaze: document.effects.dehaze, detail: document.effects.detail
                ), crop: .neutral, adjustments: adjustments, lut: document.lut,
                retouch: document.retouch
            )
        }
    }
}

/// Bounded memo of recent identities per source. Each incoming component is compared with the
/// remembered values using `==` and reuses the stored digest when equal; only differing components
/// are encoded and hashed. A miss computes the same identity a cold build would, so correctness
/// never depends on the memo. `NaN != NaN` makes such a field always miss, never falsely hit.
struct RenderDocumentIdentityMemo: Sendable {
    struct Entry: Sendable {
        let inputs: RenderDocumentIdentity.Inputs
        let identity: RenderDocumentIdentity
    }

    static let entriesPerSource = 4
    static let sourceLimit = 8

    private var entries: [RenderSourceFingerprint: [Entry]] = [:]
    /// Least recently used first.
    private var sourceOrder: [RenderSourceFingerprint] = []

    var sourceCount: Int { entries.count }
    func entryCount(for source: RenderSourceFingerprint) -> Int { entries[source]?.count ?? 0 }

    mutating func identity(for document: EditDocument, source: RenderSourceFingerprint) -> RenderDocumentIdentity {
        let inputs = RenderDocumentIdentity.Inputs(document)
        var remembered = entries[source] ?? []
        let identity = RenderDocumentIdentity(inputs: inputs, reusing: remembered)

        remembered.removeAll { $0.inputs == inputs }
        remembered.insert(Entry(inputs: inputs, identity: identity), at: 0)
        if remembered.count > Self.entriesPerSource { remembered.removeLast() }
        entries[source] = remembered

        sourceOrder.removeAll { $0 == source }
        sourceOrder.append(source)
        if sourceOrder.count > Self.sourceLimit {
            entries[sourceOrder.removeFirst()] = nil
        }
        return identity
    }

    mutating func removeAll() {
        entries.removeAll()
        sourceOrder.removeAll()
    }
}
