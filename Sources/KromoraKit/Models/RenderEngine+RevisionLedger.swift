import Foundation

extension RenderEngine {
    /// Bounded bookkeeping for render/mask request supersession, owned by `RenderEngine` but kept
    /// as a plain `Sendable` value so its eviction arithmetic is unit-testable without an actor or
    /// a GPU. Every dictionary here is paired with an insertion/recency-ordered array so eviction
    /// never has to rescan the dictionary for the oldest entry (KRMA-530): unbounded navigation
    /// through many sources previously grew `latestRenderRequestRevisions` forever, and the mask
    /// ledger's cap enforcement repeatedly called `.min(by:)`, which is O(n) per evicted entry.
    struct RevisionLedger: Sendable {
        /// Latest request revision admitted for each source. Independent of mask revisions: an
        /// unmasked interactive render still needs a pre-submit supersession fence.
        private var latestRenderRequestRevisions: [String: UInt64] = [:]
        /// Recency order for `latestRenderRequestRevisions`, oldest first. A source is moved to the
        /// end whenever its revision is touched, so eviction always drops the least-recently-seen
        /// source rather than rescanning for a minimum.
        private var renderRequestOrder: [String] = []
        private let maximumTrackedRenderSources: Int

        /// Render-domain supersession is keyed by source and full document identity. This lets a
        /// global-only edit keep an older local-mask resolution alive while still rejecting a
        /// lagging render of the same document revision. Local-mask recipe changes invalidate
        /// every older document entry for that source.
        private var latestMaskRequestRevisions: [String: UInt64] = [:]
        /// Insertion order for `latestMaskRequestRevisions` keys, oldest first.
        private var maskRequestOrder: [String] = []
        private var latestMaskRecipeIdentities: [String: String] = [:]
        /// Dictionary iteration order is undefined, so keep the source insertion order separately
        /// for the bounded supersession table. A recipe replacement makes that source the newest
        /// entry.
        private var maskSourceOrder: [String] = []
        /// Overlay requests intentionally remain source-wide: the overlay has no document identity
        /// and must still reject a stale nonzero revision after a preview render has started.
        private var latestOverlayMaskRequestRevisions: [String: UInt64] = [:]
        private let maximumTrackedMaskSources: Int
        private let maximumTrackedMaskRequests: Int

        init(
            maximumTrackedRenderSources: Int = 64,
            maximumTrackedMaskSources: Int = 16,
            maximumTrackedMaskRequests: Int = 64
        ) {
            self.maximumTrackedRenderSources = maximumTrackedRenderSources
            self.maximumTrackedMaskSources = maximumTrackedMaskSources
            self.maximumTrackedMaskRequests = maximumTrackedMaskRequests
        }

        // MARK: - Render revisions

        mutating func noteRenderRequest(sourceKey: String, revision: UInt64) {
            guard revision > 0 else { return }
            if latestRenderRequestRevisions[sourceKey, default: 0] < revision {
                latestRenderRequestRevisions[sourceKey] = revision
            }
            touch(sourceKey, in: &renderRequestOrder)
            while latestRenderRequestRevisions.count > maximumTrackedRenderSources,
                  !renderRequestOrder.isEmpty {
                let oldest = renderRequestOrder.removeFirst()
                latestRenderRequestRevisions.removeValue(forKey: oldest)
            }
        }

        func latestRenderRevision(sourceKey: String) -> UInt64 {
            latestRenderRequestRevisions[sourceKey, default: 0]
        }

        func isCurrentRenderRequest(sourceKey: String, revision: UInt64) -> Bool {
            guard revision > 0 else { return true }
            return latestRenderRequestRevisions[sourceKey, default: 0] <= revision
        }

        // MARK: - Overlay mask revisions

        mutating func noteOverlayMaskRequest(sourceKey: String, revision: UInt64) {
            guard revision > 0 else { return }
            if latestOverlayMaskRequestRevisions[sourceKey, default: 0] < revision {
                latestOverlayMaskRequestRevisions[sourceKey] = revision
            }
        }

        func isCurrentOverlayMaskRequest(sourceKey: String, revision: UInt64) -> Bool {
            guard revision > 0 else { return true }
            return latestOverlayMaskRequestRevisions[sourceKey] == revision
        }

        // MARK: - Recipe-scoped mask revisions

