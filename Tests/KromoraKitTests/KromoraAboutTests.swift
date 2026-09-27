import XCTest
@testable import KromoraKit

final class KromoraAboutTests: XCTestCase {
    func testAboutMetadataUsesBundleValues() {
        let metadata = KromoraAboutMetadata(infoDictionary: [
            "CFBundleShortVersionString": "0.1.4",
            "KromoraGitCommit": "0123456789ab",
        ])

        XCTAssertEqual(metadata.version, "0.1.4")
        XCTAssertEqual(metadata.commitIdentifier, "0123456789ab")
        XCTAssertEqual(metadata.versionLabel, "Version 0.1.4 · 0123456789ab")
    }

    func testAboutMetadataFallsBackForMissingOrBlankDevelopmentValues() {
        let metadata = KromoraAboutMetadata(infoDictionary: [
            "CFBundleShortVersionString": "  ",
            "KromoraGitCommit": " \n",
        ])

        XCTAssertEqual(metadata.version, "Development build")
        XCTAssertNil(metadata.commitIdentifier)
        XCTAssertEqual(metadata.versionLabel, "Version Development build")
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

    func testAboutShowsConciseLUTLicenseDisclosureWithoutInventory() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let aboutView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/KromoraAboutView.swift"),
            encoding: .utf8
        )
        let buildScript = try String(
            contentsOf: packageRoot.appendingPathComponent("scripts/build-macos-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(aboutView.contains("Image(nsImage: NSApplication.shared.applicationIconImage)"))
        XCTAssertTrue(aboutView.contains("Text(\"Kromora\")"))
        XCTAssertTrue(aboutView.contains("All included LUTs are released under the MIT License."))
        XCTAssertFalse(aboutView.contains("Bundled Starter Looks"))
        XCTAssertFalse(aboutView.contains("look.attribution"))
        XCTAssertFalse(aboutView.contains("textSelection(.enabled)"))
        XCTAssertTrue(buildScript.contains("git rev-parse --short=12 HEAD"))
        XCTAssertTrue(buildScript.contains("KromoraGitCommit"))
    }
}
