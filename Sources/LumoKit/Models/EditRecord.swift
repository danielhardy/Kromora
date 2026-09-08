import Foundation
import SwiftData

/// One durable, independently writable edit document.
///
/// SwiftData stores the Codable value as a Data attribute while the source locator fields stay
/// queryable for relinking. Documents are decoded only through `decodeDocument()`, so corruption
/// cannot be silently turned into a blank edit by a value façade.
@Model
final class EditRecord {
    // SwiftData's #Index macro is only available from macOS 15, while Lumo supports macOS 14.
    // Keep this locator queryable and let the source-path predicate avoid materializing the
    // catalog; add the schema index when the deployment target can support it.
    @Attribute(.unique) var assetID: String
    var documentData: Data
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
        assetID: String,
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
        assetID: String,
        documentData: Data,
        sourcePath: String? = nil,
        sourceFileName: String? = nil,
        sourceBookmark: Data? = nil
    ) {
        self.assetID = assetID
        self.documentData = documentData
        self.sourcePath = sourcePath
        self.sourceFileName = sourceFileName
        self.sourceBookmark = sourceBookmark
    }
}
