import Foundation
import XCTest

@testable import KromoraKit

final class PortableLibraryValidationTests: TempDirectoryTestCase {
    func testValidationSeparatesCanonicalChecksumsFromRebuildableGaps() throws {
        let packageURL = tempDirectory.appendingPathComponent("Validation.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("canonical source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)

        let indexURL = tempDirectory.appendingPathComponent("Indexes/LibraryIndex.store")
        let expectedPreview = "Derived/Previews/\(assetID.raw).jpg"
        let expectedThumbnail = "Derived/Thumbnails/\(PortableLibraryPackage.shard(for: assetID)).pack"
        let masksURL = tempDirectory.appendingPathComponent("Masks")
        let analysisURL = tempDirectory.appendingPathComponent("Analysis")

        let report = try package.validate(options: .init(
            localIndexURL: indexURL,
            masksDirectoryURL: masksURL,
            analysisDirectoryURL: analysisURL,
            expectedRebuildablePaths: [expectedPreview, expectedThumbnail]
        ))

        XCTAssertTrue(report.criticalFailures.isEmpty, report.criticalFailures.map(\.message).joined(separator: "\n"))
        XCTAssertFalse(report.rebuildableGaps.isEmpty)
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .preview && $0.path == expectedPreview })
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .thumbnail && $0.path == expectedThumbnail })
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .localIndex })
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .mask })
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .analysis })
        XCTAssertTrue(report.checkedFiles.contains { $0.component == .original })
        XCTAssertTrue(report.isValid, "rebuildable gaps must not become critical failures")
    }

    func testCorruptAssetRecordAndEditSidecarAreCritical() throws {
        let packageURL = tempDirectory.appendingPathComponent("CanonicalCorruption.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("canonical source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        _ = try package.appendEditRevision(for: assetID, document: EditDocument(), lease: lease)
        try lease.release()

        let record = try package.readAssetRecord(for: assetID)
        let recordURL = packageURL.appendingPathComponent("Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/asset.json")
        try Data("{not-json".utf8).write(to: recordURL)
        let recordReport = try PortableLibraryValidation.run(at: packageURL)
        XCTAssertTrue(recordReport.criticalFailures.contains { $0.component == .assetRecord })
        XCTAssertFalse(recordReport.criticalFailures.contains { $0.component == .original && $0.kind == .missing })
        _ = record

        // Restore the record so the sidecar is reached by the second scrub.
        try package.writeAssetRecord(record)
        let pointer = try XCTUnwrap(record.editHistory.edits.first)
        let xmpURL = packageURL.appendingPathComponent(try XCTUnwrap(pointer.xmpRelativePath))
        try Data("<truncated".utf8).write(to: xmpURL)
        let sidecarReport = try package.scrub()
        XCTAssertTrue(sidecarReport.criticalFailures.contains { $0.component == .editSidecar })
        XCTAssertTrue(sidecarReport.criticalFailures.allSatisfy { $0.component != .preview && $0.component != .thumbnail })
    }

    func testStaleIndexAndMalformedDerivedArtifactsStayRebuildable() throws {
        let packageURL = tempDirectory.appendingPathComponent("RebuildableCorruption.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)

        let indexURL = tempDirectory.appendingPathComponent("Index/LibraryIndex.store")
        let emptyIndex = try LibraryIndexProjection(libraryID: package.manifest.libraryID, entries: [])
        try emptyIndex.write(to: indexURL)
        let previewURL = packageURL.appendingPathComponent("Derived/Previews/bad.jpg")
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: previewURL)
        let thumbnailURL = packageURL.appendingPathComponent("Derived/Thumbnails/00.pack")
        try FileManager.default.createDirectory(at: thumbnailURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 3).write(to: thumbnailURL)

        let report = try package.validate(options: .init(
            localIndexURL: indexURL,
            expectedRebuildablePaths: ["Derived/Previews/missing.jpg"]
        ))

        XCTAssertTrue(report.criticalFailures.isEmpty, report.criticalFailures.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .localIndex && $0.kind == .stale })
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .preview && $0.kind == .corrupt })
        XCTAssertTrue(report.rebuildableGaps.contains { $0.component == .preview && $0.kind == .missing })
        XCTAssertTrue(report.checkedFiles.contains { $0.path == thumbnailURL.path.replacingOccurrences(of: packageURL.path + "/", with: "") })
        _ = assetID
    }

    func testValidationDoesNotMutateThePackage() throws {
        let packageURL = tempDirectory.appendingPathComponent("ReadOnly.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let before = try snapshot(packageURL)
        _ = try package.validate()
        let after = try snapshot(packageURL)
        XCTAssertEqual(after, before)
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return [:]
        }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result[relative] = try Data(contentsOf: url)
        }
        return result
    }
}
