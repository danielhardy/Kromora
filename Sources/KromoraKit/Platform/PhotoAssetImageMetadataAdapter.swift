import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO-facing conveniences for the durable `PhotoAsset` record.
///
/// `PhotoAsset` itself only carries Codable/Sendable values. Reading an image container to infer a
/// display type or metadata is an application-boundary operation and belongs here, where the
/// ImageIO dependency is explicit.
extension PhotoAsset {
    /// A user-facing, stable file type. File extensions are preferred because they preserve the
    /// source convention; data-backed assets fall back to the type ImageIO decoded from bytes.
    var displayFileType: String {
        if let extensionType = [fileType, url?.pathExtension]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return extensionType.uppercased()
        }

        if let data = source.data,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let identifier = CGImageSourceGetType(source),
           let type = UTType(identifier as String),
           let preferredExtension = type.preferredFilenameExtension {
            return preferredExtension.uppercased()
        }
        return "Unknown"
    }

    /// Build a durable record from the platform metadata reader without storing ImageIO objects in
    /// the record itself.
    static func discoveredFile(at url: URL, bookmarkData: Data? = nil) -> PhotoAsset {
        let imageMetadata = ImageMetadata.read(from: url)
        return PhotoAsset(
            url: url,
            metadata: PhotoAssetMetadata(imageMetadata: imageMetadata),
            bookmarkData: bookmarkData ?? PhotoAssetSource.bookmarkData(for: url)
        )
    }
}
