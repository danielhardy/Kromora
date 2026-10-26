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
    /// Retained-byte accounting budget for remembered strokes. Sample-buffer capacity is charged
    /// at `MemoryLayout<BrushSample>.stride` per slot, plus fixed per-entry overhead, so spare
    /// capacity and long strokes count against the limit. 32 MiB holds roughly 1M sample slots
    /// before per-entry overhead, far beyond a realistic recipe (a long stroke is a few thousand samples).
    static let defaultByteBudget = 32 * 1024 * 1024
    private static let memo = Mutex<Memo>(Memo(byteBudget: defaultByteBudget))

    /// Least-recently-used memo bounded by bytes and by distinct stroke IDs. Eviction drops whole
    /// IDs, oldest first, in one batch down to a low-water mark, so a recipe slightly over budget
    /// does not re-scan on every paint tick and never clears the strokes still in use.
    struct Memo {
        /// Remembered values per stroke ID. Duplicate IDs in persisted data share a bucket, and `==`
        /// still decides every hit, so a repeated ID can never alias distinct strokes.
        static let entriesPerID = 4
        static let idLimit = 65_536
        private static let entryOverhead = 192

        private struct Entry {
            let stroke: BrushStroke
            let digest: String
            var cost: Int {
                stroke.samples.capacity * MemoryLayout<BrushSample>.stride
                    + Memo.entryOverhead + digest.utf8.count
            }
        }
        private struct Bucket {
            var entries: [Entry]
            var lastUse: UInt64
            var cost: Int { entries.reduce(0) { $0 + $1.cost } }
        }

        let byteBudget: Int
        let idLimit: Int
        private var buckets: [UUID: Bucket] = [:]
        private var tick: UInt64 = 0
        private(set) var retainedBytes = 0

        init(byteBudget: Int, idLimit: Int = Memo.idLimit) {
            self.byteBudget = max(0, byteBudget)
            self.idLimit = max(1, idLimit)
        }

        var idCount: Int { buckets.count }

        mutating func lookup(_ stroke: BrushStroke) -> String? {
            guard var bucket = buckets[stroke.id],
                let hit = bucket.entries.first(where: { $0.stroke == stroke })
            else { return nil }
            tick &+= 1
            bucket.lastUse = tick
            buckets[stroke.id] = bucket
            return hit.digest
        }

        mutating func store(_ stroke: BrushStroke, digest: String) {
            let entry = Entry(stroke: stroke, digest: digest)
            // A single stroke over budget is never retained; it would evict everything else.
            guard entry.cost <= byteBudget else {
                return
            }
            var bucket = buckets[stroke.id] ?? Bucket(entries: [], lastUse: 0)
            retainedBytes -= bucket.cost
            bucket.entries.removeAll { $0.stroke == stroke }
            bucket.entries.insert(entry, at: 0)
            while bucket.entries.count > Self.entriesPerID { bucket.entries.removeLast() }
            // Keep the bucket within budget even when duplicate-ID siblings are large.
            while bucket.entries.count > 1 && bucket.cost > byteBudget { bucket.entries.removeLast() }
            tick &+= 1
            bucket.lastUse = tick
            retainedBytes += bucket.cost
            buckets[stroke.id] = bucket
            evictIfNeeded(keeping: stroke.id)
        }

        mutating func removeAll() {
            buckets.removeAll()
            retainedBytes = 0
        }

        private mutating func remove(_ id: UUID) {
            if let old = buckets.removeValue(forKey: id) { retainedBytes -= old.cost }
        }

        private mutating func evictIfNeeded(keeping id: UUID) {
            guard retainedBytes > byteBudget || buckets.count > idLimit else { return }
            // Evict to 3/4 of each limit so the next ticks do not immediately re-trigger.
            let byteTarget = byteBudget / 4 * 3
            let countTarget = idLimit / 4 * 3
            let oldestFirst = buckets.filter { $0.key != id }.sorted { $0.value.lastUse < $1.value.lastUse }
            for (victim, _) in oldestFirst {
                if retainedBytes <= byteTarget && buckets.count <= max(countTarget, 1) { break }
                remove(victim)
            }
        }
    }

    static func digest(of stroke: BrushStroke) -> String {
        if let remembered = memo.withLock({ $0.lookup(stroke) }) { return remembered }
        let digest = RenderCacheHash.digest(stroke)
        // A failed digest is unique per call; remembering it would turn it into a shared identity.
        guard !digest.hasPrefix("encoding-failed:") else { return digest }
        memo.withLock { $0.store(stroke, digest: digest) }
        return digest
    }

    /// Completed definition digests for the few most recently requested brush components, so
    /// repeated overlay requests for an unchanged component skip rebuilding the ordered payload.
    /// Hits are decided by `==`, so any change to the strokes misses. Session-only, never persisted.
    struct DefinitionMemo {
        static let entryLimit = 4
        private var entries: [(definition: BrushMaskDefinition, digest: String)] = []

        mutating func lookup(_ definition: BrushMaskDefinition) -> String? {
            guard let index = entries.firstIndex(where: { $0.definition == definition }) else { return nil }
            let hit = entries.remove(at: index)
            entries.insert(hit, at: 0)
            return hit.digest
        }

        mutating func store(_ definition: BrushMaskDefinition, digest: String) {
            entries.removeAll { $0.definition == definition }
            entries.insert((definition, digest), at: 0)
            while entries.count > Self.entryLimit { entries.removeLast() }
        }

        mutating func removeAll() { entries.removeAll() }
    }
    private static let definitionMemo = Mutex<DefinitionMemo>(DefinitionMemo())
    private static let definitionComputationCount = Atomic<Int>(0)

    /// Diagnostics for tests: number of definition digests built without a definition-memo hit.
    static var definitionComputations: Int { definitionComputationCount.load(ordering: .relaxed) }

    /// Diagnostics for tests: bytes and IDs currently retained by the process-wide memo.
    static var retained: (bytes: Int, ids: Int) { memo.withLock { ($0.retainedBytes, $0.idCount) } }

    /// Deterministic SHA-256 over the ordered per-stroke digests. Reordering, editing, adding, or
    /// removing a stroke changes it; an unchanged stroke list keeps it.
    static func definitionDigest(of definition: BrushMaskDefinition) -> String {
        if let remembered = definitionMemo.withLock({ $0.lookup(definition) }) { return remembered }
        let digest = computeDefinitionDigest(of: definition)
        guard !digest.hasPrefix("encoding-failed:") else { return digest }
        definitionMemo.withLock { $0.store(definition, digest: digest) }
        return digest
    }

    private static func computeDefinitionDigest(of definition: BrushMaskDefinition) -> String {
        definitionComputationCount.add(1, ordering: .relaxed)
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

    static func removeAll() {
        memo.withLock { $0.removeAll() }
        definitionMemo.withLock { $0.removeAll() }
    }
}
