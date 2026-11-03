import Dispatch
import Synchronization

/// In-memory memo for the durable `EditDocument.editHash` string (KRMA-1099).
///
/// The digest is the same JSON + SHA-256 bytes it always was; the memo only remembers it for the
/// last few distinct document values, matched by `==` on the Auto-stripped document. A miss computes
/// exactly what the uncached path would, so correctness never depends on the memo. Nothing here is
/// persisted and no `Hasher` output is involved.
///
/// Locks only guard bookkeeping (the entry list, one entry's phase). Hashing and the `==` scans over
/// large recipes run with no lock held, so a lookup never waits behind another consumer's hash:
/// completed digests are read without blocking and in-flight work is shared by awaiting it.

final class DurableEditIdentityMemo: Sendable {
    static let shared = DurableEditIdentityMemo()

    /// One distinct document value and the lifecycle of its digest.
    private final class Entry: Sendable {
        enum Claim {
            case done(String)
            /// The caller owns the computation and must call `finish`.
            case compute
            /// Another consumer is computing; join with `addWaiter`.
            case wait
        }

        private enum Phase {
            case idle
            case computing(waiters: [@Sendable (String) -> Void])
            case done(String)
        }

        let document: EditDocument
        private let phase = Mutex(Phase.idle)

        init(document: EditDocument) {
            self.document = document
        }

        /// The finished digest, or nil while idle or in flight. Never waits for hashing.
        var completed: String? {
            phase.withLock {
                if case .done(let digest) = $0 { return digest }
                return nil
            }
        }

        func claim() -> Claim {
            phase.withLock {
                switch $0 {
                case .done(let digest): return .done(digest)
                case .idle:
                    $0 = .computing(waiters: [])
                    return .compute
                case .computing: return .wait
                }
            }
        }

        /// Registers `waiter` for an in-flight computation, or returns the digest if it finished
        /// since `claim()`. A returned digest means `waiter` was not registered.
        func addWaiter(_ waiter: @escaping @Sendable (String) -> Void) -> String? {
            phase.withLock {
                switch $0 {
                case .done(let digest): return digest
                case .computing(var waiters):
                    waiters.append(waiter)
                    $0 = .computing(waiters: waiters)
                    return nil
                case .idle: preconditionFailure("waiting on an entry nobody claimed")
                }
            }
        }

        func finish(_ digest: String) {
            let waiters = phase.withLock { phase -> [@Sendable (String) -> Void] in
                defer { phase = .done(digest) }
                if case .computing(let waiters) = phase { return waiters }
                return []
            }
            for waiter in waiters { waiter(digest) }
        }
    }

    private struct State {
        /// Most recently used first.
        var entries: [Entry] = []
        /// Bumped on every insertion, so a lookup can tell its snapshot went stale.
        var revision = 0
        var computations = 0
    }

    private let capacity: Int
    private let hasher: @Sendable (EditDocument) -> String
    private let state = Mutex(State())

    /// `hasher` is a test seam; production always uses the durable `RenderCacheHash.digest`.
    init(capacity: Int = 8, hasher: @escaping @Sendable (EditDocument) -> String = RenderCacheHash.digest) {
        self.capacity = capacity
        self.hasher = hasher
    }

    /// Number of digests actually computed (memo misses) since creation. Test-visible.
    var computationCount: Int { state.withLock { $0.computations } }

    /// The remembered digest for `document`, without computing one and without waiting on a
    /// computation another consumer has in flight.
    func cachedDigest(for document: EditDocument) -> String? {
        entry(for: document.visibleEditValue, insertingIfMissing: false)?.completed
    }

    /// The durable digest for `document`, computed at most once per distinct value while it stays in
    /// the memo, even when several threads ask at once. Safe from any isolation domain, but a miss
    /// hashes on the caller and a concurrent in-flight computation blocks the calling thread until
    /// it finishes: use `digestOffCaller(for:)` from the main actor.
    func digest(for document: EditDocument) -> String {
        guard let entry = entry(for: document.visibleEditValue, insertingIfMissing: true) else {
            preconditionFailure("insertion always yields an entry")
        }
        switch entry.claim() {
        case .done(let digest): return digest
        case .compute: return compute(entry)
        case .wait:
            let signal = DispatchSemaphore(value: 0)
            if let digest = entry.addWaiter({ _ in signal.signal() }) { return digest }
            signal.wait()
            return entry.completed ?? compute(entry)
        }
    }

    /// The durable digest, with a miss computed on the concurrent pool so the caller's actor (the
    /// main actor for the preview and thumbnail write paths) is never blocked by a large recipe.
    /// A hit returns without hopping, and a value another consumer is already hashing is awaited
    /// rather than waited on, so the caller's thread stays free.
    ///
    /// Cancellation does not interrupt the shared computation: a cancelled consumer still receives
    /// the digest and the other consumers are unaffected.
    func digestOffCaller(for document: EditDocument) async -> String {
        guard let entry = entry(for: document.visibleEditValue, insertingIfMissing: true) else {
            preconditionFailure("insertion always yields an entry")
        }
        switch entry.claim() {
        case .done(let digest): return digest
        case .compute: return await Self.computeConcurrently(self, entry)
        case .wait:
            return await withCheckedContinuation { continuation in
                if let digest = entry.addWaiter({ continuation.resume(returning: $0) }) {
                    continuation.resume(returning: digest)
                }
            }
        }
    }

    @concurrent
    private static func computeConcurrently(
        _ memo: DurableEditIdentityMemo, _ entry: Entry
    ) async -> String {
        memo.compute(entry)
    }

    /// Hashes with no lock held, then publishes to the entry's waiters.
    private func compute(_ entry: Entry) -> String {
        let digest = hasher(entry.document)
        state.withLock { $0.computations += 1 }
        entry.finish(digest)
        return digest
    }

    /// Finds the entry equal to `visible`, promoting it to most recently used, or inserts one.
    /// The `==` scans run on a snapshot outside the lock; a stale snapshot only costs scanning
    /// the entries inserted since.
    private func entry(for visible: EditDocument, insertingIfMissing: Bool) -> Entry? {
        var scanned = Set<ObjectIdentifier>()
        while true {
            let (snapshot, revision) = state.withLock { ($0.entries, $0.revision) }
            for entry in snapshot where scanned.insert(ObjectIdentifier(entry)).inserted {
                guard entry.document == visible else { continue }
                if insertingIfMissing { promote(entry) }
                return entry
            }
            guard insertingIfMissing else { return nil }
            let created = state.withLock { state -> Entry? in
                guard state.revision == revision else { return nil }
                let entry = Entry(document: visible)
                state.entries.insert(entry, at: 0)
                if state.entries.count > capacity { state.entries.removeLast() }
                state.revision += 1
                return entry
            }
            if let created { return created }
        }
    }

    private func promote(_ entry: Entry) {
        state.withLock { state in
            guard let index = state.entries.firstIndex(where: { $0 === entry }), index != 0 else {
                return
            }
            state.entries.insert(state.entries.remove(at: index), at: 0)
        }
    }
}
