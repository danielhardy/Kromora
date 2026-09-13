import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import KromoraKit

/// Builds disposable, deterministic libraries for scale and regression tests.
///
/// The generated files are deliberately tiny JPEGs with real ImageIO metadata. They are not camera
/// fixtures and are never checked in; the value records returned alongside them are what later
/// phases can use for filtering, sorting, edit, and thumbnail-demand benchmarks.
enum SyntheticLibraryGenerator {

    enum Scale: Int, CaseIterable, Sendable {
        case oneThousand = 1_000
        case tenThousand = 10_000
        case oneHundredThousand = 100_000

        var assetCount: Int { rawValue }
    }

    /// The metadata kept by the generator in the same shape as the current folder-backed asset
    /// model. Orientation remains separate because `PhotoAssetMetadata` intentionally stores only
    /// the display-facing subset; the generated JPEG carries the orientation tag too.
    struct Metadata: Codable, Equatable, Sendable {
        let dimensions: PhotoPixelDimensions
        let captureDate: String
        let cameraMake: String
        let cameraModel: String
        let lens: String
        let orientation: Int

        var photoAssetMetadata: PhotoAssetMetadata {
            PhotoAssetMetadata(
                dimensions: dimensions,
                captureDate: captureDate,
                cameraMake: cameraMake,
                cameraModel: cameraModel,
                lens: lens
            )
        }
    }

    /// A full current-schema edit value used as the synthetic asset's summary. Most assets are
    /// neutral; the non-neutral subset exercises develop/edit-aware paths without writing sidecars.
    struct EditSummary: Codable, Equatable, Sendable {
        let document: EditDocument

        var hasEdits: Bool { !document.isIdentity }
        var hasNonDefaultDevelopSettings: Bool { !document.rawDevelop.isNeutral }
    }

    struct Asset: Codable, Equatable, Sendable {
        let index: Int
        let relativePath: String
        let url: URL
        let metadata: Metadata
        let editSummary: EditSummary
        let needsThumbnailGeneration: Bool

        var filename: String { url.lastPathComponent }

        /// A value shaped exactly like the current folder-backed library record.
        var photoAsset: PhotoAsset {
            PhotoAsset(
                url: url,
                filename: filename,
                metadata: metadata.photoAssetMetadata,
                libraryState: PhotoAssetLibraryState(
                    thumbnail: needsThumbnailGeneration ? .notRequested : .ready
                )
            )
        }

        /// Convenience for consumers that need the edit document rather than its summary wrapper.
        var editDocument: EditDocument { editSummary.document }

        // The same generated layout is expected to compare equal when rooted in two different
        // temporary directories, so URL is intentionally excluded from value equality.
        static func == (lhs: Asset, rhs: Asset) -> Bool {
            lhs.index == rhs.index
                && lhs.relativePath == rhs.relativePath
                && lhs.metadata == rhs.metadata
                && lhs.editSummary == rhs.editSummary
                && lhs.needsThumbnailGeneration == rhs.needsThumbnailGeneration
        }
    }

    /// An owned generated root. Call `cleanup()` when a generated library is no longer needed, or
    /// use `withLibrary` to make cleanup automatic for both success and failure.
    struct GeneratedLibrary: Sendable {
        let rootURL: URL
        let scale: Scale
        let seed: UInt64
        let assets: [Asset]

        var assetCount: Int { assets.count }

        var existsOnDisk: Bool {
            FileManager.default.fileExists(atPath: rootURL.path)
        }

        func cleanup() throws {
            guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
            try FileManager.default.removeItem(at: rootURL)
        }
    }

    static let defaultSeed: UInt64 = 0x4B52_4D41_3339_34

    static func assetID(for index: Int) -> PortablePhotoAssetID? {
        guard let uuid = UUID(uuidString: String(
            format: "%08x-0000-4000-8000-%012x", index, index
        )) else { return nil }
        return PortablePhotoAssetID(uuid: uuid)
    }

