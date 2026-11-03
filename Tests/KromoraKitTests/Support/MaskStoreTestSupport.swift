import Foundation

@testable import KromoraKit

enum MaskStoreTestSupport {
    static func filename(for key: MaskCacheKey) -> String {
        MaskStore.entryName(for: key).filename(extension: "json")
    }

    /// Where `MaskStore(directory:)` keeps the metadata file for `key`.
    static func metadataURL(in directory: URL, for key: MaskCacheKey) -> URL {
        entryURL(in: directory, for: key, extension: "json")
    }

    static func sidecarURL(in directory: URL, for key: MaskCacheKey) -> URL {
        entryURL(in: directory, for: key, extension: "bin")
    }

    static func assetDirectory(in directory: URL, for key: MaskCacheKey) -> URL {
        DiskCacheIO.assetDirectory(in: directory, for: key.identity.assetID)
    }

    private static func entryURL(in directory: URL, for key: MaskCacheKey, extension ext: String) -> URL {
        assetDirectory(in: directory, for: key)
            .appendingPathComponent(MaskStore.entryName(for: key).filename(extension: ext))
    }
}
