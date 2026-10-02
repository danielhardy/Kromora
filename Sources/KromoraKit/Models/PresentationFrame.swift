import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Value model

/// Where a persisted presentation raster came from. Only `preview2048` has a store today; the
/// thumbnail kinds share the same classifier so every surface answers "may these pixels stand in
/// for the current photo?" identically.
enum PresentationFrameKind: String, Codable, Sendable, Equatable {
    case preview2048
    case originalThumbnail480
    case editedThumbnail480
}

/// The raster's color space, independent of the working space it was rendered in.
///
/// Rasters are encoded in their working space's profile, so today the two are 1:1. Keeping the
/// raster's identity separate is what lets the classifier reason about *presentability*: an sRGB
/// raster is inside every supported display space, a Display P3 raster is not inside sRGB.
enum RasterColorSpace: String, Codable, Sendable, Equatable {
    case sRGB
    case displayP3

    init(_ space: WorkingSpace) {
        switch space {
        case .sRGB: self = .sRGB
        case .displayP3: self = .displayP3
        }
    }

    /// True when presenting this raster in `space` loses no color information.
    func isLosslesslyPresentable(in space: WorkingSpace) -> Bool {
        switch (self, space) {
        case (.sRGB, _): return true
        case (.displayP3, .displayP3): return true
        case (.displayP3, .sRGB): return false
        }
    }
}

/// Everything that gives a raster its pixel meaning. Container layout is deliberately absent; it
/// has its own `storageFormatVersion`.
struct FrameSignature: Codable, Equatable, Sendable {
    let source: PortablePhotoIdentity
    let editHash: String
    let look: LookSignature
    let workingSpace: WorkingSpace
    let pixelEpoch: Int
}

/// The crop and rotation the raster was presented with. Recorded so a cell or canvas can reserve
/// the final aspect ratio before pixels arrive.
struct PresentedGeometry: Codable, Equatable, Sendable {
    let crop: CropAdjustments
    let rotation: ImageRotation
    let orientedAspectRatio: Double
}

/// A tiny, fixed-size fingerprint of how a frame looks: an 8×8 grid of mean R, G, B in the raster's
/// own encoding. Two digests of the same photo differ only where the pixels visibly differ, which
/// is all the refinement policy needs to decide whether a swap deserves a crossfade.
struct PerceptualDigest: Codable, Equatable, Sendable {
    static let gridSide = 8
    static let byteCount = gridSide * gridSide * 3

    let bytes: Data

    init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        guard let digest = PerceptualDigest(bytes: data) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Digest has \(data.count) bytes"
            )
        }
        self = digest
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }

    /// Mean absolute per-channel difference, 0 (identical) through 1 (black versus white).
    func distance(to other: PerceptualDigest) -> Double {
        var total = 0
        for (lhs, rhs) in zip(bytes, other.bytes) {
            total += abs(Int(lhs) - Int(rhs))
        }
        return Double(total) / Double(255 * Self.byteCount)
    }
}

struct PresentationFrameMetadata: Codable, Equatable, Sendable {
    let identity: PortablePhotoIdentity
    let kind: PresentationFrameKind
    let signature: FrameSignature
    let geometry: PresentedGeometry
    let rasterColorSpace: RasterColorSpace
    let perceptualDigest: PerceptualDigest
    let presentedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
}

/// A persisted raster plus the metadata that says what it depicts. `rasterData` is the encoded
/// (JPEG) payload; decoding to pixels is a separate, explicit step.
struct PresentationFrame: Sendable, Equatable {
    let metadata: PresentationFrameMetadata
    let rasterData: Data

    var identity: PortablePhotoIdentity { metadata.identity }
    var kind: PresentationFrameKind { metadata.kind }
    var signature: FrameSignature { metadata.signature }
    var geometry: PresentedGeometry { metadata.geometry }
    var rasterColorSpace: RasterColorSpace { metadata.rasterColorSpace }
    var perceptualDigest: PerceptualDigest { metadata.perceptualDigest }
    var presentedAt: Date { metadata.presentedAt }
}

// MARK: - Freshness

