import AppKit
import XCTest
@testable import KromoraKit

@MainActor
final class AppLaunchTests: XCTestCase {
    private func makeStaleLibrary() throws -> (URL, PortablePackageLease) {
        let directory = try Fixtures.makeTempDirectory("AppLaunchTests")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let packageURL = directory.appendingPathComponent("Library.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL)
        try session.lease.release()
        return (packageURL, try PortablePackageLease.acquire(
            at: packageURL, deviceName: "killed-swift-run", processID: .max,
            writerHostID: "another-host", processStartedAt: "1:0", duration: -1
        ))
    }

    private func decision(_ sheets: FakeSheets, _ url: URL) async -> ResolvedLeaseRecoveryConfirmer? {
        await PortablePackageLeaseRecoveryPrompt(sheets: sheets).decision(for: url)
    }

    func testRecoveryPromptAcceptReportsTakeover() async throws {
        let (url, stale) = try makeStaleLibrary()
        let sheets = FakeSheets()
        sheets.confirmResult = true
        let answer = await decision(sheets, url)
        XCTAssertEqual(answer?.allowBreak, true)
        XCTAssertEqual(sheets.lastConfirmButtons, ["Take Over Library", "Not Now"])
        _ = stale
    }

    func testRecoveryPromptCancelDeclinesTakeover() async throws {
        let (url, stale) = try makeStaleLibrary()
        let sheets = FakeSheets()
        sheets.confirmResult = false
        let answer = await decision(sheets, url)
        XCTAssertEqual(answer?.allowBreak, false)
        _ = stale
    }

    func testRecoveryPromptSkipsWhenNoDecisionIsNeeded() async throws {
        let directory = try Fixtures.makeTempDirectory("AppLaunchTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fresh.kromoralibrary")
        let sheets = FakeSheets()
        let answer = await decision(sheets, url)
        XCTAssertNil(answer)
        XCTAssertEqual(sheets.confirmCalls, 0)
    }

    private func launch(_ url: URL, sheets: FakeSheets) -> AppLaunch {
        let defaults = UserDefaults(suiteName: "AppLaunchTests-\(UUID().uuidString)")!
        return AppLaunch(
            settings: KromoraSettings(preferences: defaults),
            packageURL: url,
            sheets: sheets,
            makeViewModel: { settings, packageURL in
                AppViewModel(
                    engine: RenderEngine.shared,
                    preferences: defaults,
                    includeBundledLooks: false,
                    portablePackageURL: packageURL,
                    settings: settings,
                    asynchronousPortableLibraryIndexLoading: true,
                    defersLibraryOpen: true
                )
            }
        )
    }

    func testLibraryPackageOverrideAcceptsOnlyAbsolutePaths() {
        let key = "KROMORA_LIBRARY_PACKAGE"
        XCTAssertEqual(
            AppLaunch.libraryPackageOverride(
                environment: [key: "/tmp/Disposable.kromoralibrary"], allowed: true)?.path,
            "/tmp/Disposable.kromoralibrary")
        XCTAssertNil(AppLaunch.libraryPackageOverride(environment: [:], allowed: true))
        XCTAssertNil(AppLaunch.libraryPackageOverride(environment: [key: ""], allowed: true))
        XCTAssertNil(AppLaunch.libraryPackageOverride(
            environment: [key: "Relative.kromoralibrary"], allowed: true))
    }

    func testLibraryPackageOverrideIsIgnoredUnlessBuildAllowsIt() {
        XCTAssertNil(AppLaunch.libraryPackageOverride(
            environment: ["KROMORA_LIBRARY_PACKAGE": "/tmp/Disposable.kromoralibrary"], allowed: false))
        XCTAssertFalse(AppLaunch.allowsLibraryOverride, "the test host is not a verification bundle")
    }

    func testProductionConfigurationExcludesOverrideAndVerificationBuildKeepsIt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func text(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        XCTAssertTrue(try text("Config/Base.xcconfig").contains("\nKROMORA_ALLOW_LIBRARY_OVERRIDE =\n"))
        XCTAssertFalse(try text("Config/Release.xcconfig").contains("KROMORA_ALLOW_LIBRARY_OVERRIDE"))
        XCTAssertTrue(try text("Kromora/Info.plist").contains("$(KROMORA_ALLOW_LIBRARY_OVERRIDE)"))
        let build = try text("scripts/app-store-build.sh")
        XCTAssertTrue(build.contains("KROMORA_VERIFICATION_BUILD"))
        XCTAssertTrue(build.contains("KROMORA_ALLOW_LIBRARY_OVERRIDE=YES"))
        XCTAssertTrue(try text("scripts/disposable-app.sh").contains("KromoraAllowLibraryOverride"))
    }

    func testNoModelExistsUntilOpenIsRequested() throws {
        let (url, _) = try makeStaleLibrary()
        let appLaunch = launch(url, sheets: FakeSheets())
        XCTAssertNil(appLaunch.viewModel, "construction does no package work and builds no model")
    }

    func testDelegateTerminatesBeforeFirstFrameCreatesModel() {
        let delegate = KromoraAppDelegate()

        XCTAssertNil(delegate.launch.viewModel)
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
    }

    func testLaunchOpensLibraryWhenTakeoverAccepted() async throws {
        let (url, stale) = try makeStaleLibrary()
        let sheets = FakeSheets()
        sheets.confirmResult = true
        let appLaunch = launch(url, sheets: sheets)
        let model = appLaunch.open()
        XCTAssertEqual(model.libraryOpen.state, .opening, "the window does not wait for the open")
        XCTAssertFalse(model.canImportIntoPortableLibrary)
        await appLaunch.waitForLibraryOpen()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(sheets.confirmCalls, 1, "the takeover question is asked exactly once")
        XCTAssertEqual(model.libraryOpen.state, .ready)
        XCTAssertTrue(model.canImportIntoPortableLibrary)
        await model.shutdown()
        _ = stale
    }

    func testLaunchStaysClosedWhenTakeoverDeclined() async throws {
        let (url, stale) = try makeStaleLibrary()
        let sheets = FakeSheets()
        sheets.confirmResult = false
        let appLaunch = launch(url, sheets: sheets)
        let model = appLaunch.open()
        await appLaunch.waitForLibraryOpen()
        XCTAssertEqual(sheets.confirmCalls, 1)
        XCTAssertFalse(model.canImportIntoPortableLibrary)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(appLaunch.viewModel === model)
        await model.shutdown()
        _ = stale
    }
}
