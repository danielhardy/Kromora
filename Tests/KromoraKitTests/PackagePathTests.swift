import Foundation
import XCTest

@testable import KromoraKit

final class PackagePathTests: TempDirectoryTestCase {
    func testPackagePathRejectsAbsoluteTraversalAndDotComponents() throws {
        XCTAssertThrowsError(try PackagePath("/outside/file.jpg"))
        XCTAssertThrowsError(try PackagePath("Assets/../outside/file.jpg"))
        XCTAssertThrowsError(try PackagePath("Assets/./file.jpg"))
        XCTAssertThrowsError(try PackagePath("Assets//file.jpg"))
        XCTAssertThrowsError(try PackagePath("Assets\\file.jpg"))
    }

    func testPackagePathAcceptsValidNestedPathAndRejectsSymlinkEscape() throws {
        let root = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let valid = try PackagePath("Assets/ab/asset/Original/source.jpg").url(in: root)
        XCTAssertEqual(valid.path, root.appendingPathComponent("Assets/ab/asset/Original/source.jpg").path)

        let outside = tempDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let escapedDirectory = root.appendingPathComponent("Assets")
        try FileManager.default.createSymbolicLink(
            at: escapedDirectory, withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try PackagePath("Assets/secret.jpg").url(in: root)
        ) { error in
            XCTAssertEqual(error as? PackagePathError, .escapesRoot("Assets/secret.jpg"))
        }
    }

    func testValidationReportsSymlinkedOriginalAsCritical() throws {
        let packageURL = tempDirectory.appendingPathComponent("Malicious.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "ab000000-0000-4000-8000-000000000001")!)
        let relativeOriginal = "Assets/ab/\(assetID.raw)/Original/source.jpg"
        let record = PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: .data(Data("outside".utf8), decoderVersion: "test")
            ),
            source: .embedded(relativePath: relativeOriginal)
        )
        let assetDirectory = packageURL.appendingPathComponent("Assets/ab/\(assetID.raw)")
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        let outside = tempDirectory.appendingPathComponent("OutsideOriginal")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside.appendingPathComponent("source.jpg"))
        try FileManager.default.createSymbolicLink(
            at: assetDirectory.appendingPathComponent("Original"), withDestinationURL: outside
        )
        try PackageJSONCoder.encode(record).write(
            to: assetDirectory.appendingPathComponent("asset.json"), options: .atomic
        )

        var shard = try package.readMembershipShard("ab")
        shard.entries = [
            .init(
                assetID: assetID,
                recordPath: "Assets/ab/\(assetID.raw)/asset.json",
                summary: .init(displayName: "source.jpg")
            )
        ]
        try package.writeMembershipShard(shard)

        let report = try PortableLibraryValidation.run(at: packageURL)
        XCTAssertTrue(
            report.criticalFailures.contains {
                $0.message.contains("unsafe") || $0.message.contains("escapes")
            },
            report.criticalFailures.map(\.message).joined(separator: "\n")
        )
    }
}

