import XCTest
@testable import KromoraKit

final class MediaVolumeSelectionTests: XCTestCase {
    func testSelectionSupportsAllNoneAndToggle() {
        let files = (0..<3).map {
            MediaVolumeFile(url: URL(fileURLWithPath: "/fixture/shot\($0).jpg"))
        }
        var selection = MediaVolumeSelectionModel()

        selection.selectAll(in: files)
        XCTAssertEqual(selection.count, 3)
        selection.toggle(files[1])
        XCTAssertEqual(selection.count, 2)
        XCTAssertFalse(selection.contains(files[1]))
        selection.clear()
        XCTAssertEqual(selection.count, 0)
    }

    func testShiftRangeSelectsEverythingBetweenAnchorAndClickInEitherDirection() {
        let files = (0..<6).map {
            MediaVolumeFile(url: URL(fileURLWithPath: "/fixture/shot\($0).jpg"))
        }
        var selection = MediaVolumeSelectionModel()

        selection.toggle(files[1])
        selection.selectRange(to: files[3], in: files)
        XCTAssertEqual(selection.selectedIDs, Set(files[1...3].map(\.id)))

        selection.selectRange(to: files[0], in: files)
        XCTAssertEqual(selection.selectedIDs, Set(files[0...3].map(\.id)))
    }

    func testShiftRangeWithoutAnchorActsLikePlainClick() {
        let files = (0..<3).map {
            MediaVolumeFile(url: URL(fileURLWithPath: "/fixture/shot\($0).jpg"))
        }
        var selection = MediaVolumeSelectionModel()
        selection.selectRange(to: files[2], in: files)
        XCTAssertEqual(selection.selectedIDs, [files[2].id])
    }

    func testDayGroupsSplitByCalendarDayAndKeepUndatedLast() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 9))!
        let day1Late = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 18))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 8))!
        let files = [
            MediaVolumeFile(url: URL(fileURLWithPath: "/f/a.jpg"), captureDate: day1),
            MediaVolumeFile(url: URL(fileURLWithPath: "/f/b.jpg"), captureDate: day1Late),
            MediaVolumeFile(url: URL(fileURLWithPath: "/f/c.jpg"), captureDate: day2),
            MediaVolumeFile(url: URL(fileURLWithPath: "/f/d.jpg")),
        ]
        let groups = MediaVolumeDayGroup.groups(for: files, calendar: calendar)
        XCTAssertEqual(groups.map(\.files.count), [2, 1, 1])
        XCTAssertNil(groups.last?.day)
    }
}

