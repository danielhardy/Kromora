import Foundation

/// Value-only handoff from an import/open action to the source-session loader.
///
/// The plan resolves stable identity, backing storage, decoder kind, and persistence reference in
/// one place. It has no UI or asynchronous behavior, so URL-backed opens and Photos/data-backed
/// imports can test the same source contract without constructing `AppViewModel`.
struct SourceImportPlan: Sendable, Equatable {
    let name: String
    let url: URL?
    let data: Data?
    let assetID: PhotoAssetID
    let portableIdentity: PortablePhotoIdentity?
    let fileChangeSignature: PhotoSourceFingerprint?
    let dataFingerprint: String?
    let traceQuality: String
    let source: ImageSource

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
        if let url {
            self.source = ImageSource(
                url: url, nativeExtent: .zero, portableIdentity: portableIdentity,
                existingFileChangeSignature: fileChangeSignature
            )
        } else if let data {
            self.source = ImageSource(
                data: data, nativeExtent: .zero, dataFingerprint: dataFingerprint,
                portableIdentity: portableIdentity
            )
        } else {
            self.source = ImageSource(
                backing: .data(Data()), kind: .standard, nativeExtent: .zero,
                portableIdentity: portableIdentity
            )
        }
    }

    var sourceReference: EditSourceReference {
        EditSourceReference(
            assetID: assetID, portableIdentity: portableIdentity, url: url
        )
    }

}
