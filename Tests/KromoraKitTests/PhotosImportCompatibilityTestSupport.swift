import Foundation
@testable import KromoraKit

@MainActor
private final class AppViewModelPhotosImportProvider: PhotosImportProviding {
    private let items: [(name: String, data: Data)]

    init(items: [(name: String, data: Data)]) {
        self.items = items
    }

    func originalFilename(for selection: PhotosImportSelection) -> String? {
        guard items.indices.contains(selection.ordinal) else { return nil }
        return items[selection.ordinal].name
    }

    func transferData(for selection: PhotosImportSelection) async throws -> Data? {
        guard items.indices.contains(selection.ordinal) else { return nil }
        return items[selection.ordinal].data
    }
}

/// Compatibility helpers for older tests. The production facade was removed; these calls now
/// exercise the coordinator directly with the application model as its destination.
@MainActor
extension AppViewModel {
    func beginPhotosImport(totalCount: Int) {
        photosImportCoordinator.begin(totalCount: totalCount)
    }

    func appendPhotosImport(_ item: ImageCollection.PhotoImportItem, ordinal: Int) {
        photosImportCoordinator.append(item, ordinal: ordinal)
    }

    func recordPhotosImportFailure(name: String, ordinal: Int? = nil) {
        photosImportCoordinator.recordFailure(
            name: name, ordinal: ordinal, reason: "Photos returned no transferable data."
        )
    }

    func finishPhotosImport(cancelled: Bool) {
        photosImportCoordinator.finish(cancelled: cancelled)
    }

    func importPhotosData(_ items: [(name: String, data: Data)]) {
        photosImportCoordinator.start(
            selections: items.indices.map {
                PhotosImportSelection(ordinal: $0, localIdentifier: "test.photos.\($0)")
            },
            provider: AppViewModelPhotosImportProvider(items: items)
        )
    }
}
