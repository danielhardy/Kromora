#if KROMORA_DIRECT_DISTRIBUTION
import Foundation
import XCTest
@testable import KromoraKit

@MainActor
final class UpdateTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "KromoraUpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func release(_ version: String, diskImage: URL? = URL(string: "https://objects.example/update.dmg")) -> KromoraRelease {
        KromoraRelease(
            version: AppVersion(version)!,
            title: "Kromora \(version)",
            notes: "Notes for \(version)",
            pageURL: URL(string: "https://github.com/danielhardy/Kromora/releases/tag/v\(version)")!,
            diskImageURL: diskImage
        )
    }

    private func waitForPhase(
        _ coordinator: UpdateCoordinator,
        matching predicate: @escaping (UpdateCoordinator.Phase?) -> Bool
    ) async {
        for _ in 0..<100 {
            if predicate(coordinator.phase) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for updater phase; got \(String(describing: coordinator.phase))")
    }

    func testVersionComparisonAndStrictTagParsing() throws {
        XCTAssertEqual(AppVersion("v1.2"), AppVersion(1, 2, 0))
        XCTAssertEqual(AppVersion("1"), AppVersion(1, 0, 0))
        XCTAssertNil(AppVersion("v1.2.3-beta"))

        let validJSON = """
        {"tag_name":"v1.4.0","name":"Kromora 1.4","body":"Fixes","html_url":"https://github.com/danielhardy/Kromora/releases/tag/v1.4.0","assets":[{"name":"Kromora-1.4.0.dmg","browser_download_url":"https://objects.example/Kromora-1.4.0.dmg","size":42}]}
        """
        let parsed = try KromoraReleaseFeed.parse(Data(validJSON.utf8))
        XCTAssertEqual(parsed.version, AppVersion(1, 4, 0))
        XCTAssertEqual(parsed.diskImageSize, 42)

        let invalid = validJSON.replacingOccurrences(of: "v1.4.0", with: "nightly")
        XCTAssertThrowsError(try KromoraReleaseFeed.parse(Data(invalid.utf8))) { error in
            XCTAssertEqual(error as? KromoraReleaseFeed.FeedError, .unusableTag("nightly"))
        }
    }

    func testManualCheckReportsUpToDateAndAvailable() async {
        let upToDate = release("1.0.0")
        let current = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: makeDefaults(), fetch: { upToDate }
        )
        current.checkNow()
        await waitForPhase(current) { $0 == .upToDate }
        XCTAssertTrue(current.isSheetPresented)

        let newer = release("1.1.0")
        let available = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: makeDefaults(), fetch: { newer }
        )
        available.checkNow()
        await waitForPhase(available) { $0 == .available(newer) }
        XCTAssertTrue(available.isSheetPresented)
    }

    func testSkippedVersionIsShownManuallyButSuppressedAutomatically() async {
        let defaults = makeDefaults()
        let newer = release("1.1.0")
        let first = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: defaults, fetch: { newer }
        )
        first.checkNow()
        await waitForPhase(first) { $0 == .available(newer) }
        first.skip(newer)

        let manual = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: defaults, fetch: { newer }
        )
        manual.checkNow()
        await waitForPhase(manual) { $0 == .skipped(newer) }

        let automatic = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: defaults, fetch: { newer }
        )
        automatic.checkAutomaticallyIfDue()
        await waitForPhase(automatic) { _ in automatic.lastCheck != nil }
        XCTAssertNil(automatic.phase)
        XCTAssertFalse(automatic.isSheetPresented)
    }

    func testAutomaticFailureIsQuietAndSignatureFailureIsSurfaced() async {
        enum TestError: Error { case offline }
        let automatic = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: makeDefaults(), fetch: { throw TestError.offline }
        )
        automatic.checkAutomaticallyIfDue()
        await waitForPhase(automatic) { _ in automatic.lastCheck != nil }
        XCTAssertNil(automatic.phase)
        XCTAssertFalse(automatic.isSheetPresented)

        let newer = release("1.1.0")
        let failed = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0),
            canInstallInPlace: true,
            defaults: makeDefaults(),
            fetch: { newer },
            install: { _ in throw KromoraUpdateInstaller.InstallError.signatureRejected("test rejection") }
        )
        failed.checkNow()
        await waitForPhase(failed) { $0 == .available(newer) }
        failed.installAndRelaunch(newer)
        await waitForPhase(failed) {
            if case .failed = $0 { return true }
            return false
        }
        XCTAssertTrue(failed.isSheetPresented)
    }

    func testMissingDMGAndUnsignedBuildUseReleasePagePath() async {
        let noDMG = release("1.1.0", diskImage: nil)
        let coordinator = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), defaults: makeDefaults(), fetch: { noDMG }
        )
        coordinator.checkNow()
        await waitForPhase(coordinator) { $0 == .available(noDMG) }
        XCTAssertNil(noDMG.diskImageURL)

        let unsigned = UpdateCoordinator(
            currentVersion: AppVersion(1, 0, 0), canInstallInPlace: false,
            defaults: makeDefaults(), fetch: { noDMG }, openPage: { _ in true }
        )
        unsigned.checkNow()
        await waitForPhase(unsigned) { $0 == .available(noDMG) }
        unsigned.installAndRelaunch(noDMG)
        XCTAssertNil(unsigned.phase)
        XCTAssertFalse(unsigned.isSheetPresented)
    }

    func testStagedCopyVerificationFailureLeavesCurrentAppUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraSwapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let current = root.appendingPathComponent("Kromora.app", isDirectory: true)
        let incoming = root.appendingPathComponent("Incoming.app", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let currentMarker = current.appendingPathComponent("marker.txt")
        try Data("installed version".utf8).write(to: currentMarker)
        try Data("candidate version".utf8).write(to: incoming.appendingPathComponent("marker.txt"))

        XCTAssertThrowsError(try KromoraUpdateInstaller.swap(newApp: incoming, into: current) { staged in
            XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appendingPathComponent("marker.txt").path))
            throw KromoraUpdateInstaller.InstallError.signatureRejected("staged copy rejected")
        }) { error in
            XCTAssertEqual(error as? KromoraUpdateInstaller.InstallError, .signatureRejected("staged copy rejected"))
        }

        XCTAssertEqual(try String(contentsOf: currentMarker, encoding: .utf8), "installed version")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(Set(remaining), Set(["Kromora.app", "Incoming.app"]))
    }
}
#endif