        /// Records a revisioned mask request and returns whether the source's mask recipe changed,
        /// so the caller (actor-isolated `RenderEngine`) can cancel any in-flight semantic
        /// resolution for the old recipe. In-flight `Task`s are not `Sendable` state this value type
        /// can own, so that cancellation stays the actor's responsibility.
        mutating func noteMaskRequest(
            sourceKey: String, revision: UInt64, maskIdentity: String, documentIdentity: String
        ) -> Bool {
            guard revision > 0 else { return false }
            let recipeChanged = latestMaskRecipeIdentities[sourceKey] != maskIdentity
            if recipeChanged {
                latestMaskRecipeIdentities[sourceKey] = maskIdentity
                touch(sourceKey, in: &maskSourceOrder)
                removeMaskRequests(withSourcePrefix: sourceKey)
            }
            let documentKey = sourceKey + "|" + documentIdentity
            if latestMaskRequestRevisions[documentKey, default: 0] < revision {
                if latestMaskRequestRevisions[documentKey] == nil {
                    maskRequestOrder.append(documentKey)
                }
                latestMaskRequestRevisions[documentKey] = revision
            }
            noteOverlayMaskRequest(sourceKey: sourceKey, revision: revision)
            trimMaskRequestState()
            return recipeChanged
        }

        func isCurrentMaskRequest(
            sourceKey: String, revision: UInt64, maskIdentity: String, documentIdentity: String
        ) -> Bool {
            guard revision > 0 else { return true }
            return latestMaskRecipeIdentities[sourceKey] == maskIdentity
                && latestMaskRequestRevisions[sourceKey + "|" + documentIdentity] == revision
        }

        var trackedMaskSourceKeys: [String] { maskSourceOrder }

        // MARK: - Diagnostics (stress test seams)

        var trackedRenderSourceCount: Int { latestRenderRequestRevisions.count }
        var trackedMaskRequestCount: Int { latestMaskRequestRevisions.count }
        var trackedMaskSourceCount: Int { latestMaskRecipeIdentities.count }

        // MARK: - Resets

        /// Clears only the recipe-scoped mask bookkeeping. Used by memory-pressure eviction and
        /// explicit render-cache invalidation, which have never reset render-request supersession
        /// fences — doing so would let an already-superseded render slip back through.
        mutating func clearMaskRequestState() {
            latestMaskRequestRevisions.removeAll(keepingCapacity: true)
            maskRequestOrder.removeAll(keepingCapacity: true)
            latestMaskRecipeIdentities.removeAll(keepingCapacity: true)
            maskSourceOrder.removeAll(keepingCapacity: true)
            latestOverlayMaskRequestRevisions.removeAll(keepingCapacity: true)
        }

        /// Clears every ledger, including render-request supersession. Used by a full source-cache
        /// invalidation, where no in-flight render for the old source should be able to win a race.
        mutating func removeAll() {
            latestRenderRequestRevisions.removeAll(keepingCapacity: true)
            renderRequestOrder.removeAll(keepingCapacity: true)
            clearMaskRequestState()
        }

        // MARK: - Private

        private mutating func removeMaskRequests(withSourcePrefix sourceKey: String) {
            let prefix = sourceKey + "|"
            let staleKeys = latestMaskRequestRevisions.keys.filter { $0.hasPrefix(prefix) }
            guard !staleKeys.isEmpty else { return }
            let staleKeySet = Set(staleKeys)
            for key in staleKeys { latestMaskRequestRevisions.removeValue(forKey: key) }
            maskRequestOrder.removeAll { staleKeySet.contains($0) }
        }

        private mutating func trimMaskRequestState() {
            while latestMaskRecipeIdentities.count > maximumTrackedMaskSources,
                  !maskSourceOrder.isEmpty {
                let oldestSource = maskSourceOrder.removeFirst()
                guard latestMaskRecipeIdentities.removeValue(forKey: oldestSource) != nil else {
                    continue
                }
                latestOverlayMaskRequestRevisions.removeValue(forKey: oldestSource)
                removeMaskRequests(withSourcePrefix: oldestSource)
            }
            // Bounded FIFO eviction: each iteration removes the oldest tracked document key in
            // O(1) amortized time rather than rescanning the whole table for a minimum revision.
            while latestMaskRequestRevisions.count > maximumTrackedMaskRequests,
                  !maskRequestOrder.isEmpty {
                let oldest = maskRequestOrder.removeFirst()
                latestMaskRequestRevisions.removeValue(forKey: oldest)
            }
        }

        private func touch(_ key: String, in order: inout [String]) {
            order.removeAll { $0 == key }
            order.append(key)
        }
    }
}
