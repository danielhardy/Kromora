import Foundation
import SwiftData

/// One durable, independently writable edit document.
///
/// SwiftData stores the Codable value as a Data attribute while the source locator fields stay
/// queryable for relinking. The unique persistence key is an opaque UUID; locators are operational
/// hints only and are never used as the record identity. Documents are decoded only through
/// `decodeDocument()`, so corruption cannot be silently turned into a blank edit by a value façade.
@Model
final class EditRecord {
    /// The only durable key for an edit. It intentionally has no URL, inode, mtime, or content
    /// digest component. A source can move or be replaced without changing which edit record it
    /// addresses; source integrity belongs to `PortablePhotoSourceFingerprint`.
    @Attribute(.unique) var assetID: UUID
    var documentData: Data

    // These fields remain as non-identity relinking hints for the referenced-folder editor. They
    // are not consulted for direct persistence lookup and are not part of the portable key.
    var sourcePath: String?
    var sourceFileName: String?
    var sourceBookmark: Data?

    /// Decodes the stored document without hiding corruption from the persistence layer.
    func decodeDocument() throws -> EditDocument {
        try JSONDecoder().decode(EditDocument.self, from: documentData)
    }

    /// Creates a record after encoding the document. Callers that already encoded the document
    /// should use the `documentData` initializer to avoid encoding it a second time.
    convenience init(
        assetID: PortablePhotoAssetID,
        document: EditDocument,
        sourcePath: String? = nil,
        sourceFileName: String? = nil,
        sourceBookmark: Data? = nil
    ) throws {
        self.init(
            assetID: assetID,
            documentData: try JSONEncoder().encode(document),
            sourcePath: sourcePath,
            sourceFileName: sourceFileName,
            sourceBookmark: sourceBookmark
        )
    }

    init(
        assetID: PortablePhotoAssetID,
        documentData: Data,
        sourcePath: String? = nil,
        sourceFileName: String? = nil,
        sourceBookmark: Data? = nil
    ) {
        self.assetID = assetID.uuid
        self.documentData = documentData
        self.sourcePath = sourcePath
        self.sourceFileName = sourceFileName
        self.sourceBookmark = sourceBookmark
    }

    /// Compatibility initializer for test fixtures and pre-identity callers. New persistence
    /// callers should pass `PortablePhotoAssetID`; even this bridge stores only its UUID.
    convenience init(
        assetID: String,
        document: EditDocument,
        sourcePath: String? = nil,
        sourceFileName: String? = nil,
        sourceBookmark: Data? = nil
    ) throws {
        try self.init(
            assetID: Self.portableAssetID(from: assetID), document: document,
            sourcePath: sourcePath, sourceFileName: sourceFileName, sourceBookmark: sourceBookmark
        )
    }

    /// Value-only view used by diagnostics and migration tests.
    var portableAssetID: PortablePhotoAssetID { PortablePhotoAssetID(uuid: assetID) }

    private static func portableAssetID(from raw: String) -> PortablePhotoAssetID {
        if let uuid = UUID(uuidString: raw) {
            return PortablePhotoAssetID(uuid: uuid)
        }
        return PortablePhotoAssetID.compatibility(from: PhotoAssetID(rawValue: raw))
    }
}
