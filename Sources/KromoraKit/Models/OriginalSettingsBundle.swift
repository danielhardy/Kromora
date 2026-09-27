import CryptoKit
import Foundation

/// Portable, read-only handoff of an original and its non-destructive Kromora settings.
enum OriginalSettingsBundle {
    static let fileExtension = "kromora-original"
    static let settingsFilename = "settings.json"
    static let manifestFilename = "manifest.json"

    struct Manifest: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let originalFilename: String
        let originalSHA256: String
        let settingsSHA256: String
        let originalsAreReadOnly: Bool
        let locationMetadataIncluded: Bool
    }

    enum BundleError: Error, LocalizedError {
        case invalidSource
        case checksumMismatch(String)

        var errorDescription: String? {
            switch self {
            case .invalidSource: "The original image is no longer available."
            case .checksumMismatch(let filename): "The " + filename + " checksum does not match the bundle manifest."
            }
        }
    }

    static func create(
        source: ImageSource,
        sourceName: String,
        document: EditDocument,
        destination: URL,
        locationMetadataIncluded: Bool
    ) throws {
        let original: Data
        switch source.backing {
        case .url(let url): original = try Data(contentsOf: url, options: .mappedIfSafe)
        case .data(let data): original = data
        }
        let settings = try JSONEncoder.prettySorted.encode(document)
        let originalFilename = safeFilename(sourceName, fallbackExtension: extensionFor(source))
        let manifest = Manifest(
            schemaVersion: 1,
            originalFilename: originalFilename,
            originalSHA256: checksum(original),
            settingsSHA256: checksum(settings),
            originalsAreReadOnly: true,
            locationMetadataIncluded: locationMetadataIncluded
        )
        let manifestData = try JSONEncoder.prettySorted.encode(manifest)

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        try original.write(to: temporary.appendingPathComponent(originalFilename), options: .atomic)
        try settings.write(to: temporary.appendingPathComponent(settingsFilename), options: .atomic)
        try manifestData.write(to: temporary.appendingPathComponent(manifestFilename), options: .atomic)
        _ = try verify(at: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    /// Validate both payloads before a bundle is imported or archived elsewhere.
    static func verify(at directory: URL) throws -> Manifest {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(
            Manifest.self, from: Data(contentsOf: directory.appendingPathComponent(manifestFilename))
        )
        guard manifest.schemaVersion == 1, manifest.originalsAreReadOnly else {
            throw BundleError.checksumMismatch(manifestFilename)
        }
        guard !manifest.originalFilename.isEmpty,
              manifest.originalFilename != ".", manifest.originalFilename != "..",
              URL(fileURLWithPath: manifest.originalFilename).lastPathComponent == manifest.originalFilename,
              !manifest.originalFilename.contains("/") else {
            throw BundleError.checksumMismatch(manifestFilename)
        }
        let originalURL = directory.appendingPathComponent(manifest.originalFilename)
        let original = try Data(contentsOf: originalURL, options: .mappedIfSafe)
        let settings = try Data(contentsOf: directory.appendingPathComponent(settingsFilename))
        guard checksum(original) == manifest.originalSHA256 else {
            throw BundleError.checksumMismatch(manifest.originalFilename)
        }
        guard checksum(settings) == manifest.settingsSHA256 else {
            throw BundleError.checksumMismatch(settingsFilename)
        }
        return manifest
    }

    private static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func safeFilename(_ name: String, fallbackExtension: String) -> String {
        let trimmed = URL(fileURLWithPath: name).lastPathComponent
        let candidate = trimmed.isEmpty ? "Original.\(fallbackExtension)" : trimmed
        return candidate.replacingOccurrences(of: "/", with: "_")
    }

    private static func extensionFor(_ source: ImageSource) -> String {
        if case .url(let url) = source.backing, !url.pathExtension.isEmpty { return url.pathExtension }
        return "image"
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
