import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// The value-only result of opening a source. It contains enough information to start rendering,
/// but intentionally contains no decoded pixels or Core Image objects.
struct ImageSourcePreparation: Sendable, Equatable {
    let source: ImageSource

    var nativeExtent: CGSize { source.nativeExtent }
    var isRAW: Bool { source.kind == .raw }
}

/// How to *reproduce* the source image, rather than the image itself.
///
/// A RAW has to be re-developed from scratch on every render — `CIRAWFilter` is configured before it
/// produces an image, so there is no developed `CIImage` to hold on to and adjust. The pipeline
/// therefore needs the bytes, not a picture.
///
/// It is also the reason this type carries a URL or `Data` and never a live `CIImage`: `CIImage` is
/// not `Sendable`, and the whole point of the value-state spine is that nothing non-`Sendable` enters
/// app state. See `docs/ENGINEERING_GUIDE.md`.
struct ImageSource: Sendable, Equatable {

    /// Where the bytes are.
    ///
    /// `.data` is not an afterthought: a Photos import arrives as bytes with **no URL at all**
    /// (`ImageCollection.Item.url` is `nil` for one). Writing those to a temp file to get a URL would
    /// mean inventing a filename, and extension-based RAW detection would then classify the file by
    /// whatever extension was guessed — plus someone has to delete it afterwards. Carrying the bytes
    /// avoids both.
    ///
    /// Note `Equatable` on `.data` compares the whole buffer. Sources are compared rarely (has the
    /// user opened a different image?), never per render, so that is the right trade — but it is a
    /// reason not to put an `ImageSource` inside a value that *is* compared per frame.
    enum Backing: Sendable, Equatable {
        case url(URL)
        case data(Data)
    }

    /// Which decode path the source needs. RAW goes through `CIRAWFilter` and honours
    /// `RAWDevelopSettings`; standard images do not.
    enum Kind: Sendable, Equatable {
        case raw
        case standard
    }

    let backing: Backing
    let kind: Kind
    /// The source's full pixel dimensions, upright. Lets `RenderScale` compute a downscale factor
    /// without decoding the image again.
    let nativeExtent: CGSize
    /// Portable identity captured at the source boundary. Cache consumers must use this value,
    /// never the URL or filesystem metadata used to obtain the bytes. URL-backed sources retain
    /// only a bounded file-change signature beside it so replacement checks can avoid a second
    /// full read for an unchanged file.
    let portableIdentity: PortablePhotoIdentity
    private let fileChangeSignature: PhotoSourceFingerprint?
    private let dataFingerprint: String?
    /// Captured when this source session is created. This is for observability grouping only;
    /// cache identity must continue to use the dynamic `cacheFingerprint` below.
    let traceToken: String

    init(
        backing: Backing,
        kind: Kind,
        nativeExtent: CGSize,
        dataFingerprint: String? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        self.backing = backing
        self.kind = kind
        self.nativeExtent = nativeExtent
        if case .data(let data) = backing {
            self.dataFingerprint = dataFingerprint ?? PhotoAssetID.contentDigest(data)
        } else {
            self.dataFingerprint = nil
        }
        if case .url(let url) = backing {
            self.fileChangeSignature = PhotoSourceFingerprint.file(at: url)
        } else {
            self.fileChangeSignature = nil
        }
        self.portableIdentity = Self.makePortableIdentity(
            backing: backing, kind: kind, nativeExtent: nativeExtent,
            dataFingerprint: self.dataFingerprint, existing: portableIdentity
        )
        self.traceToken = Self.makeTraceToken(from: Self.fingerprintForTrace(backing: backing,
                                                                              kind: kind,
                                                                              nativeExtent: nativeExtent,
                                                                              dataFingerprint: self.dataFingerprint))
    }

    /// A file-backed source, classified by extension — the same rule `ImageDecoder.load` uses,
    /// so a file cannot be RAW for one and standard for the other.
    init(
        url: URL, nativeExtent: CGSize, portableIdentity: PortablePhotoIdentity? = nil
    ) {
        self.init(
            backing: .url(url), kind: Self.kind(forExtension: url.pathExtension),
            nativeExtent: nativeExtent, portableIdentity: portableIdentity
        )
    }

    /// A bytes-backed source, classified by **content**.
    ///
    /// There is no filename to inspect here, so the UTI ImageIO reports for the buffer decides. This
    /// is what makes a RAW dropped in as a payload — or a Photos item delivered as one — take the
    /// RAW path rather than being misread as a standard image.
    init(
        data: Data, nativeExtent: CGSize, dataFingerprint: String? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        self.init(
            backing: .data(data), kind: Self.kind(forData: data), nativeExtent: nativeExtent,
            dataFingerprint: dataFingerprint, portableIdentity: portableIdentity
        )
    }

    init(preparation: ImageSourcePreparation) {
        self = preparation.source
    }

    // MARK: - Classification

    static func kind(forExtension ext: String) -> Kind {
        ImageDecoder.rawExtensions.contains(ext.lowercased()) ? .raw : .standard
    }

