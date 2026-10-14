import XCTest
import UniformTypeIdentifiers
@testable import KromoraKit

@MainActor
final class ActiveLibrarySelectionTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var defaultURL: URL!

    override func setUp() async throws {
        directory = try Fixtures.makeTempDirectory("ActiveLibrarySelectionTests")
        defaults = UserDefaults(suiteName: "ActiveLibrarySelectionTests-\(UUID().uuidString)")!
        defaultURL = directory.appendingPathComponent("Default.kromoralibrary")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var selection: ActiveLibrarySelection {
        ActiveLibrarySelection(preferences: defaults, defaultURL: defaultURL)
    }

    private func makePackage(_ name: String) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        let session = try PortableLibrarySession(at: url)
        try session.lease.release()
        return url
    }

    private func access(_ url: URL) -> SecurityScopedResourceAccess {
        .systemGranted(for: url, stop: { _ in })
    }

    func testValidPackageIsAcceptedAndResolvedAtLaunch() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        try selection.choose(url, access: access(url))
        XCTAssertTrue(selection.hasChoice)
        let resolution = selection.resolve()
        XCTAssertEqual(resolution.url.standardizedFileURL.resolvingSymlinksInPath(),
                       url.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(resolution.notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultURL.path))
    }

    func testInvalidFolderIsRejectedAndChangesNothing() throws {
        let folder = directory.appendingPathComponent("Plain.kromoralibrary")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try selection.choose(folder, access: access(folder))) {
            XCTAssertEqual($0 as? ActiveLibrarySelection.ChoiceError, .notALibrary(name: "Plain.kromoralibrary"))
        }
        XCTAssertFalse(selection.hasChoice)
        XCTAssertEqual(selection.resolve().url, defaultURL)
    }

    func testBookmarkRoundTripsAndUseDefaultClearsIt() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        try selection.choose(url, access: access(url))
        XCTAssertEqual(selection.chosenURL?.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
        selection.useDefault()
        XCTAssertFalse(selection.hasChoice)
        XCTAssertNil(selection.chosenURL)
        XCTAssertEqual(selection.resolve().url, defaultURL)
    }

    func testUnresolvableBookmarkFallsBackWithNoticeOnce() {
        defaults.set(Data("not a bookmark".utf8), forKey: ActiveLibrarySelection.bookmarkKey)
        let first = selection.resolve()
        XCTAssertEqual(first.url, defaultURL)
        XCTAssertNotNil(first.notice)
        XCTAssertNil(selection.resolve().notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultURL.path))
    }

    func testStaleBookmarkFallsBackWithNoticeOnceWithoutStartingAccess() {
        let chosenURL = directory.appendingPathComponent("Moved.kromoralibrary")
        defaults.set(Data("stale bookmark".utf8), forKey: ActiveLibrarySelection.bookmarkKey)
        var accessStartCount = 0

        let first = selection.resolve(
            bookmarkResolver: { _, isStale in
                isStale = true
                return chosenURL
            },
            accessStarter: { _ in
                accessStartCount += 1
                return nil
            }
        )

        XCTAssertEqual(first.url, defaultURL)
        XCTAssertNotNil(first.notice)
        XCTAssertEqual(accessStartCount, 0)
        XCTAssertFalse(selection.hasChoice)
        XCTAssertNil(selection.resolve().notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chosenURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultURL.path))
    }

    func testMissingChosenPackageFallsBackWithoutRecreatingIt() async throws {
        let url = try await makePackage("Gone.kromoralibrary")
        try selection.choose(url, access: access(url))
        try FileManager.default.removeItem(at: url)
        let resolution = selection.resolve()
        XCTAssertEqual(resolution.url, defaultURL)
        XCTAssertNotNil(resolution.notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLaunchOpensChosenLibraryFromSettings() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let settings = KromoraSettings(preferences: defaults)
        try ActiveLibrarySelection(preferences: defaults).choose(url, access: access(url))
        var opened: URL?
        let launch = AppLaunch(settings: settings, sheets: FakeSheets(), makeViewModel: { settings, packageURL in
            opened = packageURL
            return AppViewModel(
                engine: RenderEngine.shared, preferences: self.defaults, includeBundledLooks: false,
                portablePackageURL: packageURL, settings: settings,
                asynchronousPortableLibraryIndexLoading: true, defersLibraryOpen: true)
        })
        let model = launch.open()
        await launch.waitForLibraryOpen()
        XCTAssertEqual(opened?.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
        await model.shutdown()
    }

    // MARK: Chooser

    private final class StubDialog: FileDialogProviding {
        var folder: URL?
        func chooseFiles(title: String, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                         startingAt directoryURL: URL?) -> [URL]? { nil }
        func chooseFolder(title: String, prompt: String, startingAt directoryURL: URL?,
                          canCreateDirectories: Bool) -> URL? { folder }
    }

    private final class SpyRelauncher: AppRelaunching {
        var count = 0
        var error: (any Error)?
        /// Records what happened before the launch was requested.
        var events: EventLog?
        /// Runs at the moment the launch is requested.
        var onLaunch: (@MainActor () -> Void)?
        func relaunch() async throws {
            events?.append("launch")
            onLaunch?()
            count += 1
            if let error { throw error }
        }
    }

    private final class EventLog {
        private(set) var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }

    func testChooserPromptsRelaunchAfterValidChoice() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        let relauncher = SpyRelauncher()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher)
        await chooser.choose()
        XCTAssertEqual(sheets.lastConfirmButtons, ["Relaunch", "Later"])
        XCTAssertEqual(relauncher.count, 1)
        XCTAssertFalse(chooser.isUsingDefault)
        XCTAssertEqual(chooser.errorMessage, "")
    }

    func testChooserShowsOneErrorForInvalidFolderWithoutPrompting() async throws {
        let folder = directory.appendingPathComponent("Plain")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dialog = StubDialog(); dialog.folder = folder
        let sheets = FakeSheets()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: SpyRelauncher())
        await chooser.choose()
        XCTAssertFalse(chooser.errorMessage.isEmpty)
        XCTAssertEqual(sheets.confirmCalls, 0)
        XCTAssertTrue(chooser.isUsingDefault)
    }

    func testChooserLaterKeepsRunningAndUseDefaultClears() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = false
        let relauncher = SpyRelauncher()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher)
        await chooser.choose()
        XCTAssertEqual(relauncher.count, 0)
        await chooser.useDefault()
        XCTAssertTrue(chooser.isUsingDefault)
        XCTAssertFalse(selection.hasChoice)
    }

    func testRelaunchRequestsLaunchOnlyAfterLibraryReleased() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        let log = EventLog()
        let relauncher = SpyRelauncher(); relauncher.events = log
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: { log.append("release"); return .released })
        await chooser.choose()
        XCTAssertEqual(log.values, ["release", "launch"])
    }

    func testLaunchRequestFindsPackageLeaseReleased() async throws {
        let openURL = directory.appendingPathComponent("Open.kromoralibrary")
        let session = try PortableLibrarySession(at: openURL)
        let chosen = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = chosen
        let sheets = FakeSheets(); sheets.confirmResult = true
        var leaseHeldAtLaunch: Bool?
        let relauncher = SpyRelauncher()
        relauncher.onLaunch = {
            // A replacement process opening the old package must be able to take the writer lease.
            do {
                let next = try PortableLibrarySession(at: openURL)
                try next.lease.release()
                leaseHeldAtLaunch = false
            } catch {
                leaseHeldAtLaunch = true
            }
        }
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: {
                try? session.lease.release()
                return .released
            })
        await chooser.choose()
        XCTAssertEqual(relauncher.count, 1)
        XCTAssertEqual(leaseHeldAtLaunch, false)
    }

    func testReleaseWithoutSavingDoesNotLaunch() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        let relauncher = SpyRelauncher()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: { .releasedWithoutSaving })
        await chooser.choose()
        XCTAssertEqual(relauncher.count, 0)
        XCTAssertFalse(chooser.statusMessage.isEmpty)
        XCTAssertEqual(chooser.errorMessage, "")
    }

    func testFailedFlushQuitWithoutSavingDoesNotLaunch() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        var flushCount = 0
        var discarded = false
        var shutDown = false
        let releaseOutcome = await LibraryReleaseFlow.flushAndRelease(
            flush: {
                flushCount += 1
                return .failure("disk full")
            },
            chooseAfterFailure: { result in
                XCTAssertEqual(result, .failure("disk full"))
                return .discard
            },
            discard: { discarded = true },
            shutdown: { shutDown = true }
        )
        let relauncher = SpyRelauncher()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: { releaseOutcome })

        await chooser.choose()

        XCTAssertEqual(flushCount, 1)
        XCTAssertTrue(discarded)
        XCTAssertTrue(shutDown)
        XCTAssertEqual(releaseOutcome, .releasedWithoutSaving)
        XCTAssertEqual(relauncher.count, 0)
        XCTAssertTrue(chooser.statusMessage.contains("unsaved edits were discarded"))
    }

    func testDeclinedReleaseDoesNotLaunch() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        let relauncher = SpyRelauncher()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: { .declined })
        await chooser.choose()
        XCTAssertEqual(relauncher.count, 0)
        XCTAssertFalse(chooser.statusMessage.isEmpty)
    }

    func testFailedLaunchReportsErrorAfterRelease() async throws {
        struct LaunchFailure: LocalizedError { var errorDescription: String? { "no launch." } }
        let url = try await makePackage("Chosen.kromoralibrary")
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        let relauncher = SpyRelauncher(); relauncher.error = LaunchFailure()
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: { .released })
        await chooser.choose()
        XCTAssertTrue(chooser.errorMessage.contains("no launch."))
    }

    func testChoosingTheOpenLibrarySkipsRelaunch() async throws {
        let url = try await makePackage("Chosen.kromoralibrary")
        try selection.choose(url, access: .systemGranted(for: url))
        let dialog = StubDialog(); dialog.folder = url
        let sheets = FakeSheets(); sheets.confirmResult = true
        let relauncher = SpyRelauncher()
        var released = 0
        let chooser = ActiveLibraryChooser(
            selection: selection, fileDialog: dialog, sheets: sheets, relauncher: relauncher,
            releaseLibrary: { released += 1; return .released })
        await chooser.choose()
        XCTAssertEqual(sheets.confirmCalls, 0)
        XCTAssertEqual(relauncher.count, 0)
        XCTAssertEqual(released, 0)
        XCTAssertFalse(chooser.statusMessage.isEmpty)
    }
}
