import XCTest
import CoreImage
@testable import KromoraKit

@MainActor
final class BundledLookTests: TempDirectoryTestCase {
    private func makeLibrary() -> LUTLibrary {
        let defaults = UserDefaults(suiteName: "Kromora.BundledLookTests")!
        defaults.removePersistentDomain(forName: "Kromora.BundledLookTests")
        return LUTLibrary(preferences: defaults, includeBundled: true)
    }

    func testManifestContainsApprovedProvenanceForEveryBundledLook() throws {
        let manifest = try BundledLookLibrary.validate()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertFalse(manifest.acknowledgement.isEmpty)
        XCTAssertEqual(manifest.looks.count, 16)
        XCTAssertEqual(
            Set(manifest.looks.map(\.category)),
            ["Monochrome", "Cinematic", "Film-inspired", "Warm slide-inspired",
             "Pastel", "Faded", "High-contrast", "Cool-toned", "Moody"]
        )
        XCTAssertEqual(Set(manifest.looks.map(\.id)).count, manifest.looks.count)
        XCTAssertEqual(Set(manifest.looks.map(\.resource)).count, manifest.looks.count)
        XCTAssertTrue(manifest.looks.allSatisfy { $0.id.hasPrefix("kromora.starter.") })
        XCTAssertTrue(manifest.looks.allSatisfy { $0.resource.hasSuffix(".cube") })
        XCTAssertTrue(manifest.looks.allSatisfy { $0.approval.status == "approved" })
        XCTAssertTrue(manifest.looks.allSatisfy { $0.license.contains("MIT") })
        XCTAssertTrue(manifest.looks.allSatisfy { $0.attribution.contains("No third-party") })
        XCTAssertTrue(manifest.looks.contains { $0.name == "Honey Negative" && $0.category == "Film-inspired" })
        XCTAssertTrue(manifest.looks.contains { $0.name == "Ember & Cyan" && $0.category == "Cinematic" })
        XCTAssertTrue(manifest.looks.contains { $0.name == "Pastel Wash" && $0.category == "Pastel" })
        XCTAssertTrue(manifest.looks.contains { $0.name == "Midnight Slate" && $0.category == "Cool-toned" })
        XCTAssertTrue(manifest.looks.contains { $0.name == "Forest Shadow" && $0.category == "Moody" })
        XCTAssertTrue(manifest.acknowledgement.contains("descriptive inspiration"))
    }

    func testApplicationLibrarySeparatesStarterLooksFromUserLooks() async throws {
        let library = makeLibrary()
        XCTAssertEqual(library.allLUTs.count, 16)
        XCTAssertTrue(library.allLUTs.allSatisfy { $0.source == .bundled })
        XCTAssertEqual(
            library.categories.map(\.name),
            ["Cinematic", "Cool-toned", "Faded", "Film-inspired", "High-contrast",
             "Monochrome", "Moody", "Pastel", "Warm slide-inspired"]
        )
        XCTAssertTrue(library.categories.allSatisfy { $0.source == .bundled })
        XCTAssertTrue(library.bundledLoadWarnings.isEmpty)

        let userURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "my-look.cube", in: tempDirectory
        )
        library.importLUT(from: userURL)
        while library.isImporting { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(library.allLUTs.filter { $0.source == .bundled }.count, 16)
        XCTAssertEqual(library.allLUTs.filter { $0.source == .user }.map(\.name), ["my-look"])
        XCTAssertEqual(library.categories.filter { $0.source == .user }.map(\.name), ["Imported"])
    }

    func testEveryBundledLookCanApplyWithoutMutatingTheInput() throws {
        let library = makeLibrary()
        let input = CIImage(color: CIColor(red: 0.31, green: 0.47, blue: 0.73))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        for look in library.allLUTs where look.source == .bundled {
            XCTAssertNotNil(look.makeFilter(), "\(look.name) did not create a Core Image cube filter")
            let output = try XCTUnwrap(look.apply(to: input), "\(look.name) did not apply")
            XCTAssertEqual(output.extent, input.extent)
        }
        XCTAssertEqual(input.extent, CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    func testBundledLooksHaveDistinctPreviewFingerprints() throws {
        let library = makeLibrary()
        let fingerprints = library.allLUTs
            .filter { $0.source == .bundled }
            .map(\.cacheFingerprint)

        XCTAssertEqual(fingerprints.count, 16)
        XCTAssertEqual(Set(fingerprints).count, fingerprints.count)
    }

    func testMalformedBundledEntryIsSkippedWithoutHidingHealthyEntries() throws {
        let directory = try Fixtures.makeTempDirectory("StarterLookPartial")
        defer { try? FileManager.default.removeItem(at: directory) }
        let validURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "healthy.cube", in: directory
        )
        let manifest = BundledLookManifest(
            schemaVersion: 1,
            acknowledgement: "Test acknowledgement",
            looks: [
                BundledLookManifest.Entry(
                    id: "healthy", name: "Healthy", category: "Test", resource: validURL.lastPathComponent,
                    sourceAuthor: "Tests", source: "Original", license: "MIT License (Kromora project license)", attribution: "None",
                    redistribution: "Allowed", approval: .init(status: "approved", recordID: "test-1", reviewer: "Tests", approvedAt: "2026-01-01", notes: "Test")
                ),
                BundledLookManifest.Entry(
                    id: "missing", name: "Missing", category: "Test", resource: "missing.cube",
                    sourceAuthor: "Tests", source: "Original", license: "MIT License (Kromora project license)", attribution: "None",
                    redistribution: "Allowed", approval: .init(status: "approved", recordID: "test-2", reviewer: "Tests", approvedAt: "2026-01-01", notes: "Test")
                ),
            ]
        )

        let loaded = BundledLookLibrary.load(manifest: manifest, resourceDirectory: directory)
        XCTAssertEqual(loaded.looks.map(\.name), ["Healthy"])
        XCTAssertEqual(loaded.warnings.count, 1)
        XCTAssertTrue(loaded.warnings[0].contains("Missing"))
    }
}
