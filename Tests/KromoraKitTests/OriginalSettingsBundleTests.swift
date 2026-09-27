import Foundation
import XCTest
@testable import KromoraKit

final class OriginalSettingsBundleTests: XCTestCase {
    func testBundleIncludesUnmodifiedOriginalAndVerifiableSettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("original image bytes".utf8)
        let destination = root.appendingPathComponent("Photo.\(OriginalSettingsBundle.fileExtension)")

        try await OriginalSettingsBundle.create(
            source: ImageSource(data: original, nativeExtent: .zero),
            sourceName: "Photo.raw",
            document: EditDocument(),
            destination: destination,
            locationMetadataIncluded: false
        )

        let manifest = try OriginalSettingsBundle.verify(at: destination)
        XCTAssertEqual(manifest.originalFilename, "Photo.raw")
        XCTAssertTrue(manifest.originalsAreReadOnly)
        XCTAssertFalse(manifest.locationMetadataIncluded)
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("Photo.raw")), original
        )
        XCTAssertNoThrow(try JSONDecoder().decode(
            EditDocument.self,
            from: Data(contentsOf: destination.appendingPathComponent(OriginalSettingsBundle.settingsFilename))
        ))
    }

    func testVerificationRejectsChangedOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Photo.\(OriginalSettingsBundle.fileExtension)")
        try await OriginalSettingsBundle.create(
            source: ImageSource(data: Data("original".utf8), nativeExtent: .zero),
            sourceName: "Photo.raw",
            document: EditDocument(),
            destination: destination,
            locationMetadataIncluded: false
        )
        try Data("modified".utf8).write(to: destination.appendingPathComponent("Photo.raw"))

        XCTAssertThrowsError(try OriginalSettingsBundle.verify(at: destination))
    }

    func testVerificationRejectsChangedSettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Photo.\(OriginalSettingsBundle.fileExtension)")
        try await OriginalSettingsBundle.create(
            source: ImageSource(data: Data("original".utf8), nativeExtent: .zero),
            sourceName: "Photo.raw",
            document: EditDocument(),
            destination: destination,
            locationMetadataIncluded: false
        )
        try Data("changed settings".utf8).write(
            to: destination.appendingPathComponent(OriginalSettingsBundle.settingsFilename)
        )

        XCTAssertThrowsError(try OriginalSettingsBundle.verify(at: destination))
    }
}
