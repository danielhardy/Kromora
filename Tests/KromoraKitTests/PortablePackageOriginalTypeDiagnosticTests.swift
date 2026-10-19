import Foundation
import XCTest

@testable import KromoraKit

final class PortablePackageOriginalTypeDiagnosticTests: TempDirectoryTestCase {
    private let jpegHead = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8) + [0, 1, 1, 0])

    private func makePackage(_ files: [(String, Data)]) throws
        -> (PortableLibraryPackage, [String: PortablePhotoAssetID])
    {
        let packageURL = tempDirectory.appendingPathComponent("Diag.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceDir = tempDirectory.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        var sources: [PortablePackageImportSource] = []
        for (name, data) in files {
            let url = sourceDir.appendingPathComponent(name)
            try data.write(to: url)
            sources.append(.init(url: url))
        }
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let result = try package.importSources(sources, lease: lease)
        try lease.release()
        var ids: [String: PortablePhotoAssetID] = [:]
        for item in result.imported { ids[item.source.name] = item.assetID }
        return (package, ids)
    }

    func testListsMismatchedOriginalsWithoutModifyingThem() throws {
        let (package, ids) = try makePackage([
            ("DSC00160.ARW", jpegHead + Data(repeating: 0, count: 64)),
            ("good.jpg", jpegHead + Data(repeating: 2, count: 64)),
            ("renamed.jpg", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 16))),
            ("opaque.dat", Data("not an image".utf8)),
        ])
        let before = try snapshot(package.rootURL)

        let report = try package.scanOriginalFileTypes()

        XCTAssertEqual(report.assetsScanned, 4)
        let byName = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.displayName, $0) })
        XCTAssertEqual(Set(byName.keys), ["DSC00160.ARW", "renamed.jpg"])
        let raw = try XCTUnwrap(byName["DSC00160.ARW"])
        XCTAssertEqual(raw.assetID, ids["DSC00160.ARW"])
        XCTAssertEqual(raw.detectedFormat, "JPEG")
        XCTAssertTrue(raw.isRAWName)
        XCTAssertTrue(raw.relativePath.hasSuffix("/Original/DSC00160.ARW"), raw.relativePath)
        XCTAssertTrue(raw.message.contains("not RAW"))
        XCTAssertTrue(raw.guidance.contains("Photos"))
        XCTAssertEqual(byName["renamed.jpg"]?.detectedFormat, "PNG")
        XCTAssertEqual(try snapshot(package.rootURL), before, "the diagnostic must not change the package")
    }

    func testCleanPackageHasNoFindings() throws {
        let (package, _) = try makePackage([("a.jpg", jpegHead + Data(repeating: 1, count: 32))])
        let report = try package.scanOriginalFileTypes()
        XCTAssertEqual(report.assetsScanned, 1)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testTIFFHeaderUnderRAWNameIsNotRAWFinding() throws {
        // A TIFF byte-order header ImageIO cannot classify as RAW is not proof of a RAW file.
        let (package, _) = try makePackage([
            ("fake.ARW", Data([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
        ])
        let report = try package.scanOriginalFileTypes()
        XCTAssertEqual(report.assetsScanned, 1)
        XCTAssertEqual(report.findings.map(\.detectedFormat), ["TIFF"])
    }

    func testCancellationPropagates() throws {
        let (package, _) = try makePackage([("a.jpg", jpegHead)])
        XCTAssertThrowsError(try package.scanOriginalFileTypes(isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = e?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            out[url.path] = try Data(contentsOf: url)
        }
        return out
    }
}
