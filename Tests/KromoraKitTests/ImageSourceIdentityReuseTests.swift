import XCTest

@testable import KromoraKit

/// Opening a photo from the package must not rehash the whole file on the main actor.
final class ImageSourceIdentityReuseTests: TempDirectoryTestCase {
    /// The package stores file dates as ISO-8601 whole seconds, so a change signature that went
    /// through the package never equals a fresh read of an unchanged file. `ImageSource` compared
    /// them with `==`, so every open of every library photo fell through to a whole-file SHA-256
    /// on the main actor (about 50 ms for a 126 MB RAW, and again for each adjacent photo).
    func testUnchangedFileKeepsItsPersistedContentHashAcrossAPackageRoundTrip() throws {
        let url = try Fixtures.writeJPEG(
            width: 64, height: 48, orientation: 1, named: "reuse.jpg", in: tempDirectory
        )
        // A modification time with a sub-second part, as every real file has.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_760_000_000.384)],
            ofItemAtPath: url.path
        )
        let observed = PhotoSourceFingerprint.file(at: url)
        let persisted = try PackageJSONCoder.decode(
            PhotoSourceFingerprint.self, from: PackageJSONCoder.encode(observed)
        )
        XCTAssertNotEqual(
            observed, persisted,
            "precondition: the package round trip drops the fractional second"
        )
        XCTAssertTrue(persisted.isSameFileSnapshot(as: observed))

        let identity = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(),
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "persisted-content-hash", decoderVersion: "import-v1"
            )
        )
        let source = ImageSource(
            url: url, nativeExtent: .zero, portableIdentity: identity,
            existingFileChangeSignature: persisted
        )
        XCTAssertEqual(
            source.portableIdentity.sourceFingerprint.contentHash, "persisted-content-hash",
            "an unchanged file must reuse the stored content hash instead of rehashing it"
        )
    }

    func testChangedFileStillRecomputesItsContentHash() throws {
        let url = try Fixtures.writeJPEG(
            width: 64, height: 48, orientation: 1, named: "changed.jpg", in: tempDirectory
        )
        let stale = PhotoSourceFingerprint(
            byteCount: 1, modificationDate: Date(timeIntervalSince1970: 1),
            resourceIdentifier: nil, sampleDigest: "old"
        )
        let identity = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(),
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "persisted-content-hash", decoderVersion: "import-v1"
            )
        )
        let source = ImageSource(
            url: url, nativeExtent: .zero, portableIdentity: identity,
            existingFileChangeSignature: stale
        )
        XCTAssertNotEqual(source.portableIdentity.sourceFingerprint.contentHash, "persisted-content-hash")
    }

    /// Package browsing assets carry a real content hash but a placeholder change signature, and
    /// five main-actor callers (edited thumbnails, adjacent previews, the idle warmer, open) build
    /// an `ImageSource` from them. None of those may read and hash the whole file.
    func testBrowsingAssetReusesItsContentHashWithoutReadingTheFile() throws {
        let url = try Fixtures.writeJPEG(
            width: 64, height: 48, orientation: 1, named: "browsing.jpg", in: tempDirectory
        )
        let assetID = PortablePhotoAssetID()
        let browsingSignature = PhotoSourceFingerprint(
            byteCount: nil, modificationDate: nil, resourceIdentifier: nil,
            sampleDigest: PhotoAssetID.contentDigest(Data("browsing:\(assetID.raw)".utf8))
        )
        XCTAssertTrue(browsingSignature.isBrowsingObservation)
        XCTAssertFalse(PhotoSourceFingerprint.file(at: url).isBrowsingObservation)

        let identity = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "stored-import-hash", decoderVersion: "import-v1"
            )
        )
        let source = ImageSource(
            url: url, nativeExtent: CGSize(width: 64, height: 48), portableIdentity: identity,
            existingFileChangeSignature: browsingSignature
        )
        XCTAssertEqual(source.portableIdentity.sourceFingerprint.contentHash, "stored-import-hash")
        XCTAssertEqual(
            source.portableIdentity.sourceFingerprint.geometry,
            PhotoPixelDimensions(width: 64, height: 48), "geometry is still applied"
        )
    }

    /// A summary with no persisted fingerprint has a synthetic identity too. That one has no real
    /// hash to reuse, so the file is still hashed.
    func testPlaceholderIdentityStillHashesTheFile() throws {
        let url = try Fixtures.writeJPEG(
            width: 64, height: 48, orientation: 1, named: "legacy.jpg", in: tempDirectory
        )
        let assetID = PortablePhotoAssetID()
        let browsingSignature = PhotoSourceFingerprint(
            byteCount: nil, modificationDate: nil, resourceIdentifier: nil, sampleDigest: "x"
        )
        let identity = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "synthetic", decoderVersion: "browsing-v1"
            )
        )
        let source = ImageSource(
            url: url, nativeExtent: .zero, portableIdentity: identity,
            existingFileChangeSignature: browsingSignature
        )
        XCTAssertNotEqual(source.portableIdentity.sourceFingerprint.contentHash, "synthetic")
    }
}