/// What the caller currently knows about the pixels it wants. `editHash` and `look` are `nil`
/// until stored edits and Look resolution have finished; a frame may hide latency in that window
/// but must not suppress work.
struct FrameCurrentInputs: Sendable, Equatable {
    let source: PortablePhotoIdentity
    let editHash: String?
    let look: LookSignature?
    let workingSpace: WorkingSpace
    let pixelEpoch: Int

    init(
        source: PortablePhotoIdentity, editHash: String? = nil, look: LookSignature? = nil,
        workingSpace: WorkingSpace = .current, pixelEpoch: Int = RenderPipeline.pixelEpoch
    ) {
        self.source = source
        self.editHash = editHash
        self.look = look
        self.workingSpace = workingSpace
        self.pixelEpoch = pixelEpoch
    }

    /// Every input that determines pixels is known, and none of them is an unresolved Look.
    var isFullyResolved: Bool {
        editHash != nil && look?.permitsExactReuse == true
    }
}

enum FrameClassification: Sendable, Equatable {
    /// Same pixels the current inputs would render. Present and skip the render.
    case exact
    /// Same photo, presentable, but an input differs. Present inert pixels, render, replace once.
    case staleCompatible
    /// Same photo, but current edit or Look truth is not known yet. May hide latency only.
    case provisionalOnly
    /// Must not be shown.
    case unusable

    var isPresentable: Bool { self != .unusable }
}

enum FrameRejectionReason: String, Sendable, Equatable, CaseIterable {
    case assetMismatch
    case sourceFingerprintMismatch
    case placeholderSourceIdentity
    case dimensionsInvalid
    case colorSpaceUnpresentable
}

/// The only freshness implementation. Pure: no I/O, no clock, no UI.
enum FrameClassifier {
    /// The long edge every durable preview is rendered at. A larger raster is not a valid frame.
    static let previewLongEdge = 2048

    static func classify(
        _ frame: PresentationFrameMetadata, against current: FrameCurrentInputs
    ) -> FrameClassification {
        classifyWithReason(frame, against: current).classification
    }

    static func classifyWithReason(
        _ frame: PresentationFrameMetadata, against current: FrameCurrentInputs
    ) -> (classification: FrameClassification, reason: FrameRejectionReason?) {
        if isPlaceholder(current.source) { return (.unusable, .placeholderSourceIdentity) }
        guard frame.identity.assetID == current.source.assetID,
              frame.signature.source.assetID == current.source.assetID
        else { return (.unusable, .assetMismatch) }
        guard frame.identity.sourceFingerprint.matches(current.source.sourceFingerprint)
        else { return (.unusable, .sourceFingerprintMismatch) }
        guard frame.pixelWidth > 0, frame.pixelHeight > 0,
              max(frame.pixelWidth, frame.pixelHeight) <= previewLongEdge
        else { return (.unusable, .dimensionsInvalid) }
        guard frame.rasterColorSpace.isLosslesslyPresentable(in: current.workingSpace)
        else { return (.unusable, .colorSpaceUnpresentable) }
        guard let editHash = current.editHash, let look = current.look,
              look.permitsExactReuse
        else { return (.provisionalOnly, nil) }

        let signature = frame.signature
        let matches = signature.source.sourceFingerprint.matches(current.source.sourceFingerprint)
            && signature.editHash == editHash
            && signature.look.isExactMatch(of: look)
            && signature.workingSpace == current.workingSpace
            && signature.pixelEpoch == current.pixelEpoch
        return (matches ? .exact : .staleCompatible, nil)
    }

    private static func isPlaceholder(_ identity: PortablePhotoIdentity) -> Bool {
        identity.sourceFingerprint.contentHash.isEmpty || identity.sourceFingerprint.decoderVersion.isEmpty
    }
}

// MARK: - Refinement

enum FrameTransition: Sendable, Equatable {
    case immediate
    case crossfade(duration: TimeInterval)
}

/// Decides how a stale frame is replaced by its refinement: at most one short crossfade, and only
/// when the pixels visibly differ.
enum FrameRefinementPolicy {
    static let crossfadeDuration: TimeInterval = 0.12