    /// Classify a buffer by the type ImageIO reports for it. Anything undecodable or unrecognised is
    /// treated as standard: the standard path fails with a plain "cannot load" message, whereas
    /// pushing a non-RAW through `CIRAWFilter` fails less legibly.
    static func kind(forData data: Data) -> Kind {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source),
              let type = UTType(uti as String)
        else { return .standard }
        if type.conforms(to: .rawImage) {
            return .raw
        }
        // Some camera RAW payloads are TIFF containers without a filename, so ImageIO reports
        // public.tiff after the bytes lose their extension. CIRAWFilter's initializer identifies
        // those sources without asking for outputImage or developing pixels.
        guard type.conforms(to: .tiff) else { return .standard }
        return CIRAWFilter(imageData: data, identifierHint: nil) != nil ? .raw : .standard
    }

    /// A cache identity containing only the portable UUID, content hash, decoder revision, and
    /// geometry. Repeated reads on the render/mask hot path use the captured hash when the bounded
    /// file-change signature is unchanged. A signature change triggers a fresh content hash, so
    /// an in-place replacement still gets a new identity; the URL itself never enters the identity.
    var cacheFingerprint: String {
        if case .data = backing, let dataFingerprint {
            let extent = "\(Double(nativeExtent.width).bitPattern):\(Double(nativeExtent.height).bitPattern)"
            return "data:\(dataFingerprint):\(kind):\(extent)"
        }
        return cacheIdentity.cacheKey
    }

    /// Identity used by the renderer-owned RAW session. Geometry is intentionally excluded so the
    /// session created while preparing a zero-extent source is reused after preparation fills in
    /// the decoder's authoritative dimensions.
    var decoderFingerprint: String {
        cacheIdentity.cacheKey
    }

    var cacheIdentity: PortablePhotoIdentity {
        guard case .url(let url) = backing,
              let fileChangeSignature,
              PhotoSourceFingerprint.file(at: url) != fileChangeSignature,
              let fingerprint = try? PortablePhotoSourceFingerprint.file(
                  at: url,
                  sourceRevision: portableIdentity.sourceFingerprint.sourceRevision,
                  decoderVersion: portableIdentity.sourceFingerprint.decoderVersion,
                  geometry: portableIdentity.sourceFingerprint.geometry
              ) else {
            return portableIdentity
        }
        return PortablePhotoIdentity(assetID: portableIdentity.assetID, sourceFingerprint: fingerprint)
    }

    private static func makePortableIdentity(
        backing: Backing, kind: Kind, nativeExtent: CGSize, dataFingerprint: String?,
        existing: PortablePhotoIdentity?
    ) -> PortablePhotoIdentity {
        let geometry = nativeExtent.width > 0 && nativeExtent.height > 0
            ? PhotoPixelDimensions(width: Int(nativeExtent.width), height: Int(nativeExtent.height))
            : nil
        let fingerprint: PortablePhotoSourceFingerprint
        switch backing {
        case .data(let data):
            fingerprint = PortablePhotoSourceFingerprint(
                contentHash: PortablePhotoSourceFingerprint.contentHash(of: data),
                sourceRevision: existing?.sourceFingerprint.sourceRevision ?? 0,
                decoderVersion: existing?.sourceFingerprint.decoderVersion ?? "imageio-\(kind)-v1",
                geometry: geometry
            )
        case .url(let url):
            let decoderVersion = existing?.sourceFingerprint.decoderVersion
                ?? "imageio-\(kind)-v1"
            fingerprint = (try? PortablePhotoSourceFingerprint.file(
                at: url,
                sourceRevision: existing?.sourceFingerprint.sourceRevision ?? 0,
                decoderVersion: decoderVersion, geometry: geometry
            )) ?? existing?.sourceFingerprint.with(geometry: geometry)
                ?? PortablePhotoSourceFingerprint(
                    contentHash: PortablePhotoSourceFingerprint.contentHash(
                        of: Data(("unavailable:" + PhotoAssetID.file(url).raw).utf8)
                    ),
                    decoderVersion: "unavailable-\(kind)-v1", geometry: geometry
                )
        }
        let fallbackAssetID: PortablePhotoAssetID
        if let existing {
            fallbackAssetID = existing.assetID
        } else {
            switch backing {
            case .url(let url):
                let fallbackFingerprint = (try? PortablePhotoSourceFingerprint.file(
                    at: url, decoderVersion: "imageio-\(kind)-v1", geometry: geometry
                )) ?? PortablePhotoSourceFingerprint(
                    contentHash: PortablePhotoSourceFingerprint.contentHash(
                        of: Data("unavailable".utf8)
                    ), decoderVersion: "unavailable-\(kind)-v1", geometry: geometry
                )
                fallbackAssetID = PortablePhotoAssetID.compatibility(from: fallbackFingerprint)
            case .data(let data):
                fallbackAssetID = PortablePhotoAssetID.compatibility(from: PhotoAssetID.data(data))
            }
        }
        return PortablePhotoIdentity(assetID: fallbackAssetID, sourceFingerprint: fingerprint)
    }

    private static func fingerprintForTrace(backing: Backing, kind: Kind, nativeExtent: CGSize,
                                            dataFingerprint: String?) -> String {
        let extent = "\(Double(nativeExtent.width).bitPattern):\(Double(nativeExtent.height).bitPattern)"
        switch backing {
        case .data:
            return "data:\(dataFingerprint ?? "missing"):\(kind):\(extent)"
        case .url(let url):
            // This is intentionally performed once, at source-session creation. Subsequent event
            // logging uses the stored token, while cache/source replacement checks remain dynamic.
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey
            ])
            let size = values?.fileSize.map(String.init) ?? "missing"
            let modified = values?.contentModificationDate?.timeIntervalSince1970.description ?? "missing"
            let resourceID = values?.fileResourceIdentifier.map { String(describing: $0) } ?? "missing"
            return "url:\(url.standardizedFileURL.path):\(size):\(modified):\(resourceID):\(kind):\(extent)"
        }
    }

    private static func makeTraceToken(from fingerprint: String) -> String {
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return String(digest.prefix(16))
    }
}
