import Foundation
import XCTest
@testable import KromoraKit

final class PortablePhotoIdentityTests: TempDirectoryTestCase {

    func testSameContentAtDifferentPathsHasByteIdenticalPortableIdentity() throws {
        let bytes = Data("same source bytes".utf8)
        let firstURL = tempDirectory.appendingPathComponent("first/photo.jpg")
        let secondURL = tempDirectory.appendingPathComponent("second/renamed.jpg")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try bytes.write(to: firstURL)
        try bytes.write(to: secondURL)

        let uuid = UUID(uuidString: "B3D1C7AF-90D6-4DB3-9CB3-8F8E4C8D1E11")!
        let firstFingerprint = try PortablePhotoSourceFingerprint.file(
            at: firstURL, sourceRevision: 7, decoderVersion: "decoder-3",
            geometry: PhotoPixelDimensions(width: 4000, height: 3000)
        )
        let secondFingerprint = try PortablePhotoSourceFingerprint.file(
            at: secondURL, sourceRevision: 7, decoderVersion: "decoder-3",
            geometry: PhotoPixelDimensions(width: 4000, height: 3000)
        )
        let first = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(uuid: uuid), sourceFingerprint: firstFingerprint
        )
        let second = PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(uuid: uuid), sourceFingerprint: secondFingerprint
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.canonicalData, second.canonicalData)
        XCTAssertEqual(first.cacheKey, second.cacheKey)
    }

    func testMovingAndRenamingContentPreservesIdentity() throws {
        let originalURL = tempDirectory.appendingPathComponent("before.jpg")
        let movedURL = tempDirectory.appendingPathComponent("nested/after.jpg")
        try Data(repeating: 0x42, count: 1024).write(to: originalURL)
        try FileManager.default.createDirectory(
            at: movedURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: originalURL, to: movedURL)

        let fingerprint = try PortablePhotoSourceFingerprint.file(
            at: movedURL, sourceRevision: 1, decoderVersion: "decoder-1"
        )
        let sameUUID = PortablePhotoAssetID(
            uuid: UUID(uuidString: "C8D71D77-0DBD-4C49-B681-04D8B0F0AA23")!
        )
        let movedIdentity = PortablePhotoIdentity(assetID: sameUUID, sourceFingerprint: fingerprint)

        XCTAssertFalse(movedIdentity.cacheKey.contains("before"))
        XCTAssertFalse(movedIdentity.cacheKey.contains("after"))
        XCTAssertEqual(fingerprint, .data(
            Data(repeating: 0x42, count: 1024), sourceRevision: 1, decoderVersion: "decoder-1"
        ))
    }

    func testDifferentContentAtTheSamePathChangesIdentity() throws {
        let url = tempDirectory.appendingPathComponent("replace.jpg")
        try Data("before".utf8).write(to: url)
        let before = try PortablePhotoSourceFingerprint.file(
            at: url, sourceRevision: 1, decoderVersion: "decoder-1"
        )
        try Data("after".utf8).write(to: url)
        let after = try PortablePhotoSourceFingerprint.file(
            at: url, sourceRevision: 2, decoderVersion: "decoder-1"
        )

        XCTAssertNotEqual(before.contentHash, after.contentHash)
        XCTAssertNotEqual(before, after)
        XCTAssertNotEqual(before.cacheKey, after.cacheKey)
    }

    func testRelativePathResolutionIsExplicitlyAtRenderBoundary() throws {
        let root = tempDirectory.appendingPathComponent("Library", isDirectory: true)
        let resolved = try RenderBoundarySourceResolver.resolve(
            packageRelativePath: "Assets/01/photo.jpg", packageRoot: root
        )

        XCTAssertEqual(resolved.path, root.appendingPathComponent("Assets/01/photo.jpg").path)
        XCTAssertThrowsError(try RenderBoundarySourceResolver.resolve(
            packageRelativePath: "../outside.jpg", packageRoot: root
        )) { error in
            XCTAssertEqual(error as? RenderBoundarySourceResolver.ResolutionError, .escapesPackage)
        }
    }
}
