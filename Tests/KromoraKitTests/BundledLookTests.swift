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
        XCTAssertEqual(manifest.looks.count, 14)
        XCTAssertEqual(
            Set(manifest.looks.map(\.category)),
            ["Monochrome", "Cinematic", "Film-inspired", "Warm slide-inspired",
             "Pastel", "Faded", "High-contrast", "Slide"]
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
        XCTAssertFalse(manifest.looks.contains { $0.name == "Neon Dusk" })
        XCTAssertFalse(manifest.looks.contains { $0.name == "Midnight Slate" })
        XCTAssertFalse(manifest.looks.contains { $0.name == "Forest Shadow" })
        XCTAssertTrue(manifest.acknowledgement.contains("descriptive inspiration"))
        XCTAssertFalse(manifest.acknowledgement.localizedCaseInsensitiveContains("mit"))
    }

    func testApplicationLibrarySeparatesStarterLooksFromUserLooks() async throws {
        let library = makeLibrary()
        XCTAssertEqual(library.allLUTs.count, 14)
        XCTAssertTrue(library.allLUTs.allSatisfy { $0.source == .bundled })
        XCTAssertEqual(library.lookCollections.map(\.title), ["Starter Looks", "My Looks"])
        XCTAssertEqual(library.starterLooks.count, 14)
        XCTAssertEqual(
            library.starterCategories.map(\.name),
            ["Monochrome", "Cinematic", "Faded", "Film-inspired", "High-contrast",
             "Pastel", "Slide", "Warm slide-inspired"]
        )
        XCTAssertEqual(Set(library.starterLooks.prefix(5).map(\.category)), ["Monochrome"])
        XCTAssertTrue(library.starterLooks.allSatisfy { $0.source == .bundled })
        XCTAssertTrue(library.myLooks.isEmpty, "the empty My Looks collection must remain visible")
        XCTAssertTrue(library.lookCollections[0].isReadOnly)
        XCTAssertFalse(library.lookCollections[1].isReadOnly)
        XCTAssertEqual(
            library.categories.map(\.name),
            ["Monochrome", "Cinematic", "Faded", "Film-inspired", "High-contrast",
             "Pastel", "Slide", "Warm slide-inspired"]
        )
        XCTAssertTrue(library.categories.allSatisfy { $0.source == .bundled })
        XCTAssertTrue(library.bundledLoadWarnings.isEmpty)

        let userURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "my-look.cube", in: tempDirectory
        )
        library.importLUT(from: userURL)
        while library.isImporting { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(library.allLUTs.filter { $0.source == .bundled }.count, 14)
        XCTAssertEqual(library.allLUTs.filter { $0.source == .user }.map(\.name), ["my-look"])
        XCTAssertEqual(library.categories.filter { $0.source == .user }.map(\.name), ["Imported"])
        XCTAssertEqual(library.starterLooks.count, 14)
        XCTAssertEqual(library.myLooks.map(\.name), ["my-look"])
        XCTAssertTrue(library.myLooks.allSatisfy { $0.source != .bundled })
        XCTAssertEqual(library.lookCollections.map { $0.looks.count }, [14, 1])
    }

    func testLookCollectionsHaveDeterministicFlatOrderingAcrossCategories() async throws {
        let preferences = UserDefaults(suiteName: "Kromora.BundledLookOrderingTests")!
        preferences.removePersistentDomain(forName: "Kromora.BundledLookOrderingTests")
        let library = LUTLibrary(
            preferences: preferences,
            userLookFolderURL: tempDirectory.appendingPathComponent("user-looks", isDirectory: true)
        )
        let folder = tempDirectory.appendingPathComponent("ordered-looks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Zebra.cube", in: folder)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Alpha.cube", in: nested)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Middle.cube", in: folder)

        library.scan(folder)
        while library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(library.myLooks.map(\.name), ["Alpha", "Middle", "Zebra"])
        XCTAssertEqual(library.lookCollections.map { $0.looks.map(\.name) }, [[], ["Alpha", "Middle", "Zebra"]])
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

        XCTAssertEqual(fingerprints.count, 14)
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

    func testStarterLookIDIsIndependentOfInstallLocation() throws {
        let entry = BundledLookManifest.Entry(
            id: "kromora.starter.relocated", name: "Relocated", category: "Test", resource: "relocated.cube",
            sourceAuthor: "Tests", source: "Original", license: "MIT License (Kromora project license)", attribution: "None",
            redistribution: "Allowed", approval: .init(status: "approved", recordID: "test-3", reviewer: "Tests", approvedAt: "2026-01-01", notes: "Test")
        )
        let manifest = BundledLookManifest(schemaVersion: 1, acknowledgement: "Test", looks: [entry])

        let firstInstall = try Fixtures.makeTempDirectory("StarterLookInstallA")
        let secondInstall = try Fixtures.makeTempDirectory("StarterLookInstallB")
        defer {
            try? FileManager.default.removeItem(at: firstInstall)
            try? FileManager.default.removeItem(at: secondInstall)
        }
        for directory in [firstInstall, secondInstall] {
            _ = try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "relocated.cube", in: directory)
        }

        let saved = try XCTUnwrap(
            BundledLookLibrary.load(manifest: manifest, resourceDirectory: firstInstall).looks.first
        )
        let otherBuild = BundledLookLibrary.load(manifest: manifest, resourceDirectory: secondInstall).looks
        XCTAssertNotEqual(saved.url, otherBuild.first?.url)

        let resolved = try XCTUnwrap(otherBuild.first(matching: saved.lutID))
        XCTAssertEqual(resolved.id, "kromora.starter.relocated")
        XCTAssertEqual(resolved.source, .bundled)

        let library = makeLibrary()
        library.allLUTs = otherBuild
        let coordinator = LookSelectionCoordinator(library: library)
        let reloadedDocument = EditDocument(lut: LUTSettings(lutID: saved.lutID, intensity: 0.72))
        let resolvedAfterRelocation = try XCTUnwrap(coordinator.resolve(reloadedDocument.lut.lutID))
        let request = LookPreviewRequest(
            source: ImageSource(data: Data([1]), nativeExtent: CGSize(width: 8, height: 8)),
            document: reloadedDocument,
            look: resolvedAfterRelocation,
            targetSize: CGSize(width: 8, height: 8)
        ).renderRequest
        XCTAssertEqual(request.document.lut.lutID, reloadedDocument.lut.lutID)
        XCTAssertEqual(request.document.lut.intensity, 1)
        XCTAssertEqual(request.lut?.lutID, saved.lutID)
        XCTAssertEqual(request.lut?.url, resolved.url)
        XCTAssertTrue(resolved.id.hasPrefix("kromora.starter."))
    }
}
