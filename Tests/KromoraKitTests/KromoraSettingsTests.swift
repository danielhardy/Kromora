import XCTest
@testable import KromoraKit

@MainActor
final class KromoraSettingsTests: TempDirectoryTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "KromoraSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAppearancePersistsAndUnrelatedSettingsSurvive() {
        let defaults = makeDefaults()
        defaults.set(["Info", "Look"], forKey: "kromora.inspector.tabs")
        let first = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertFalse(first.alwaysDarkMode)
        first.alwaysDarkMode = true

        let relaunched = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertTrue(relaunched.alwaysDarkMode)
        XCTAssertEqual(defaults.stringArray(forKey: "kromora.inspector.tabs"), ["Info", "Look"])
        XCTAssertEqual(defaults.integer(forKey: "Kromora.settings.schemaVersion"), 1)
    }

    func testPhotoNameVisibilityPersistsAcrossRelaunch() {
        let defaults = makeDefaults()
        let first = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertFalse(first.showPhotoNames)
        first.showPhotoNames = true

        let relaunched = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertTrue(relaunched.showPhotoNames)
    }

    func testLastCopyCategoriesPersistAcrossRelaunch() {
        let defaults = makeDefaults()
        let first = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertEqual(first.lastCopyCategories, Set(EditClipboardPayload.Category.allCases))
        first.lastCopyCategories = [.light, .color, .crop]

        let relaunched = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertEqual(relaunched.lastCopyCategories, [.light, .color, .crop])
    }

    func testSourceAndExportFoldersPersistIndependentlyAndReset() throws {
        let defaults = makeDefaults()
        let source = tempDirectory.appendingPathComponent("Imports")
        let export = tempDirectory.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let settings = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertTrue(settings.setDefaultFolder(source, for: .source))
        XCTAssertTrue(settings.setDefaultFolder(export, for: .export))
        XCTAssertEqual(settings.sourceFolderStatus.availability, .available)
        XCTAssertEqual(settings.exportFolderStatus.availability, .available)
        XCTAssertEqual(settings.defaultSourceFolderURL?.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(settings.testDefaultFolder(.export).status.availability, .available)

        let relaunched = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertEqual(relaunched.defaultSourceFolderURL?.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(relaunched.defaultExportFolderURL?.standardizedFileURL, export.standardizedFileURL)

        relaunched.resetDefaultFolder(.source)
        XCTAssertNil(relaunched.defaultSourceFolderURL)
        XCTAssertEqual(relaunched.exportFolderStatus.availability, .available)
    }

    func testUnavailableFolderKeepsConfiguredPreferenceAndReportsRecovery() throws {
        let defaults = makeDefaults()
        let folder = tempDirectory.appendingPathComponent("Disconnected")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertTrue(settings.setDefaultFolder(folder, for: .source))

        try FileManager.default.removeItem(at: folder)
        settings.refreshFolderStatus()

        XCTAssertEqual(settings.sourceFolderStatus.availability, .unavailable)
        XCTAssertEqual(settings.sourceFolderStatus.displayName, "Disconnected")
        XCTAssertTrue(settings.testDefaultFolder(.source).message.contains("Choose it again"))

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(settings.setDefaultFolder(folder, for: .source))
        XCTAssertEqual(settings.sourceFolderStatus.availability, .available)
    }

    func testMigrationSeedsSourceDefaultWithoutReplacingWorkflowOrLookSettings() throws {
        let defaults = makeDefaults()
        let currentSource = tempDirectory.appendingPathComponent("Current Source")
        try FileManager.default.createDirectory(at: currentSource, withIntermediateDirectories: true)
        let bookmark = try currentSource.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        defaults.set(bookmark, forKey: "imageSourceFolderBookmark")
        defaults.set(Data("existing-look-bookmark".utf8), forKey: "lutFolderBookmark")
        defaults.set(true, forKey: "kromora.inspector.isPresented")

        let settings = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertEqual(settings.defaultSourceFolderURL?.standardizedFileURL, currentSource.standardizedFileURL)
        XCTAssertEqual(defaults.data(forKey: "lutFolderBookmark"), Data("existing-look-bookmark".utf8))
        XCTAssertEqual(defaults.bool(forKey: "kromora.inspector.isPresented"), true)
        XCTAssertEqual(defaults.integer(forKey: "Kromora.settings.schemaVersion"), 1)
    }

    func testCanonicalUserLookFolderIsAppOwnedAndCreated() {
        let canonical = tempDirectory.appendingPathComponent("User Looks")
        let settings = KromoraSettings(
            preferences: makeDefaults(), userLookFolderURL: canonical
        )

        XCTAssertEqual(settings.ensureUserLookFolder(), canonical)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
        XCTAssertNil(settings.sourceFolderStatus.url)
    }

    func testCleanProfileUsesVisiblePicturesDestinations() {
        let settings = KromoraSettings(preferences: makeDefaults())

        XCTAssertEqual(settings.userLookFolderURL, KromoraStorage.defaultUserLookDirectory())
        XCTAssertEqual(settings.defaultExportFolderURL, KromoraStorage.defaultExportDirectory())
        XCTAssertTrue(settings.userLookFolderURL.path.contains("Pictures/"))
        XCTAssertTrue(settings.defaultExportDestinationURL.path.contains("Pictures/"))
        XCTAssertFalse(settings.userLookFolderURL.path.contains("Application Support"))
        XCTAssertFalse(settings.defaultExportDestinationURL.path.contains("Application Support"))
    }

    func testEditDatabaseURLIsRevealableOnlyAfterStoreFileExists() throws {
        let storeURL = tempDirectory.appendingPathComponent("EditStore.store")

        XCTAssertNil(KromoraSettingsView.revealableEditDatabaseURL(for: storeURL))
        XCTAssertNil(KromoraSettingsView.revealableEditDatabaseURL(for: nil))

        try Data().write(to: storeURL)
        XCTAssertEqual(
            KromoraSettingsView.revealableEditDatabaseURL(for: storeURL),
            storeURL
        )
    }

    func testStorageAdoptsLegacyApplicationSupportDirectory() throws {
        let support = tempDirectory.appendingPathComponent("Application Support")
        let legacy = support.appendingPathComponent("Lumo", isDirectory: true)
        let marker = legacy.appendingPathComponent("EditStore.store")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: marker)

        let current = KromoraStorage.root(in: support)

        XCTAssertEqual(current.lastPathComponent, "Kromora")
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("EditStore.store").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testLegacySettingsAreCopiedIntoKromoraNamespace() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "Lumo.settings.alwaysDarkMode")
        defaults.set(false, forKey: "Lumo.settings.showPhotoNames")

        let settings = KromoraSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertTrue(settings.alwaysDarkMode)
        XCTAssertFalse(settings.showPhotoNames)
        XCTAssertTrue(defaults.bool(forKey: "Kromora.settings.alwaysDarkMode"))
        XCTAssertFalse(defaults.bool(forKey: "Kromora.settings.showPhotoNames"))
    }
}