    /// Generate one of the supported scales in a unique child directory of `parentDirectory`.
    /// When no parent is supplied, the system temporary directory is used.
    ///
    /// Generation yields cooperatively at least once per `yieldEvery` assets and checks task
    /// cancellation before every asset. Any cancellation or write error removes the partial root
    /// before rethrowing, so callers never inherit a half-generated library.
    static func generate(
        scale: Scale,
        seed: UInt64 = defaultSeed,
        in parentDirectory: URL? = nil,
        yieldEvery: Int = 128
    ) async throws -> GeneratedLibrary {
        let yieldInterval = max(1, yieldEvery)
        try Task.checkCancellation()

        let fileManager = FileManager.default
        let parent = parentDirectory ?? fileManager.temporaryDirectory
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent(
            "KromoraSyntheticLibrary-\(scale.rawValue)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        do {
            let assets = try await buildAssets(
                scale: scale,
                seed: seed,
                root: root,
                yieldEvery: yieldInterval
            )
            return GeneratedLibrary(rootURL: root, scale: scale, seed: seed, assets: assets)
        } catch {
            // The generated root is uniquely owned by this invocation. Do not touch the caller's
            // parent directory, which may also contain another generated run under comparison.
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    /// Generate a library for the duration of an async operation and always tear it down.
    static func withLibrary<Result>(
        scale: Scale,
        seed: UInt64 = defaultSeed,
        in parentDirectory: URL? = nil,
        yieldEvery: Int = 128,
        operation: (GeneratedLibrary) async throws -> Result
    ) async throws -> Result {
        let library = try await generate(
            scale: scale,
            seed: seed,
            in: parentDirectory,
            yieldEvery: yieldEvery
        )
        defer { try? library.cleanup() }
        return try await operation(library)
    }

    // MARK: - Generation

    private struct CameraProfile: Sendable {
        let make: String
        let model: String
        let lens: String
    }

    private struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    private struct PayloadKey: Hashable {
        let cameraIndex: Int
        let orientation: Int
        let captureDate: String
    }

    private static let cameraProfiles = [
        CameraProfile(make: "Kromora", model: "Synthetic One", lens: "Kromora 35mm f/1.8"),
        CameraProfile(make: "Kromora", model: "Synthetic Two", lens: "Kromora 50mm f/2.0"),
        CameraProfile(make: "Kromora", model: "Synthetic Three", lens: "Kromora 85mm f/2.8"),
        CameraProfile(make: "Kromora", model: "Synthetic Four", lens: "Kromora 24mm f/4.0"),
    ]

    private static let orientations = [1, 3, 6, 8]

    private static func buildAssets(
        scale: Scale,
        seed: UInt64,
        root: URL,
        yieldEvery: Int
    ) async throws -> [Asset] {
        let fileManager = FileManager.default
        var assets: [Asset] = []
        assets.reserveCapacity(scale.assetCount)

        // Many assets intentionally share a metadata profile. Caching its tiny encoded payload
        // keeps the 100k optional lane focused on filesystem scale instead of repeating ImageIO
        // setup for identical values.
        var payloads: [PayloadKey: Data] = [:]
        payloads.reserveCapacity(cameraProfiles.count * orientations.count * 32)

        for index in 0..<scale.assetCount {
            try Task.checkCancellation()

            let cameraIndex = cameraIndex(for: index, seed: seed)
            let metadata = metadata(for: index, seed: seed, cameraIndex: cameraIndex)
            let payloadKey = PayloadKey(
                cameraIndex: cameraIndex,
                orientation: metadata.orientation,
                captureDate: metadata.captureDate
            )
            let payload: Data
            if let cached = payloads[payloadKey] {
                payload = cached
            } else {
                let created = try jpegData(for: metadata, cameraIndex: cameraIndex)
                payloads[payloadKey] = created
                payload = created
            }

            let group = index % 10
            let groupName = String(format: "Group-%02d", group)
            let filename = String(format: "Photo-%06d.jpg", index)
            let relativePath = "\(groupName)/\(filename)"
            let directory = root.appendingPathComponent(groupName, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename)
            try payload.write(to: url)

            assets.append(Asset(
                index: index,
                relativePath: relativePath,
                url: url,
                metadata: metadata,
                editSummary: editSummary(for: index, seed: seed),
                needsThumbnailGeneration: needsThumbnail(for: index, seed: seed)
            ))

            if (index + 1) % yieldEvery == 0 {
                await Task.yield()
            }
        }

        try Task.checkCancellation()
        return assets
    }

    private static func cameraIndex(for index: Int, seed: UInt64) -> Int {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0xD1B5_4A32_D192_ED03)
        return Int(generator.next() % UInt64(cameraProfiles.count))
    }

    private static func metadata(for index: Int, seed: UInt64, cameraIndex: Int) -> Metadata {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0xA24B_AED4_963E_E407)
        let camera = cameraProfiles[cameraIndex]
        let orientation = orientations[Int(generator.next() % UInt64(orientations.count))]

        // Keep the encoded-payload profile set bounded for the 100k lane while still providing
        // enough dates to exercise sorting and filtering. The seed controls which of these 16
        // plausible capture moments each asset receives.
        let captureVariant = Int(generator.next() % 16)
        let month = captureVariant / 4 + 1
        let day = captureVariant % 4 + 1
        let hour = 9 + captureVariant % 8
        let minute = (captureVariant * 7) % 60
        let second = 0
        let captureDate = String(
            format: "2024:%02d:%02d %02d:%02d:%02d",
            month, day, hour, minute, second
        )

        let isQuarterTurned = orientation >= 5
        let dimensions = PhotoPixelDimensions(
            width: isQuarterTurned ? 48 : 64,
            height: isQuarterTurned ? 64 : 48
        )
        return Metadata(
            dimensions: dimensions,
            captureDate: captureDate,
            cameraMake: camera.make,
            cameraModel: camera.model,
            lens: camera.lens,
            orientation: orientation
        )
    }

