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
}