    /// Mean per-channel digest distance (0…1) above which a replacement is animated.
    ///
    /// Chosen from the generated fixtures in `FrameRefinementPolicyTests`, which pin it. Measured
    /// on a 512×384 ramp-and-blocks image: visible edits — +0.5 EV exposure 0.170, −0.5 EV 0.122,
    /// a 12 % warm white-balance shift 0.034. Sub-visible changes — a 1-level brightness step
    /// 0.004, 2 levels 0.008, +0.01 EV 0.003, identical pixels 0. 0.02 clears the largest
    /// sub-visible value by 2.5× and sits below the smallest visible one.
    static let crossfadeDigestThreshold = 0.02

    static func transition(
        from old: PerceptualDigest?, to new: PerceptualDigest?, reduceMotion: Bool
    ) -> FrameTransition {
        guard !reduceMotion, let old, let new,
              old.distance(to: new) > crossfadeDigestThreshold
        else { return .immediate }
        return .crossfade(duration: crossfadeDuration)
    }
}

// MARK: - Envelope

/// One atomically replaceable file holding a frame's metadata and JPEG together, so a crash can
/// never pair new metadata with an old raster.
///
/// ```
/// offset 0   4 bytes  magic "KFRM"
/// offset 4   4 bytes  storageFormatVersion (big-endian UInt32)
/// offset 8   4 bytes  header length H (big-endian UInt32, <= maxHeaderBytes)
/// offset 12  H bytes  JSON `Header`
/// offset 12+H  R bytes  JPEG, where R is `Header.rasterByteCount` and must reach end of file
/// ```
///
/// Every length is validated against the file size before any buffer is allocated, so a corrupt
/// or hostile length cannot trigger a large allocation.
enum PresentationFrameEnvelope {
    /// Bump only when this layout can no longer be decoded. An older or newer file is an
    /// unsupported per-entry miss; it never clears the directory.
    static let storageFormatVersion: UInt32 = 1
    static let fileExtension = "kframe"
    static let magic = Data("KFRM".utf8)
    static let prefixLength = 12
    static let maxHeaderBytes = 16 * 1024
    static let maxRasterBytes = 32 * 1024 * 1024
    static let maxPixelDimension = 4096

    enum DecodeError: Error, Equatable {
        case unreadable
        case badMagic
        case unsupportedVersion(UInt32)
        case badHeaderLength
        case malformedHeader
        case truncated
        case trailingBytes
        case identityMismatch
        case invalidDimensions
        case corruptRaster
    }

    private struct Header: Codable {
        let metadata: PresentationFrameMetadata
        let rasterByteCount: Int
    }

    static func encode(_ frame: PresentationFrame) throws -> Data {
        let header = try PackageJSONCoder.encode(
            Header(metadata: frame.metadata, rasterByteCount: frame.rasterData.count)
        )
        var data = Data()
        data.reserveCapacity(prefixLength + header.count + frame.rasterData.count)
        data.append(magic)
        data.append(bigEndian: storageFormatVersion)
        data.append(bigEndian: UInt32(header.count))
        data.append(header)
        data.append(frame.rasterData)
        return data
    }

    /// Read and validate a frame. `expectedAssetID` binds the file to the identity it is being
    /// asked for; a mismatch is a miss, not a wrong photo. With `includeRaster == false` only the
    /// header is read and `rasterData` is empty.
    static func read(
        from url: URL, expectedAssetID: PortablePhotoAssetID?, includeRaster: Bool = true
    ) throws(DecodeError) -> PresentationFrame {
        let handle: FileHandle
        let fileSize: Int
        do {
            handle = try FileHandle(forReadingFrom: url)
            fileSize = Int(try handle.seekToEnd())
            try handle.seek(toOffset: 0)
        } catch { throw .unreadable }
        defer { try? handle.close() }

        let prefix: Data
        do { prefix = try handle.read(upToCount: prefixLength) ?? Data() } catch { throw .unreadable }
        guard prefix.count == prefixLength else {
            throw prefix.starts(with: magic.prefix(prefix.count)) ? .truncated : .badMagic
        }
        guard prefix.prefix(4) == magic else { throw .badMagic }
        let version = prefix.readBigEndianUInt32(at: 4)
        guard version == storageFormatVersion else { throw .unsupportedVersion(version) }
        let headerLength = Int(prefix.readBigEndianUInt32(at: 8))
        guard headerLength > 0, headerLength <= maxHeaderBytes else { throw .badHeaderLength }
        guard prefixLength + headerLength <= fileSize else { throw .truncated }

        let headerBytes: Data
        do { headerBytes = try handle.read(upToCount: headerLength) ?? Data() } catch {
            throw .unreadable
        }
        guard headerBytes.count == headerLength else { throw .truncated }
        let header: Header
        do { header = try PackageJSONCoder.decode(Header.self, from: headerBytes) } catch {
            throw .malformedHeader
        }

        let metadata = header.metadata
        try validate(metadata, rasterByteCount: header.rasterByteCount, expectedAssetID: expectedAssetID)
        let expectedSize = prefixLength + headerLength + header.rasterByteCount
        guard fileSize >= expectedSize else { throw .truncated }
        guard fileSize == expectedSize else { throw .trailingBytes }

        guard includeRaster else {
            return PresentationFrame(metadata: metadata, rasterData: Data())
        }
        let raster: Data
        do { raster = try handle.read(upToCount: header.rasterByteCount) ?? Data() } catch {
            throw .unreadable
        }
        guard raster.count == header.rasterByteCount else { throw .truncated }
        return PresentationFrame(metadata: metadata, rasterData: raster)
    }

