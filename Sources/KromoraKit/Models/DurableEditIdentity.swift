import Synchronization

/// In-memory memo for the durable `EditDocument.editHash` string (KRMA-1099).
///
/// The digest is the same JSON + SHA-256 bytes it always was; the memo only remembers it for the
/// last few distinct document values, matched by `==` on the Auto-stripped document. A miss computes
/// exactly what the uncached path would, so correctness never depends on the memo. Nothing here is
/// persisted and no `Hasher` output is involved.
final class DurableEditIdentityMemo: Sendable {
    static let shared = DurableEditIdentityMemo()

    /// One distinct document value. The digest is computed under the slot's own lock, so concurrent
    /// readers of the same value wait for one computation instead of repeating it.
    private final class Entry: Sendable {
        let document: EditDocument
        private let storage = Mutex<String?>(nil)

        init(document: EditDocument) {
            self.document = document
        }

        var cached: String? { storage.withLock { $0 } }

        /// Returns the digest and whether this call computed it.
        func resolve() -> (digest: String, computed: Bool) {
            storage.withLock { digest in
                if let digest { return (digest, false) }
                let computed = RenderCacheHash.digest(document)
                digest = computed
                return (computed, true)
            }
        }
    }

    private struct State {
        /// Most recently used first.
        var entries: [Entry] = []
        var computations = 0
    }

    private let capacity: Int
    private let state = Mutex(State())

    init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// Number of digests actually computed (memo misses) since creation. Test-visible.
    var computationCount: Int { state.withLock { $0.computations } }

    /// The remembered digest for `document`, without computing one.
    func cachedDigest(for document: EditDocument) -> String? {
        let visible = document.visibleEditValue
        let entry = state.withLock { state in
            state.entries.first { $0.document == visible }
        }
        return entry?.cached
    }

    /// The durable digest for `document`, computed at most once per distinct value while it stays in
    /// the memo, even when several threads ask at once. Safe from any isolation domain, but a miss
    /// hashes on the caller: use `digestOffCaller(for:)` from the main actor.
    func digest(for document: EditDocument) -> String {
        let visible = document.visibleEditValue
        let entry = state.withLock { state -> Entry in
            if let index = state.entries.firstIndex(where: { $0.document == visible }) {
                let entry = state.entries.remove(at: index)
                state.entries.insert(entry, at: 0)
                return entry
            }
            let entry = Entry(document: visible)
            state.entries.insert(entry, at: 0)
            if state.entries.count > capacity { state.entries.removeLast() }
            return entry
        }
        let (digest, computed) = entry.resolve()
        if computed { state.withLock { $0.computations += 1 } }
        return digest
    }

    /// The durable digest, with a miss computed on the concurrent pool so the caller's actor (the
    /// main actor for the preview and thumbnail write paths) is never blocked by a large recipe.
    /// A hit returns without hopping.
    func digestOffCaller(for document: EditDocument) async -> String {
        if let hit = cachedDigest(for: document) { return hit }
        return await Self.computeConcurrently(self, document)
    }

    @concurrent
    private static func computeConcurrently(
        _ memo: DurableEditIdentityMemo, _ document: EditDocument
    ) async -> String {
        memo.digest(for: document)
    }
}
