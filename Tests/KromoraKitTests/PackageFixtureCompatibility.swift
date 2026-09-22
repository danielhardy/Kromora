import Foundation
@testable import KromoraKit

/// Transitional fixture adapters for tests that still describe their input as a folder.
/// Production has no corresponding API: these helpers immediately turn fixture files into the
/// package presentation model so the old test cases can be migrated incrementally.
@MainActor
extension ImageCollection {
    var libraryFolderURL: URL {
        items.first?.url?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("KromoraPackageFixture")
    }

    static var defaultLibraryFolderURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KromoraPackageFixture")
    }

    var sourceFolderURL: URL? { nil }
    var hasActiveSourceFolderScopeForTesting: Bool { false }
    var pendingImportSlots: [Int] { [] }

    func metadataCompletion() async { await scanCompletion() }

    func loadFromFolder(_ folder: URL) {
        let urls = (FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )?.compactMap { value -> URL? in
            guard let url = value as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  ImageDecoder.supportedExtensions.contains(url.pathExtension.lowercased())
            else { return nil }
            return url
        } ?? []).sorted {
            let lhs = $0.deletingPathExtension().lastPathComponent
            let rhs = $1.deletingPathExtension().lastPathComponent
            let nameOrder = lhs.localizedStandardCompare(rhs)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.standardizedFileURL.path < $1.standardizedFileURL.path
        }
        loadPortableAssets(urls.map { PhotoAsset(url: $0) })
        // The former folder-backed fixture selected the first discovered photo while its scan
        // settled. Preserve that compatibility contract for tests that enter Edit without an
        // explicit grid click; the production package path mirrors selection from its query
        // controller instead.
        if !items.isEmpty { select(at: 0) }
    }

    @discardableResult
    func setSourceFolder(_ folder: URL) -> Bool {
        loadFromFolder(folder)
        return !items.isEmpty
    }

    @discardableResult
    func restoreLibrary() -> Bool { false }

    @discardableResult
    func addFromURLs(_ urls: [URL]) -> [PhotoAssetID] {
        let existing = items.map(\.asset)
        let existingIDs = Set(existing.map(\.id))
        let additions = urls.map { PhotoAsset(url: $0) }.filter { !existingIDs.contains($0.id) }
        loadPortableAssets(existing + additions)
        return additions.map(\.id)
    }

    @discardableResult
    func addFromData(_ values: [(name: String, data: Data)]) -> [PhotoAssetID] {
        let existing = items.map(\.asset)
        let existingIDs = Set(existing.map(\.id))
        let additions = values.map { PhotoAsset(data: $0.data, filename: $0.name) }
            .filter { !existingIDs.contains($0.id) }
        loadPortableAssets(existing + additions)
        return additions.map(\.id)
    }

    @discardableResult
    func addFromMediaVolume(_ volume: MediaVolume, files: [MediaVolumeFile]) -> [PhotoAssetID] {
        guard !volume.requiresAccessGrant else { return [] }
        return addFromURLs(files.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    func beginDataImport(reservedCount: Int = 0) {
        _ = reservedCount
    }

    @discardableResult
    func appendDataImport(_ item: PhotoImportItem, ordinal: Int) -> PhotoAssetID {
        _ = ordinal
        return addFromData([(name: item.name, data: item.data)]).first
            ?? PhotoAssetID.data(item.data)
    }

    func finishDataImport() {}
}
