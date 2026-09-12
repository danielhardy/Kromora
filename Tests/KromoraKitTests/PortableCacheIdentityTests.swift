import CoreGraphics
import Foundation
import XCTest
@testable import KromoraKit

final class PortableCacheIdentityTests: TempDirectoryTestCase {
    private func identity(for url: URL) throws -> PortablePhotoIdentity {
        PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(
                uuid: UUID(uuidString: "1C0A2C7B-7E3F-4E5D-9F05-7FBA7E3D5B2A")!
            ),
            sourceFingerprint: try PortablePhotoSourceFingerprint.file(
                at: url, decoderVersion: "imageio-standard-v1",
                geometry: PhotoPixelDimensions(width: 96, height: 64)
            )
        )
    }

    func testRenderCacheHitsAfterRelocationWithTheSamePortableIdentity() async throws {
        let originalURL = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "before.png", in: tempDirectory
        )
        let movedURL = tempDirectory.appendingPathComponent("relocated/after.png")
        try FileManager.default.createDirectory(
            at: movedURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: originalURL, to: movedURL)

        let identity = try self.identity(for: movedURL)
        let first = ImageSource(
            url: movedURL, nativeExtent: CGSize(width: 96, height: 64),
            portableIdentity: identity
        )
        let second = ImageSource(
            url: movedURL, nativeExtent: CGSize(width: 96, height: 64),
            portableIdentity: identity
        )
        let engine = RenderEngine()
        let request = { (source: ImageSource) in
            RenderRequest(
                source: source, document: EditDocument(), targetSize: CGSize(width: 48, height: 32),
                quality: .preview, output: .raster, space: .sRGB
            )
        }

        _ = try await engine.render(request(first))
        _ = try await engine.render(request(second))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 1)
        XCTAssertEqual(stats.preview.hits, 1)
    }

    func testMaskAndPreviewDiskKeysUseOnlyPortableIdentity() async throws {
        let bytes = Data("portable-cache-source".utf8)
        let fingerprint = PortablePhotoSourceFingerprint.data(
            bytes, sourceRevision: 4, decoderVersion: "decoder-7",
            geometry: PhotoPixelDimensions(width: 12, height: 8)
        )
        let firstIdentity = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(uuid: UUID(uuidString: "D90B0CF5-85E5-4E5E-AD66-3E3B44F9B8B0")!),
            sourceFingerprint: fingerprint
        )
        let sameIdentity = PortablePhotoIdentity(
            assetID: firstIdentity.assetID, sourceFingerprint: fingerprint
        )
        let maskKey = MaskCacheKey(identity: firstIdentity, kind: .subject, quality: .preview)
        let movedMaskKey = MaskCacheKey(identity: sameIdentity, kind: .subject, quality: .preview)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let pixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [0, 1, 1, 0]
        )

        _ = try await store.store(pixels, for: maskKey, quality: .preview)
        let movedReference = await store.mask(for: movedMaskKey, quality: .preview)
        XCTAssertNotNil(movedReference)
        XCTAssertEqual(
            MaskStore.filenameForTesting(for: maskKey),
            MaskStore.filenameForTesting(for: movedMaskKey)
        )

        let previewA = PreviewDiskCache.Key(
            identity: firstIdentity, documentHash: "document", lookFingerprint: "look",
            space: .sRGB
        )
        let previewB = PreviewDiskCache.Key(
            identity: sameIdentity, documentHash: "document", lookFingerprint: "look",
            space: .sRGB
        )
        XCTAssertEqual(previewA.canonicalKeyString, previewB.canonicalKeyString)
        XCTAssertFalse(previewA.canonicalKeyString.contains("/"))
    }

    func testChangingContentChangesRenderIdentityEvenWhenAssetUUIDIsRetained() throws {
        let url = tempDirectory.appendingPathComponent("mutable.png")
        try Data("before".utf8).write(to: url)
        let initial = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(),
            sourceFingerprint: try PortablePhotoSourceFingerprint.file(
                at: url, decoderVersion: "decoder-1"
            )
        )
        let before = ImageSource(url: url, nativeExtent: .zero, portableIdentity: initial)
        let beforeKey = RenderSourceFingerprint(before)
        try Data("after".utf8).write(to: url)
        let after = ImageSource(url: url, nativeExtent: .zero, portableIdentity: initial)

        XCTAssertEqual(beforeKey.identity.assetID, after.cacheIdentity.assetID)
        XCTAssertNotEqual(
            beforeKey.identity.sourceFingerprint.contentHash,
            after.cacheIdentity.sourceFingerprint.contentHash
        )
        XCTAssertNotEqual(beforeKey, RenderSourceFingerprint(after))
    }

    func testImageSourceCacheIdentityRefreshesAfterFileMetadataChanges() throws {
        let url = tempDirectory.appendingPathComponent("session.png")
        try Data("before".utf8).write(to: url)

        let source = ImageSource(url: url, nativeExtent: .zero)
        let sessionIdentity = source.cacheIdentity
        XCTAssertEqual(source.cacheIdentity, sessionIdentity)

        try Data("after".utf8).write(to: url)

        let refreshedIdentity = source.cacheIdentity
        XCTAssertNotEqual(refreshedIdentity, sessionIdentity)
        XCTAssertNotEqual(
            refreshedIdentity.sourceFingerprint.contentHash,
            sessionIdentity.sourceFingerprint.contentHash
        )
    }

    func testPhotoAssetCacheKeySurvivesRelocationAndInvalidatesReplacement() throws {
        let originalURL = tempDirectory.appendingPathComponent("asset.png")
        try Data("asset-before".utf8).write(to: originalURL)
        let assetID = PhotoAssetID(rawValue: "legacy-record")
        let portableID = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(),
            sourceFingerprint: try PortablePhotoSourceFingerprint.file(
                at: originalURL, decoderVersion: "decoder-1"
            )
        )
        let before = PhotoAssetSource(
            url: originalURL, id: assetID, data: nil, portableIdentity: portableID
        )

        let movedURL = tempDirectory.appendingPathComponent("moved/asset.png")
        try FileManager.default.createDirectory(
            at: movedURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        let moved = PhotoAssetSource(
            url: movedURL, id: assetID, data: nil, portableIdentity: portableID
        )
        XCTAssertEqual(before.cacheKey, moved.cacheKey)

        try Data("asset-after".utf8).write(to: movedURL)
        let replaced = PhotoAssetSource(
            url: movedURL, id: assetID, data: nil, portableIdentity: portableID
        )
        XCTAssertNotEqual(moved.cacheKey, replaced.cacheKey)
        XCTAssertEqual(moved.cacheIdentity.assetID, replaced.cacheIdentity.assetID)
    }
}
