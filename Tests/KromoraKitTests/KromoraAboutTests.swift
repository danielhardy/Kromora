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
}
