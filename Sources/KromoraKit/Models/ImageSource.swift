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

    var sourceDataFingerprint: String? { dataFingerprint }
    /// Captured when this source session is created. This is for observability grouping only;
    /// cache identity must continue to use the dynamic `cacheFingerprint` below.
    let traceToken: String

    /// Pure memberwise initializer: no stat, no read, no hash. The identity and the file-change
    /// signature are already resolved by the caller — `resolve` for a file, the `data:` initializer
    /// for bytes — so constructing a source is safe on any thread, including the main actor.
    init(
        backing: Backing,
        kind: Kind,
        nativeExtent: CGSize,
        portableIdentity: PortablePhotoIdentity,
        fileChangeSignature: PhotoSourceFingerprint? = nil,
        dataFingerprint: String? = nil
    ) {
        self.backing = backing
        self.kind = kind
        self.nativeExtent = nativeExtent
        self.portableIdentity = portableIdentity
        self.fileChangeSignature = fileChangeSignature
        self.dataFingerprint = dataFingerprint
        self.traceToken = Self.makeTraceToken(from: Self.fingerprintForTrace(
            backing: backing, kind: kind, nativeExtent: nativeExtent,
            dataFingerprint: dataFingerprint, fileChangeSignature: fileChangeSignature
        ))
    }

    /// A file-backed source whose identity the caller already resolved off the main actor.
    init(
        url: URL, nativeExtent: CGSize, portableIdentity: PortablePhotoIdentity,
        fileChangeSignature: PhotoSourceFingerprint?
    ) {
        self.init(
            backing: .url(url), kind: Self.kind(forExtension: url.pathExtension),
            nativeExtent: nativeExtent, portableIdentity: portableIdentity,
            fileChangeSignature: fileChangeSignature
        )
    }

    /// A bytes-backed source, classified by **content**.
    ///
    /// There is no filename to inspect here, so the UTI ImageIO reports for the buffer decides. This
    /// is what makes a RAW dropped in as a payload — or a Photos item delivered as one — take the
    /// RAW path rather than being misread as a standard image.
    ///
    /// The bytes are already in memory, so this does no file I/O. It does digest them unless the
    /// import boundary supplies `dataFingerprint`; Photos imports always do.
    init(
        data: Data, nativeExtent: CGSize, dataFingerprint: String? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        let kind = Self.kind(forData: data)
        let fingerprint = dataFingerprint ?? PhotoAssetID.contentDigest(data)
        self.init(
            backing: .data(data), kind: kind, nativeExtent: nativeExtent,
            portableIdentity: Self.dataIdentity(
                data: data, kind: kind, nativeExtent: nativeExtent, existing: portableIdentity
            ),
            dataFingerprint: fingerprint
        )
    }

    init(preparation: ImageSourcePreparation) {
        self = preparation.source
    }

    // MARK: - Identity resolution

    /// Everything needed to resolve a source, as a value that can cross to a background context.
    struct Request: Sendable, Equatable {
        let backing: Backing
        let nativeExtent: CGSize
        let portableIdentity: PortablePhotoIdentity?
        let existingFileChangeSignature: PhotoSourceFingerprint?
        let dataFingerprint: String?

        init(
            url: URL, nativeExtent: CGSize, portableIdentity: PortablePhotoIdentity? = nil,
            existingFileChangeSignature: PhotoSourceFingerprint? = nil
        ) {
            self.backing = .url(url)
            self.nativeExtent = nativeExtent
            self.portableIdentity = portableIdentity
            self.existingFileChangeSignature = existingFileChangeSignature
            self.dataFingerprint = nil
        }

        init(
            data: Data, nativeExtent: CGSize, dataFingerprint: String? = nil,
            portableIdentity: PortablePhotoIdentity? = nil
        ) {
            self.backing = .data(data)
            self.nativeExtent = nativeExtent
            self.portableIdentity = portableIdentity
            self.existingFileChangeSignature = nil
            self.dataFingerprint = dataFingerprint
        }
    }

    /// Resolve a source's identity off the main actor: stat the file, take its bounded signature,
    /// and — only when neither a browsing placeholder nor an unchanged snapshot lets the existing
    /// identity be reused — stream the whole file through SHA-256.
    ///
    /// Never fails: an unreadable file resolves to an "unavailable" identity so the caller's
    /// decode reports the real error.
    @concurrent
    static func resolve(
        url: URL, nativeExtent: CGSize, portableIdentity: PortablePhotoIdentity? = nil,
        existingFileChangeSignature: PhotoSourceFingerprint? = nil
    ) async -> ImageSource {
        resolveBlocking(
            url: url, nativeExtent: nativeExtent, portableIdentity: portableIdentity,
            existingFileChangeSignature: existingFileChangeSignature
        )
    }

    @concurrent
    static func resolve(_ request: Request) async -> ImageSource {
        resolveBlocking(request)
    }

    static func resolveBlocking(_ request: Request) -> ImageSource {
        switch request.backing {
        case .url(let url):
            return resolveBlocking(
                url: url, nativeExtent: request.nativeExtent,
                portableIdentity: request.portableIdentity,
                existingFileChangeSignature: request.existingFileChangeSignature
            )
        case .data(let data):
            return ImageSource(
                data: data, nativeExtent: request.nativeExtent,
                dataFingerprint: request.dataFingerprint,
                portableIdentity: request.portableIdentity
            )
        }
    }

    /// The synchronous body of `resolve`. It performs blocking file I/O, so it is for background
    /// contexts and for tests that need a source without an `await`; UI code uses `resolve`.
    static func resolveBlocking(
        url: URL, nativeExtent: CGSize, portableIdentity existing: PortablePhotoIdentity? = nil,
        existingFileChangeSignature: PhotoSourceFingerprint? = nil
    ) -> ImageSource {
        let kind = kind(forExtension: url.pathExtension)
        let current = PhotoSourceFingerprint.file(at: url)
        let identity = fileIdentity(
            url: url, kind: kind, nativeExtent: nativeExtent, existing: existing,
            existingFileChangeSignature: existingFileChangeSignature,
            currentFileChangeSignature: current
        )
        return ImageSource(
            backing: .url(url), kind: kind, nativeExtent: nativeExtent,
            portableIdentity: identity, fileChangeSignature: current
        )
    }

    /// The same bytes with decoder-authoritative dimensions. Pure: the identity and change
    /// signature carry over, so preparing a source never rereads or rehashes the file.
    func withNativeExtent(_ extent: CGSize) -> ImageSource {
        ImageSource(
            backing: backing, kind: kind, nativeExtent: extent,
            portableIdentity: cacheIdentity.with(
                geometry: PhotoPixelDimensions(width: Int(extent.width), height: Int(extent.height))
            ),
            fileChangeSignature: fileChangeSignature, dataFingerprint: dataFingerprint
        )
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

    private static func geometry(of nativeExtent: CGSize) -> PhotoPixelDimensions? {
        nativeExtent.width > 0 && nativeExtent.height > 0
            ? PhotoPixelDimensions(width: Int(nativeExtent.width), height: Int(nativeExtent.height))
            : nil
    }

    private static func dataIdentity(
        data: Data, kind: Kind, nativeExtent: CGSize, existing: PortablePhotoIdentity?
    ) -> PortablePhotoIdentity {
        let geometry = geometry(of: nativeExtent)
        let fingerprint = PortablePhotoSourceFingerprint(
            contentHash: PortablePhotoSourceFingerprint.contentHash(of: data),
            sourceRevision: existing?.sourceFingerprint.sourceRevision ?? 0,
            decoderVersion: existing?.sourceFingerprint.decoderVersion ?? "imageio-\(kind)-v1",
            geometry: geometry
        )
        let assetID = existing?.assetID
            ?? PortablePhotoAssetID.compatibility(from: PhotoAssetID.data(data))
        return PortablePhotoIdentity(assetID: assetID, sourceFingerprint: fingerprint)
    }

    /// Resolve a file's identity. Three branches, cheapest first; only the last reads the file.
    private static func fileIdentity(
        url: URL, kind: Kind, nativeExtent: CGSize, existing: PortablePhotoIdentity?,
        existingFileChangeSignature: PhotoSourceFingerprint?,
        currentFileChangeSignature: PhotoSourceFingerprint
    ) -> PortablePhotoIdentity {
        let geometry = geometry(of: nativeExtent)
        let decoderVersion = existing?.sourceFingerprint.decoderVersion ?? "imageio-\(kind)-v1"
        let fingerprint: PortablePhotoSourceFingerprint
        // The content hash computed by the expensive path, kept so a source with no existing
        // identity derives its compatibility asset ID from it instead of hashing a second time.
        var hashed: PortablePhotoSourceFingerprint?
        if let existing, existingFileChangeSignature?.isBrowsingObservation == true,
           !existing.sourceFingerprint.isBrowsingPlaceholder {
            // A browsing asset keeps the content hash computed when it entered the library
            // but a placeholder change signature, so there is nothing to compare and the
            // match test below can never succeed. The authoritative check against the record's
            // signature happens when the photo is opened and prepared.
            fingerprint = existing.sourceFingerprint.with(geometry: geometry)
        } else if let existing, let existingFileChangeSignature,
                  // A signature that came from the package has whole-second dates, so exact
                  // equality never matched a real file and every open hashed the whole file.
                  existingFileChangeSignature.isSameFileSnapshot(as: currentFileChangeSignature) {
            fingerprint = existing.sourceFingerprint.with(geometry: geometry)
        } else {
            // The expensive path: it streams and hashes the whole file. `resolve` runs it off the
            // main actor; the log says which thread it actually ran on.
            let hashStart = DispatchTime.now().uptimeNanoseconds
            defer {
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- hashStart) / 1_000_000
                KromoraObservability.photoSwitchPhase(
                    "wholeFileRehash", since: nil,
                    detail: String(
                        format: "hashMs=%.1f hadStoredSignature=%@ mainThread=%@", ms,
                        existingFileChangeSignature == nil ? "false" : "true",
                        Thread.isMainThread ? "true" : "false"
                    )
                )
            }
            hashed = try? PortablePhotoSourceFingerprint.file(
                at: url, sourceRevision: existing?.sourceFingerprint.sourceRevision ?? 0,
                decoderVersion: decoderVersion, geometry: geometry
            )
            fingerprint = hashed ?? existing?.sourceFingerprint.with(geometry: geometry)
                ?? PortablePhotoSourceFingerprint(
                    contentHash: PortablePhotoSourceFingerprint.contentHash(
                        of: Data(("unavailable:" + PhotoAssetID.file(url).raw).utf8)
                    ),
                    decoderVersion: "unavailable-\(kind)-v1", geometry: geometry
                )
        }
        let assetID: PortablePhotoAssetID
        if let existing {
            assetID = existing.assetID
        } else {
            let compatibilityFingerprint = hashed ?? PortablePhotoSourceFingerprint(
                contentHash: PortablePhotoSourceFingerprint.contentHash(of: Data("unavailable".utf8)),
                decoderVersion: "unavailable-\(kind)-v1", geometry: geometry
            )
            assetID = PortablePhotoAssetID.compatibility(from: compatibilityFingerprint)
        }
        return PortablePhotoIdentity(assetID: assetID, sourceFingerprint: fingerprint)
    }

    private static func fingerprintForTrace(backing: Backing, kind: Kind, nativeExtent: CGSize,
                                            dataFingerprint: String?,
                                            fileChangeSignature: PhotoSourceFingerprint?) -> String {
        let extent = "\(Double(nativeExtent.width).bitPattern):\(Double(nativeExtent.height).bitPattern)"
        switch backing {
        case .data:
            return "data:\(dataFingerprint ?? "missing"):\(kind):\(extent)"
        case .url(let url):
            // Derived from the signature captured at resolution, so building the token never
            // touches the file. Subsequent event logging uses the stored token, while
            // cache/source replacement checks remain dynamic.
            let size = fileChangeSignature?.byteCount.map(String.init) ?? "missing"
            let modified = fileChangeSignature?.modificationDate?.timeIntervalSince1970.description
                ?? "missing"
            let resourceID = fileChangeSignature?.resourceIdentifier ?? "missing"
            return "url:\(url.standardizedFileURL.path):\(size):\(modified):\(resourceID):\(kind):\(extent)"
        }
    }

    private static func makeTraceToken(from fingerprint: String) -> String {
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return String(digest.prefix(16))
    }
}
