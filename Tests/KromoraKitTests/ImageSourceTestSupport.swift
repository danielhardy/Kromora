import Foundation

@testable import KromoraKit

/// Test-only synchronous construction. Production code resolves a file's identity with
/// `ImageSource.resolve` off the main actor; tests that just need a source use the blocking body.
extension ImageSource {
    init(
        url: URL, nativeExtent: CGSize, portableIdentity: PortablePhotoIdentity? = nil,
        existingFileChangeSignature: PhotoSourceFingerprint? = nil
    ) {
        self = ImageSource.resolveBlocking(
            url: url, nativeExtent: nativeExtent, portableIdentity: portableIdentity,
            existingFileChangeSignature: existingFileChangeSignature
        )
    }
}

extension ImageSource {
    /// A source with an explicit `kind`, bypassing classification (for example a RAW-labelled blob).
    init(backing: Backing, kind: Kind, nativeExtent: CGSize) {
        switch backing {
        case .url(let url):
            let resolved = ImageSource.resolveBlocking(url: url, nativeExtent: nativeExtent)
            self.init(
                backing: backing, kind: kind, nativeExtent: nativeExtent,
                portableIdentity: resolved.portableIdentity,
                fileChangeSignature: PhotoSourceFingerprint.file(at: url)
            )
        case .data(let data):
            let resolved = ImageSource(data: data, nativeExtent: nativeExtent)
            self.init(
                backing: backing, kind: kind, nativeExtent: nativeExtent,
                portableIdentity: resolved.portableIdentity,
                dataFingerprint: resolved.sourceDataFingerprint
            )
        }
    }
}

extension SourceImportPlan {
    init(
        name: String, url: URL?, data: Data?, assetID: PhotoAssetID? = nil,
        portableIdentity: PortablePhotoIdentity? = nil,
        fileChangeSignature: PhotoSourceFingerprint? = nil,
        dataFingerprint: String? = nil, traceQuality: String = "open"
    ) {
        let draft = SourceImportDraft(
            name: name, url: url, data: data, assetID: assetID,
            portableIdentity: portableIdentity, fileChangeSignature: fileChangeSignature,
            dataFingerprint: dataFingerprint, traceQuality: traceQuality
        )
        self.init(draft: draft, source: ImageSource.resolveBlocking(draft.sourceRequest))
    }
}
