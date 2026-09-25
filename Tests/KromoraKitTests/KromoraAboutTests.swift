import XCTest
@testable import KromoraKit

final class KromoraAboutTests: XCTestCase {
    func testAboutMetadataUsesBundleValues() {
        let metadata = KromoraAboutMetadata(infoDictionary: [
            "CFBundleShortVersionString": "0.1.4",
            "CFBundleVersion": "27",
        ])

        XCTAssertEqual(metadata.version, "0.1.4")
        XCTAssertEqual(metadata.build, "27")
    }

    func testAboutMetadataFallsBackForMissingOrBlankDevelopmentValues() {
        let metadata = KromoraAboutMetadata(infoDictionary: [
            "CFBundleShortVersionString": "  ",
            "CFBundleVersion": 3,
        ])

        XCTAssertEqual(metadata.version, "Development build")
        XCTAssertEqual(metadata.build, "Unavailable in development build")
    }

    func testPackagedAboutLicenseMatchesTheRepositoryLicense() throws {
        let resourceURL = try XCTUnwrap(
            KromoraKitResourceBundle.url(forResource: "LICENSE", withExtension: "txt")
        )
        let packagedText = try String(contentsOf: resourceURL, encoding: .utf8)
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceText = try String(
            contentsOf: packageRoot.appendingPathComponent("LICENSE"),
            encoding: .utf8
        )

        XCTAssertEqual(packagedText, sourceText)
    }

    func testAboutMenuAndWindowArePresentForEveryBuildConfiguration() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuCommands = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/MenuCommands.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Kromora/KromoraApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(menuCommands.contains("CommandGroup(replacing: .appInfo)"))
        XCTAssertTrue(menuCommands.contains("Button(\"About Kromora\") { openWindow(id: KromoraAboutView.windowID) }"))
        XCTAssertTrue(app.contains("Window(\"About Kromora\", id: KromoraAboutView.windowID)"))
        XCTAssertTrue(menuCommands.contains("Button(\"Check for Updates…\") { updateCoordinator.checkNow() }"))
    }

    func testStarterLookDisclosureLivesInAboutAndNotTheLooksInspector() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let aboutView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/KromoraAboutView.swift"),
            encoding: .utf8
        )
        let lookInspector = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/LookInspectorView.swift"),
            encoding: .utf8
        )
        let manifest = try BundledLookLibrary.validate()

        XCTAssertTrue(aboutView.contains("GroupBox(\"Bundled Starter Looks\")"))
        XCTAssertTrue(aboutView.contains("starterLookManifest.acknowledgement"))
        XCTAssertTrue(aboutView.contains("look.license"))
        XCTAssertTrue(aboutView.contains("look.attribution"))
        XCTAssertTrue(aboutView.contains("look.redistribution"))
        XCTAssertFalse(lookInspector.contains("bundledAcknowledgement"))
        XCTAssertFalse(lookInspector.contains("starterAcknowledgement"))
        XCTAssertTrue(manifest.looks.allSatisfy { !$0.license.isEmpty && !$0.attribution.isEmpty && !$0.redistribution.isEmpty })
    }
}