final class MediaVolumeStreamingModelTests: XCTestCase {
    private func file(_ name: String, at seconds: TimeInterval?) -> MediaVolumeFile {
        MediaVolumeFile(
            url: URL(fileURLWithPath: "/Volumes/Card/\(name)"),
            captureDate: seconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    func testMergingKeepsDisplayOrderAcrossBatchesAndSkipsKnownFiles() {
        let a = file("a.jpg", at: 100), b = file("b.jpg", at: 200)
        let c = file("c.jpg", at: 300), undated = file("z.jpg", at: nil)
        var list = MediaVolumeFile.merging([], [c, undated])
        list = MediaVolumeFile.merging(list, [a, c])
        list = MediaVolumeFile.merging(list, [b])

        XCTAssertEqual(list.map(\.filename), ["a.jpg", "b.jpg", "c.jpg", "z.jpg"])
        XCTAssertEqual(list, [c, undated, a, b].sorted(by: MediaVolumeFile.displayOrder))
    }

    func testSelectingArrivalsKeepsEarlierChoicesAndAnchor() {
        let a = file("a.jpg", at: 1), b = file("b.jpg", at: 2), c = file("c.jpg", at: 3)
        var selection = MediaVolumeSelectionModel()
        selection.select([a, b])
        selection.toggle(b)
        selection.select([c])

        XCTAssertTrue(selection.contains(a))
        XCTAssertFalse(selection.contains(b))
        XCTAssertTrue(selection.contains(c))
        XCTAssertEqual(selection.anchorID, b.id)
    }
}

@MainActor
final class MediaVolumeImportTests: TempDirectoryTestCase {
    func testMountedScannerAdmitsSupportedImagesWithOrientationAndWarnings() async throws {
        let good = try Fixtures.writeJPEG(
            width: 80, height: 40, orientation: 6, named: "portrait.jpg", in: tempDirectory
        )
        try Data("not an image".utf8).write(to: tempDirectory.appendingPathComponent("broken.jpg"))
        try Data("ignore".utf8).write(to: tempDirectory.appendingPathComponent("notes.txt"))

        let volume = MediaVolume(name: "Fixture Card", url: tempDirectory)
        let result = try await MountedMediaVolumeProvider().scan(volume)

        XCTAssertEqual(result.files.map(\.filename), ["portrait.jpg"])
        XCTAssertEqual(result.files.first?.orientation, 6)
        XCTAssertTrue(result.warnings.contains { $0.contains("broken.jpg") })
        XCTAssertFalse(result.files.contains { $0.filename == "notes.txt" })
        XCTAssertEqual(try Data(contentsOf: good), try Data(contentsOf: good), "source is untouched")
    }

    func testMountedScannerStreamsBatchesThatMergeToTheFullyScannedResult() async throws {
        let count = MountedMediaVolumeProvider.scanBatchFileLimit * 2 + 5
        for index in 0..<count {
            _ = try Fixtures.writeJPEG(
                width: 16, height: 8, orientation: 1,
                named: String(format: "img-%03d.jpg", index), in: tempDirectory
            )
        }
        try Data("not an image".utf8).write(to: tempDirectory.appendingPathComponent("broken.jpg"))
        let volume = MediaVolume(name: "Streamed Card", url: tempDirectory)
        let provider = MountedMediaVolumeProvider()

        var batches: [MediaVolumeScanBatch] = []
        var merged: [MediaVolumeFile] = []
        var warnings: [String] = []
        for try await batch in provider.scanBatches(volume, access: nil) {
            batches.append(batch)
            merged = MediaVolumeFile.merging(merged, batch.files)
            warnings += batch.warnings
        }
        let full = try await provider.scan(volume)

        XCTAssertGreaterThan(batches.count, 1, "a large card arrives in more than one batch")
        XCTAssertTrue(batches.allSatisfy { $0.files.count <= MountedMediaVolumeProvider.scanBatchFileLimit })
        XCTAssertEqual(merged, full.files, "streamed order matches the fully scanned order")
        XCTAssertEqual(Set(warnings), Set(full.warnings))
    }

    func testMountedScannerBatchStreamThrowsTheScanError() async throws {
        let gone = tempDirectory.appendingPathComponent("not-mounted")
        let volume = MediaVolume(name: "Gone", url: gone)
        do {
            for try await _ in MountedMediaVolumeProvider().scanBatches(volume, access: nil) {}
            XCTFail("expected volumeRemoved")
        } catch {
            XCTAssertEqual(error as? MediaVolumeError, .volumeRemoved("Gone"))
        }
    }

    func testMountedScannerResolvesAUserGrantedBookmarkBeforeScanning() async throws {
        let imageURL = try Fixtures.writeJPEG(
            width: 24, height: 12, orientation: 1, named: "granted.jpg", in: tempDirectory
        )
        let bookmark = try tempDirectory.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        let inaccessibleRawURL = tempDirectory.appendingPathComponent("raw-mount-no-longer-valid")
        let volume = MediaVolume(
            name: "Granted Card", url: inaccessibleRawURL, bookmarkData: bookmark
        )

        let result = try await MountedMediaVolumeProvider().scan(volume)

        XCTAssertEqual(result.files.map(\.url), [imageURL.standardizedFileURL])
    }

    func testInjectedProviderCoversDiscoveryScanAndFailureState() async throws {
        let imageURL = try Fixtures.writeJPEG(
            width: 32, height: 16, orientation: 1, named: "shot.jpg", in: tempDirectory
        )
        let volume = MediaVolume(name: "Camera Card", url: tempDirectory)
        let file = MediaVolumeFile(url: imageURL, orientation: 1)
        let provider = FixtureMediaVolumeProvider(
            volumes: [volume], result: .success(MediaVolumeScanResult(files: [file], warnings: []))
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine(), mediaVolumeProvider: provider)

        viewModel.refreshRemovableMedia()
        try await waitUntil { viewModel.removableMediaVolumes == [volume] }
        XCTAssertEqual(viewModel.removableMediaVolumes.map(\.name), ["Camera Card"])

        viewModel.openRemovableMedia(volume)
        try await waitUntil { !viewModel.isRemovableMediaScanning }
        XCTAssertEqual(viewModel.removableMediaFiles, [file])
        XCTAssertEqual(viewModel.removableMediaSelection.count, 1)

        let failing = FixtureMediaVolumeProvider(
            volumes: [volume], result: .failure(.volumeRemoved("Camera Card"))
        )
        let failingViewModel = makeAppViewModel(
            engine: FakeRenderEngine(), mediaVolumeProvider: failing,
            portablePackageURL: tempDirectory.appendingPathComponent(
                "Failure Test Library.kromoralibrary", isDirectory: true
            )
        )
        failingViewModel.openRemovableMedia(volume)
        try await waitUntil { !failingViewModel.isRemovableMediaScanning }
        XCTAssertTrue(failingViewModel.removableMediaWarnings.contains("Camera Card is no longer available."))
    }

    func testInjectedProviderLabelsVolumesNeedingAccessWithoutHidingThem() async throws {
        let pending = MediaVolume(
            name: "Blank Card", url: tempDirectory, requiresAccessGrant: true
        )
        let readable = MediaVolume(name: "Camera Card", url: tempDirectory)
        let provider = FixtureMediaVolumeProvider(
            volumes: [pending, readable],
            result: .success(MediaVolumeScanResult(files: [], warnings: []))
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine(), mediaVolumeProvider: provider)

        viewModel.refreshRemovableMedia()
        try await waitUntil { viewModel.removableMediaVolumes == [pending, readable] }

        XCTAssertEqual(viewModel.removableMediaVolumes.map(\.menuLabel), [
            "Blank Card — Access needed", "Camera Card"
        ])
        XCTAssertEqual(viewModel.removableMediaVolumes.first?.accessHint,
                       "Access needed — open to check for photos.")
    }

    func testMountedVolumeNotificationRefreshesMediaAfterInitialDiscovery() async throws {
        let volume = MediaVolume(name: "New Card", url: tempDirectory)
        let notificationCenter = NotificationCenter()
        let provider = MutableMediaVolumeProvider()
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            mediaVolumeProvider: provider,
            mediaVolumeNotificationCenter: notificationCenter,
            applicationNotificationCenter: notificationCenter
        )

        viewModel.refreshRemovableMedia()
        try await waitUntil { viewModel.removableMediaVolumes.isEmpty }

        await provider.setVolumes([volume])
        notificationCenter.post(name: NSWorkspace.didMountNotification, object: volume.url)

        try await waitUntil { viewModel.removableMediaVolumes == [volume] }
    }

    func testEmptyScanKeepsARecoverableEmptyStateAndCancelClosesIt() async throws {
        let volume = MediaVolume(name: "Empty Card", url: tempDirectory)
        let provider = FixtureMediaVolumeProvider(
            volumes: [volume], result: .success(MediaVolumeScanResult(files: [], warnings: []))
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine(), mediaVolumeProvider: provider)

        viewModel.openRemovableMedia(volume)
        try await waitUntil { !viewModel.isRemovableMediaScanning }
        XCTAssertTrue(viewModel.removableMediaFiles.isEmpty)
        XCTAssertTrue(viewModel.removableMediaWarnings.contains("No supported images were found on this volume."))
        viewModel.cancelRemovableMediaImport()
        XCTAssertFalse(viewModel.isRemovableMediaSelectorPresented)
    }

    func testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource() async throws {
        let url = try Fixtures.writeJPEG(
            width: 64, height: 32, orientation: 6, named: "DSC0001.JPG", in: tempDirectory
        )
        let original = try Data(contentsOf: url)
        let file = MediaVolumeFile(url: url, filename: "DSC0001.JPG", orientation: 6)
        let volume = MediaVolume(name: "Card", url: tempDirectory)
        let libraryFolder = tempDirectory.appendingPathComponent(
            "managed-library", isDirectory: true
        )
        let collection = makeTestCollection(libraryFolderURL: libraryFolder)

        let ids = collection.addFromMediaVolume(volume, files: [file])
        XCTAssertEqual(ids.count, 1)
        let imported = try XCTUnwrap(collection.items.first)
        let managedURL = try XCTUnwrap(imported.url)
        XCTAssertEqual(imported.url?.deletingLastPathComponent().standardizedFileURL,
                       libraryFolder.standardizedFileURL)
        XCTAssertEqual(imported.displayName, "DSC0001")
        XCTAssertEqual(imported.asset.id, imported.url.map(PhotoAssetID.file))
        XCTAssertEqual(imported.asset.metadata.dimensions,
                       PhotoPixelDimensions(width: 32, height: 64))
        XCTAssertEqual(try Data(contentsOf: url), original)

        // The source card can be ejected as soon as the synchronous copy returns. The managed
        // asset must remain usable without the source file or its security scope.
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try Data(contentsOf: managedURL), original)
        XCTAssertFalse(collection.hasActiveSourceFolderScopeForTesting)
    }

    func testFailedMediaVolumeImportDoesNotRetainACollectionScope() throws {
        let missingURL = tempDirectory.appendingPathComponent("missing.jpg")
        let volume = MediaVolume(name: "Removed Card", url: tempDirectory)
        let file = MediaVolumeFile(url: missingURL, filename: "missing.jpg")
        let collection = makeTestCollection()

        XCTAssertTrue(collection.addFromMediaVolume(volume, files: [file]).isEmpty)
        XCTAssertFalse(collection.hasActiveSourceFolderScopeForTesting)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("condition did not become true"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct FixtureMediaVolumeProvider: MediaVolumeProviding {
    let volumes: [MediaVolume]
    let result: Result<MediaVolumeScanResult, MediaVolumeError>

    func discover() async -> [MediaVolume] { volumes }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        try result.get()
    }
}

private actor MutableMediaVolumeProvider: MediaVolumeProviding {
    private var volumes: [MediaVolume] = []

    func setVolumes(_ volumes: [MediaVolume]) {
        self.volumes = volumes
    }

    func discover() async -> [MediaVolume] {
        volumes
    }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        MediaVolumeScanResult(files: [], warnings: [])
    }
}