    /// Decode a frame held in memory, such as a packed-thumbnail record. The same validation as
    /// `read(from:)` applies, and the record must be exactly one envelope: a shifted or partial
    /// read can never pass as a frame.
    static func decode(
        _ data: Data, expectedAssetID: PortablePhotoAssetID?, includeRaster: Bool = true
    ) throws(DecodeError) -> PresentationFrame {
        guard data.count >= prefixLength else {
            throw data.starts(with: magic.prefix(data.count)) ? .truncated : .badMagic
        }
        guard data.prefix(4) == magic else { throw .badMagic }
        let version = data.readBigEndianUInt32(at: 4)
        guard version == storageFormatVersion else { throw .unsupportedVersion(version) }
        let headerLength = Int(data.readBigEndianUInt32(at: 8))
        guard headerLength > 0, headerLength <= maxHeaderBytes else { throw .badHeaderLength }
        guard prefixLength + headerLength <= data.count else { throw .truncated }
        let headerStart = data.startIndex + prefixLength
        let header: Header
        do {
            header = try PackageJSONCoder.decode(
                Header.self, from: data[headerStart..<(headerStart + headerLength)]
            )
        } catch { throw .malformedHeader }

        let metadata = header.metadata
        try validate(metadata, rasterByteCount: header.rasterByteCount, expectedAssetID: expectedAssetID)
        let expectedSize = prefixLength + headerLength + header.rasterByteCount
        guard data.count >= expectedSize else { throw .truncated }
        guard data.count == expectedSize else { throw .trailingBytes }
        guard includeRaster else {
            return PresentationFrame(metadata: metadata, rasterData: Data())
        }
        let rasterStart = headerStart + headerLength
        return PresentationFrame(
            metadata: metadata,
            rasterData: Data(data[rasterStart..<(rasterStart + header.rasterByteCount)])
        )
    }

    private static func validate(
        _ metadata: PresentationFrameMetadata, rasterByteCount: Int,
        expectedAssetID: PortablePhotoAssetID?
    ) throws(DecodeError) {
        guard metadata.identity.assetID == metadata.signature.source.assetID,
              expectedAssetID.map({ $0 == metadata.identity.assetID }) ?? true
        else { throw .identityMismatch }
        guard (1...maxPixelDimension).contains(metadata.pixelWidth),
              (1...maxPixelDimension).contains(metadata.pixelHeight),
              metadata.geometry.orientedAspectRatio.isFinite,
              metadata.geometry.orientedAspectRatio > 0
        else { throw .invalidDimensions }
        guard rasterByteCount > 0, rasterByteCount <= maxRasterBytes
        else { throw .badHeaderLength }
    }

    /// Decode the JPEG payload, checking its own dimensions against the metadata before any pixel
    /// buffer is created.
    static func decodeRaster(of frame: PresentationFrame) throws(DecodeError) -> CGImage {
        guard let source = CGImageSourceCreateWithData(frame.rasterData as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw .corruptRaster }
        guard width == frame.metadata.pixelWidth, height == frame.metadata.pixelHeight
        else { throw .invalidDimensions }
        guard let image = CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else { throw .corruptRaster }
        return image
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(self[base + $1]) }
    }
}
