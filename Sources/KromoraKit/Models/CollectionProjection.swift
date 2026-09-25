import Foundation

/// Pure projections used by the package-backed library presentation adapter.
enum CollectionProjection {
    struct Snapshot {
        let filteredIndices: [Int]
        let thumbnailEntries: [ImageCollection.ThumbnailEntry]
    }

    /// A class so a hit does not write the property that stores this cache.
    ///
    /// `ImageCollection` is `@Observable`. A struct cache's `mutating` method is written back
    /// on every call, including a hit. The library grid reads that projection from its body, so
    /// the write schedules another update inside the same transaction and the window never
    /// returns to the event loop.
    final class Cache {
        private var key: Key?
        private var value: Snapshot?
        private(set) var rebuildCount = 0

        private struct Key: Equatable {
            let collectionRevision: UInt64
            let filterRevision: UInt64
        }

        func snapshot(
            items: [ImageCollection.Item], filter: LibraryFilter,
            collectionRevision: UInt64, filterRevision: UInt64
        ) -> Snapshot {
            let nextKey = Key(collectionRevision: collectionRevision, filterRevision: filterRevision)
            if key == nextKey, let value { return value }
            let indices = filteredIndices(items: items, filter: filter)
            let entries = indices.map { index in
                ImageCollection.ThumbnailEntry(
                    id: items[index].id, itemIndex: index,
                    aspectRatio: items[index].libraryAspectRatio,
                    aspectResolved: items[index].hasResolvedLibraryAspect
                )
            }
            let next = Snapshot(filteredIndices: indices, thumbnailEntries: entries)
            key = nextKey
            value = next
            rebuildCount += 1
            return next
        }
    }

    static func selectedIndices(
        items: [ImageCollection.Item], selection: LibrarySelectionModel
    ) -> [Int] {
        items.indices.filter { selection.selectedIDs.contains(items[$0].id) }
    }

    static func filteredIndices(
        items: [ImageCollection.Item], filter: LibraryFilter
    ) -> [Int] {
        items.indices.filter {
            filter.matches(flag: items[$0].asset.flag, rating: items[$0].asset.rating)
        }
    }
}
