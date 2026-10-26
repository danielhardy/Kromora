import Foundation
import Synchronization

/// Session-tier digests for brush strokes (KRMA-1102, `docs/RENDER_KEY_PLAN.md`).
///
/// A stroke's digest is the stable `RenderCacheHash.digest(stroke)`. The memo reuses a remembered
/// digest when the incoming stroke is `==` to the stroke it was computed from, which is O(1) for
/// unchanged strokes that share sample storage. Painting therefore encodes only the stroke being
/// drawn. Both `RenderDocumentIdentity` (mask definition digests) and `LocalMaskRenderer` (stroke
/// raster cache keys) read from the same memo. Values are never persisted.
enum BrushStrokeDigest {
    /// Remembered values per stroke ID. Duplicate IDs in persisted data share a bucket, and `==`
    /// still decides every hit, so a repeated ID can never alias distinct strokes.
    private static let entriesPerID = 4
    private static let idLimit = 4096

    private struct Entry {
        let stroke: BrushStroke
        let digest: String
    }

    private static let memo = Mutex<[UUID: [Entry]]>([:])

    static func digest(of stroke: BrushStroke) -> String {
        if let remembered = memo.withLock({ $0[stroke.id]?.first { $0.stroke == stroke }?.digest }) {
            return remembered
        }
        let digest = RenderCacheHash.digest(stroke)
        // A failed digest is unique per call; remembering it would turn it into a shared identity.
        guard !digest.hasPrefix("encoding-failed:") else { return digest }
        memo.withLock { entries in
            if entries.count >= idLimit, entries[stroke.id] == nil { entries.removeAll() }
            var bucket = entries[stroke.id] ?? []
            bucket.removeAll { $0.stroke == stroke }
            bucket.insert(Entry(stroke: stroke, digest: digest), at: 0)
            if bucket.count > entriesPerID { bucket.removeLast() }
            entries[stroke.id] = bucket
        }
        return digest
    }

    /// Deterministic SHA-256 over the ordered per-stroke digests. Reordering, editing, adding, or
    /// removing a stroke changes it; an unchanged stroke list keeps it.
    static func definitionDigest(of definition: BrushMaskDefinition) -> String {
        var payload = "brush-strokes-v1"
        for stroke in definition.strokes {
            let strokeDigest = digest(of: stroke)
            // Hashing a unique failure would make it a stable, shareable identity again.
            if strokeDigest.hasPrefix("encoding-failed:") { return strokeDigest }
            payload += "|" + strokeDigest
        }
        return RenderCacheHash.digest(Data(payload.utf8))
    }

    /// Definition digest for any mask source; brush sources compose per-stroke digests.
    static func definitionDigest(of source: MaskSource) -> String {
        if case .brush(let definition) = source { return definitionDigest(of: definition) }
        return RenderCacheHash.digest(source)
    }

    /// `JSONEncoder.userInfo` flag selecting the session-only brush encoding.
    static let sessionIdentityKey = CodingUserInfoKey(rawValue: "Kromora.sessionBrushIdentity")!

    static func removeAll() { memo.withLock { $0.removeAll() } }
}
