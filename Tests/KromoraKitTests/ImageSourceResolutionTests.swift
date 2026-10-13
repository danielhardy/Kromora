import CryptoKit
import XCTest
@testable import KromoraKit

/// KRMA-950: constructing an `ImageSource` is pure; identity resolution is an explicit step that
/// streams its hashing.
final class ImageSourceResolutionTests: XCTestCase {

    func testStreamingFileHashMatchesOneShotDigestOf64MiBFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("krma950-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        // Not a multiple of the chunk size, and non-repeating across chunks.
        var bytes = Data(count: 64 * 1024 * 1024 + 12_345)
        bytes.withUnsafeMutableBytes { buffer in
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            for index in buffer.indices {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                buffer[index] = UInt8(truncatingIfNeeded: state >> 33)
            }
        }
        try bytes.write(to: url)

        let streamed = try PortablePhotoSourceFingerprint.contentHash(ofFileAt: url)
        XCTAssertEqual(streamed, PortablePhotoSourceFingerprint.contentHash(of: bytes))
        XCTAssertEqual(
            try PortablePhotoSourceFingerprint.file(at: url, decoderVersion: "t").contentHash,
            streamed
        )
    }

    func testAsyncResolveMatchesBlockingResolveAndHashesTheFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("krma950-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        try bytes.write(to: url)

        let resolved = await ImageSource.resolve(url: url, nativeExtent: .zero)
        XCTAssertEqual(
            resolved.portableIdentity.sourceFingerprint.contentHash,
            PortablePhotoSourceFingerprint.contentHash(of: bytes)
        )
        XCTAssertEqual(
            resolved.portableIdentity,
            ImageSource.resolveBlocking(url: url, nativeExtent: .zero).portableIdentity
        )
    }

    func testMemberwiseInitializerDoesNotTouchTheFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/krma950-\(UUID().uuidString).dng")
        let identity = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(),
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "abc", decoderVersion: "imageio-raw-v1"
            )
        )
        let source = ImageSource(
            url: missing, nativeExtent: .zero, portableIdentity: identity, fileChangeSignature: nil
        )
        XCTAssertEqual(source.portableIdentity, identity)
        XCTAssertEqual(source.cacheIdentity, identity)
    }

    /// The initializers must stay free of file I/O and hashing. Read as source text because the
    /// property has no runtime trace until a regression stalls the main actor (KRMA-860).
    func testImageSourceInitializersContainNoFileIO() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/KromoraKit/Models/ImageSource.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "    init(\n        backing: Backing,"))
        let end = try XCTUnwrap(source.range(of: "    // MARK: - Identity resolution"))
        let initializers = String(source[start.lowerBound..<end.lowerBound])
        for forbidden in [
            "Data(contentsOf:", "PortablePhotoSourceFingerprint.file(", "PhotoSourceFingerprint.file(",
            "FileHandle", "resourceValues",
        ] {
            XCTAssertFalse(
                initializers.contains(forbidden),
                "ImageSource initializers must not reference \(forbidden); resolve identity in `resolve`."
            )
        }
    }
}
