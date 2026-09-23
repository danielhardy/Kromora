import Foundation
import ImageIO
@testable import KromoraKit

@MainActor
private var compatibilityLibraryFolders: [ObjectIdentifier: URL] = [:]

/// Transitional fixture adapters for tests that still describe their input as a folder.
/// Production has no corresponding API: these helpers immediately turn fixture files into the
/// package presentation model so the old test cases can be migrated incrementally.
@MainActor
extension ImageCollection {
    var libraryFolderURL: URL {
        compatibilityLibraryFolders[ObjectIdentifier(self)]
            ?? packageRoot(from: items.first?.url)
            ?? items.first?.url?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("KromoraPackageFixture")
    }

    private func packageRoot(from url: URL?) -> URL? {
        var candidate = url
        while let current = candidate {
            if current.pathExtension == "kromoralibrary" { return current }
            let parent = current.deletingLastPathComponent()
            guard parent != current else { return nil }
            candidate = parent
        }
        return nil
    }

    static var defaultLibraryFolderURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KromoraPackageFixture")
    }

    var sourceFolderURL: URL? { nil }
    var hasActiveSourceFolderScopeForTesting: Bool { false }
    var pendingImportSlots: [Int] { [] }

    func configureCompatibilityLibraryFolder(_ url: URL) {
        compatibilityLibraryFolders[ObjectIdentifier(self)] = url.standardizedFileURL
    }

    func metadataCompletion() async { await scanCompletion() }

    func loadFromFolder(_ folder: URL) {
        let candidates = (FileManager.default.enumerator(
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
        var unreadableNames: [String] = []
        let urls = candidates.filter { url in
            let isReadableImage: Bool
            if ImageDecoder.rawExtensions.contains(url.pathExtension.lowercased()) {
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    isReadableImage = CGImageSourceGetCount(source) > 0
                } else {
                    isReadableImage = false
                }
            } else {
                isReadableImage = (try? ImageDecoder.prepareStandard(from: url)) != nil
            }
            guard !isReadableImage else { return true }
            unreadableNames.append(url.lastPathComponent)
            return false
        }
        loadPortableAssets(urls.map { PhotoAsset(url: $0) })
        for name in unreadableNames {
            recordScanWarning("Could not read metadata for \(name).")
        }
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

        let destinationFolder = libraryFolderURL
        do {
            try FileManager.default.createDirectory(
                at: destinationFolder, withIntermediateDirectories: true
            )
        } catch {
            return []
        }

        let existingIDs = Set(items.map(\.id))
        var imported: [PhotoAsset] = []
        for file in files {
            guard FileManager.default.fileExists(atPath: file.url.path) else { continue }

            let filename = URL(fileURLWithPath: file.filename).lastPathComponent
            guard !filename.isEmpty else { continue }
            let destination = destinationFolder.appendingPathComponent(filename)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: file.url, to: destination)
            } catch {
                continue
            }

            let imageMetadata = file.metadata.isEmpty
                ? ImageMetadata.read(from: destination)
                : file.metadata
            let asset = PhotoAsset(
                url: destination,
                metadata: PhotoAssetMetadata(imageMetadata: imageMetadata)
            )
            guard !existingIDs.contains(asset.id), !imported.contains(where: { $0.id == asset.id })
            else { continue }
            imported.append(asset)
        }

        guard !imported.isEmpty else { return [] }
        loadPortableAssets(items.map(\.asset) + imported)
        return imported.map(\.id)
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
