import Synchronization

/// In-memory memo for the durable `EditDocument.editHash` string (KRMA-1099).
///
/// The digest is the same JSON + SHA-256 bytes it always was; the memo only remembers it for the
/// last few distinct document values, matched by `==` on the Auto-stripped document. A miss computes
/// exactly what the uncached path would, so correctness never depends on the memo. Nothing here is
/// persisted and no `Hasher` output is involved.
final class DurableEditIdentityMemo: Sendable {
    static let shared = DurableEditIdentityMemo()

    private struct Entry {
        let document: EditDocument
        let digest: String
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
        return state.withLock { state in
            state.entries.first { $0.document == visible }?.digest
        }
    }

    /// The durable digest for `document`, computed at most once per distinct value while it stays in
    /// the memo. Safe from any isolation domain; the digest runs outside the lock.
    func digest(for document: EditDocument) -> String {
        let visible = document.visibleEditValue
        let hit = state.withLock { state -> String? in
            guard let index = state.entries.firstIndex(where: { $0.document == visible }) else {
                return nil
            }
            let entry = state.entries.remove(at: index)
            state.entries.insert(entry, at: 0)
            return entry.digest
        }
        if let hit { return hit }
        let digest = RenderCacheHash.digest(visible)
        state.withLock { state in
            state.computations += 1
            if !state.entries.contains(where: { $0.document == visible }) {
                state.entries.insert(Entry(document: visible, digest: digest), at: 0)
                if state.entries.count > capacity { state.entries.removeLast() }
            }
        }
        return digest
    }
}
