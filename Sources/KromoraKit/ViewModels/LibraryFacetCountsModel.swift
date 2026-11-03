import Foundation

/// The published facet-count snapshot for the Library filter sidebar.
///
/// Counts are keyed to the query plus the index revision they were requested for. A request is
/// debounced so a burst of index changes (an import, a metadata backfill) coalesces into one
/// computation, and its result is published only if the task was not cancelled and no newer
/// request has begun. Categorical counts, numeric bounds, and the unread-metadata count are one
/// `LibraryFacetCounts` value, so they always update together.
@MainActor
@Observable
final class LibraryFacetCountsModel {
    struct Key: Equatable, Sendable {
        var query: LibraryQuery
        var indexRevision: UInt64
    }

    private(set) var counts = LibraryFacetCounts()

    @ObservationIgnored private var latestRequest: Key?
    @ObservationIgnored private var latestSequence: UInt64 = 0

    /// Computes counts for `key` after `debounce` and publishes them if the request is still the
    /// newest. `compute` returns nil when no library is open, which leaves the snapshot unchanged.
    func refresh(
        for key: Key, debounce: Duration = .milliseconds(150),
        compute: @MainActor (LibraryQuery) async -> LibraryFacetCounts?
    ) async {
        latestSequence &+= 1
        let sequence = latestSequence
        latestRequest = key
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
        }
        guard !Task.isCancelled, sequence == latestSequence else { return }
        let result = await compute(key.query)
        guard !Task.isCancelled, sequence == latestSequence, let result else { return }
        counts = result
    }
}
