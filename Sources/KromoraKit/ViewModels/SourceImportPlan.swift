import Foundation

/// The synchronous half of an import/open action: stable identity inputs, backing storage, and
/// persistence reference. Building it touches no file, so the selection path can publish
/// `assetID` and `name` immediately and resolve the `ImageSource` afterwards, off the main actor.
struct SourceImportDraft: Sendable, Equatable {
    let name: String
    let url: URL?
    let data: Data?
    let assetID: PhotoAssetID
    let portableIdentity: PortablePhotoIdentity?
    let fileChangeSignature: PhotoSourceFingerprint?
    let dataFingerprint: String?
    let traceQuality: String

    init(
        name: String,
        url: URL?,
        data: Data?,
        assetID: PhotoAssetID? = nil,
        portableIdentity: PortablePhotoIdentity? = nil,
        fileChangeSignature: PhotoSourceFingerprint? = nil,
        dataFingerprint: String? = nil,
        traceQuality: String = "open"
    ) {
        self.name = name
        self.url = url
        self.data = data
        self.assetID =
            assetID ?? url.map(PhotoAssetID.file)
            ?? data.map(PhotoAssetID.data)
            ?? .data(Data())
        self.portableIdentity = portableIdentity
        self.fileChangeSignature = fileChangeSignature
        self.dataFingerprint = dataFingerprint
        self.traceQuality = traceQuality
    }

    var sourceReference: EditSourceReference {
        EditSourceReference(
            assetID: assetID, portableIdentity: portableIdentity, url: url
        )
    }

    var sourceRequest: ImageSource.Request {
        if let url {
            return ImageSource.Request(
                url: url, nativeExtent: .zero, portableIdentity: portableIdentity,
                existingFileChangeSignature: fileChangeSignature
            )
        }
        return ImageSource.Request(
            data: data ?? Data(), nativeExtent: .zero, dataFingerprint: dataFingerprint,
            portableIdentity: portableIdentity
        )
    }

    /// Resolve the source's identity off the main actor and complete the plan.
    func resolved() async -> SourceImportPlan {
        SourceImportPlan(draft: self, source: await ImageSource.resolve(sourceRequest))
    }
}

/// Value-only handoff from an import/open action to the source-session loader.
///
/// The plan is a `SourceImportDraft` plus the `ImageSource` resolved from it, so URL-backed opens
/// and Photos/data-backed imports can test the same source contract without constructing
/// `AppViewModel`.
struct SourceImportPlan: Sendable, Equatable {
    let draft: SourceImportDraft
    let source: ImageSource

    var name: String { draft.name }
    var url: URL? { draft.url }
    var data: Data? { draft.data }
    var assetID: PhotoAssetID { draft.assetID }
    var portableIdentity: PortablePhotoIdentity? { draft.portableIdentity }
    var fileChangeSignature: PhotoSourceFingerprint? { draft.fileChangeSignature }
    var dataFingerprint: String? { draft.dataFingerprint }
    var traceQuality: String { draft.traceQuality }
    var sourceReference: EditSourceReference { draft.sourceReference }
}
