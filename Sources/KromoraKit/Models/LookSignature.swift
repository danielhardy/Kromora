import Foundation

/// The identity of the Look a set of pixels was (or would be) rendered with.
///
/// One value shared by the preview cache and edited-thumbnail revisions, so both answer "were these
/// pixels made with the Look the document asks for?" the same way and neither depends on whether a
/// library scan happened to finish first.
///
/// - `none`: the document applies no Look.
/// - `resolved`: the document's Look is known by content. The hash is SHA-256 of the `.cube` file
///   bytes — the same domain as `PortablePackageLookReference.contentHash`, so a saved revision and
///   a live `CubeLUT` describe the same bytes identically.
/// - `unresolved`: the document names a Look nothing has resolved (scan pending, or the file is
///   gone). Pixels rendered in this state are provisional (ungraded).
///
/// `Equatable` is structural, so `none != unresolved`. Equality is not exactness, though: two
/// unresolved signatures are equal but say nothing about the missing bytes, so cache and revision
/// reuse must go through `permitsExactReuse` / `isExactMatch(of:)`.
enum LookSignature: Codable, Equatable, Hashable, Sendable {
    case none
    case resolved(id: LUTID, contentHash: String)
    case unresolved(id: LUTID)

    /// Signature of a render: `lut` is what the renderer will actually apply.
    ///
    /// A document whose Look is off (`isIdentity`) is `none` even when a table is supplied, because
    /// the pipeline applies nothing in that case.
    init(settings: LUTSettings, resolved lut: CubeLUT?) {
        guard !settings.isIdentity, let id = settings.lutID else {
            self = .none
            return
        }
        if let lut {
            self = lut.lookSignature
        } else {
            self = .unresolved(id: id)
        }
    }

    /// Signature of a saved revision, from the content-addressed reference stored beside it. This
    /// is how a package-backed edit knows its Look bytes without the Look browser having scanned.
    init(settings: LUTSettings, reference: PortablePackageLookReference?) {
        guard !settings.isIdentity, let id = settings.lutID else {
            self = .none
            return
        }
        if let reference {
            self = .resolved(id: id, contentHash: reference.contentHash)
        } else {
            self = .unresolved(id: id)
        }
    }

    var lutID: LUTID? {
        switch self {
        case .none: return nil
        case .resolved(let id, _), .unresolved(let id): return id
        }
    }

    /// False only for `unresolved`: its pixels may be shown provisionally but never stand in for
    /// an exact result, in either direction.
    var permitsExactReuse: Bool {
        if case .unresolved = self { return false }
        return true
    }

    func isExactMatch(of other: LookSignature) -> Bool {
        permitsExactReuse && self == other
    }

    func references(anyOf ids: Set<LUTID>) -> Bool {
        lutID.map(ids.contains) ?? false
    }

    /// Stable text form for file names and string-keyed revisions. Derive nothing from it; compare
    /// signatures as values.
    var cacheComponent: String {
        switch self {
        case .none: return "look-none"
        case .resolved(let id, let hash): return "look-resolved:\(hash):\(id.raw)"
        case .unresolved(let id): return "look-unresolved:\(id.raw)"
        }
    }
}

extension CubeLUT {
    /// This table's own identity: its `LUTID` plus the hash of the file bytes it was parsed from.
    var lookSignature: LookSignature {
        .resolved(id: lutID, contentHash: contentHash)
    }
}

extension RenderRequest {
    var lookSignature: LookSignature {
        LookSignature(settings: document.lut, resolved: lut)
    }
}

/// `[LUTID: contentHash]` for every Look the browser currently holds, published by `LUTLibrary`
/// with each completed scan or import.
struct LookLibrarySnapshot: Sendable, Equatable {
    let contentHashes: [LUTID: String]

    static let empty = LookLibrarySnapshot(contentHashes: [:])

    init(contentHashes: [LUTID: String]) {
        self.contentHashes = contentHashes
    }

    init(looks: [CubeLUT]) {
        self.contentHashes = Dictionary(
            looks.map { ($0.lutID, $0.contentHash) }, uniquingKeysWith: { _, last in last }
        )
    }

    /// What differs between `previous` and this snapshot. A byte-identical rescan is empty.
    func delta(from previous: LookLibrarySnapshot) -> LookLibraryDelta {
        var changed = Set<LUTID>()
        var appeared = Set<LUTID>()
        for (id, hash) in contentHashes {
            guard let old = previous.contentHashes[id] else {
                appeared.insert(id)
                continue
            }
            if old != hash { changed.insert(id) }
        }
        let disappeared = Set(previous.contentHashes.keys).subtracting(contentHashes.keys)
        return LookLibraryDelta(changed: changed, appeared: appeared, disappeared: disappeared)
    }
}

struct LookLibraryDelta: Sendable, Equatable {
    /// Present before and after with different bytes.
    let changed: Set<LUTID>
    let appeared: Set<LUTID>
    let disappeared: Set<LUTID>

    static let empty = LookLibraryDelta(changed: [], appeared: [], disappeared: [])

    var isEmpty: Bool { changed.isEmpty && appeared.isEmpty && disappeared.isEmpty }

    /// Every ID whose resolution result differs from before the scan.
    var affected: Set<LUTID> { changed.union(appeared).union(disappeared) }
}
