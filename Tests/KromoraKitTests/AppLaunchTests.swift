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
            at: packageURL, deviceName: "killed-swift-run", duration: -1
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
            makeViewModel: { settings, packageURL, confirmer in
                AppViewModel(
                    engine: RenderEngine.shared,
                    preferences: defaults,
                    includeBundledLooks: false,
                    portablePackageURL: packageURL,
                    leaseRecoveryConfirmer: confirmer,
                    settings: settings
                )
            }
        )
    }

    func testLaunchOpensLibraryWhenTakeoverAccepted() async throws {
        let (url, stale) = try makeStaleLibrary()
        let sheets = FakeSheets()
        sheets.confirmResult = true
        let model = await launch(url, sheets: sheets).open()
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.canImportIntoPortableLibrary)
        await model.shutdown()
        _ = stale
    }

    func testLaunchStaysClosedWhenTakeoverDeclined() async throws {
        let (url, stale) = try makeStaleLibrary()
        let sheets = FakeSheets()
        sheets.confirmResult = false
        let appLaunch = launch(url, sheets: sheets)
        let model = await appLaunch.open()
        XCTAssertFalse(model.canImportIntoPortableLibrary)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(appLaunch.viewModel === model)
        await model.shutdown()
        _ = stale
    }
}
