import Foundation
import SwiftData

/// One durable, independently writable edit document.
///
/// The document remains a value so renderers and callers do not need to know anything about
/// SwiftData. SwiftData stores the Codable value as a Data attribute while the source locator
/// fields stay queryable for relinking. The computed value façade keeps the persistence model
/// independent from the document's Codable representation and avoids SwiftData's composite-coder
/// limitations for nested edit enums.
@Model
final class EditRecord {
    @Attribute(.unique) var assetID: String
    var documentData: Data
    var sourcePath: String?
    var sourceFileName: String?
    var sourceBookmark: Data?

    var document: EditDocument {
        get { (try? decodeDocument()) ?? EditDocument() }
        set { documentData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Decodes the stored document without hiding corruption from the persistence layer.
    ///
    /// The computed `document` property intentionally keeps its identity fallback for callers
    /// that need a value façade. `EditDocumentStore` uses this throwing path so a damaged row can
    /// be reported through its load status instead of looking like a valid blank edit.
    func decodeDocument() throws -> EditDocument {
        try JSONDecoder().decode(EditDocument.self, from: documentData)
    }

    init(
        assetID: String,
        document: EditDocument,
        sourcePath: String? = nil,
        sourceFileName: String? = nil,
        sourceBookmark: Data? = nil
    ) {
        self.assetID = assetID
        self.documentData = (try? JSONEncoder().encode(document)) ?? Data()
        self.sourcePath = sourcePath
        self.sourceFileName = sourceFileName
        self.sourceBookmark = sourceBookmark
    }
}