    private static func editSummary(for index: Int, seed: UInt64) -> EditSummary {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E37_79B9)
        let roll = generator.next() % 100
        let document: EditDocument
        if roll < 12 {
            let exposure = (Double(generator.next() % 151) - 75) / 100
            document = EditDocument(rawDevelop: RAWDevelopSettings(exposure: exposure))
        } else if roll < 22 {
            let exposure = (Double(generator.next() % 201) - 100) / 100
            document = EditDocument(light: LightAdjustments(exposure: exposure))
        } else {
            document = EditDocument()
        }
        return EditSummary(document: document)
    }

    private static func needsThumbnail(for index: Int, seed: UInt64) -> Bool {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0xC6BC_2796_92B5_CC83)
        return generator.next() % 100 < 35
    }

    // MARK: - Synthetic bytes

    private static func jpegData(for metadata: Metadata, cameraIndex: Int) throws -> Data {
        let color = Double(cameraIndex + 1) / Double(cameraProfiles.count + 1)
        let image = try Fixtures.makeCGImage(
            width: 64,
            height: 48,
            red: CGFloat(color),
            green: CGFloat(0.2 + color / 3),
            blue: CGFloat(0.8 - color / 3)
        )
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw Fixtures.FixtureError.cannotCreateDestination
        }

        let exif: [CFString: Any] = [
            kCGImagePropertyExifLensModel: metadata.lens,
            kCGImagePropertyExifDateTimeOriginal: metadata.captureDate,
            kCGImagePropertyExifFNumber: 2.8,
            kCGImagePropertyExifExposureTime: 1.0 / 125.0,
            kCGImagePropertyExifISOSpeedRatings: [200],
            kCGImagePropertyExifFocalLength: 35.0,
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: metadata.cameraMake,
            kCGImagePropertyTIFFModel: metadata.cameraModel,
            kCGImagePropertyTIFFDateTime: metadata.captureDate,
            kCGImagePropertyTIFFSoftware: "Kromora synthetic-library generator",
            kCGImagePropertyTIFFOrientation: metadata.orientation,
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: metadata.orientation,
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Fixtures.FixtureError.cannotWriteImage
        }
        return data as Data
    }
}

/// A package-shaped view of a generated folder library. Membership summaries are copied into the
/// package, while asset records remain absent by default so query tests can prove that the index
/// path does not materialise them.
struct SyntheticPortableLibraryPackage {
    let package: PortableLibraryPackage
    let assetIDs: [PortablePhotoAssetID]
    let urlsByName: [String: URL]
    let assetRecordCanaryURLs: [URL]
}

extension SyntheticLibraryGenerator.GeneratedLibrary {
    func makePortableLibraryPackage(
        at packageURL: URL,
        addAssetRecordCanaries: Bool = false
    ) throws -> SyntheticPortableLibraryPackage {
        let package = try PortableLibraryPackage.create(at: packageURL)
        var entriesByShard = Dictionary(
            uniqueKeysWithValues: PortableLibraryPackage.allShards.map {
                ($0, [PortablePackageMembershipEntry]())
            }
        )
        var assetIDs: [PortablePhotoAssetID] = []
        assetIDs.reserveCapacity(assets.count)
        var urlsByName: [String: URL] = [:]
        urlsByName.reserveCapacity(assets.count)
        var canaryURLs: [URL] = []
        canaryURLs.reserveCapacity(addAssetRecordCanaries ? assets.count : 0)

        for asset in assets {
            guard let assetID = SyntheticLibraryGenerator.assetID(for: asset.index) else {
                throw NSError(domain: "SyntheticLibraryGenerator", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "could not create asset ID for index \(asset.index)"
                ])
            }
            assetIDs.append(assetID)
            urlsByName[asset.filename] = asset.url
            let shard = PortableLibraryPackage.shard(for: assetID)
            let recordPath = "Assets/\(shard)/\(assetID.raw)/asset.json"
            entriesByShard[shard, default: []].append(.init(
                assetID: assetID,
                recordPath: recordPath,
                summary: .init(
                    captureDate: asset.metadata.captureDate,
                    rating: asset.index % 6,
                    flag: asset.index.isMultiple(of: 3)
                        ? PhotoFlag.pick.rawValue : PhotoFlag.none.rawValue,
                    cameraMake: asset.metadata.cameraMake,
                    cameraModel: asset.metadata.cameraModel,
                    lens: asset.metadata.lens,
                    dimensions: asset.metadata.dimensions,
                    aspectRatio: Double(asset.metadata.dimensions.width)
                        / Double(asset.metadata.dimensions.height),
                    displayName: asset.filename,
                    assetRevision: UInt64(asset.index)
                )
            ))

            if addAssetRecordCanaries {
                let canaryURL = package.rootURL.appendingPathComponent(recordPath)
                try FileManager.default.createDirectory(
                    at: canaryURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data("asset-record-canary".utf8).write(to: canaryURL)
                canaryURLs.append(canaryURL)
            }
        }

        for shard in PortableLibraryPackage.allShards {
            var membership = try package.readMembershipShard(shard)
            membership.entries = entriesByShard[shard, default: []]
            try package.writeMembershipShard(membership)
        }

        return SyntheticPortableLibraryPackage(
            package: package,
            assetIDs: assetIDs,
            urlsByName: urlsByName,
            assetRecordCanaryURLs: canaryURLs
        )
    }
}
