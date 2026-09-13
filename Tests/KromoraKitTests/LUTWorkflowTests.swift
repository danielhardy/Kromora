import XCTest
@testable import KromoraKit

/// Cross-workflow LUT checks. The model tests prove the cube and intensity math; these exercise the
/// seams where a per-photo Look can otherwise be dropped: navigation, relaunch, copy/paste, and
/// the render request consumed by the preview/export coordinators.
@MainActor
final class LUTWorkflowTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeLUTFolder() throws -> (folder: URL, lut: CubeLUT) {
        let folder = tempDirectory.appendingPathComponent("looks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Workflow Look.cube", in: folder
        )
        return (folder, try CubeLUT(url: url))
    }

    private func makePhotoFolder() throws -> (URL, URL) {
        let folder = tempDirectory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = try Fixtures.writeGradientPNG(width: 24, height: 16, named: "one.png", in: folder)
        let second = try Fixtures.writeGradientPNG(width: 24, height: 16, named: "two.png", in: folder)
        return (first, second)
    }

    func testLookIsDiscoverableThroughOneAccessibleInspectorTab() {
        let availableTabs = AppViewModel.InspectorTab.availableTabs(
            hasImage: true,
            developPanelState: .noDevelopStage
        )

        XCTAssertEqual(
            availableTabs.filter { $0 == .look },
            [.look],
            "the inspector must expose exactly one Look entry point"
        )
        XCTAssertEqual(AppViewModel.InspectorTab.look.title, "Look")
        XCTAssertEqual(AppViewModel.InspectorTab.look.iconName, "wand.and.stars")
        XCTAssertEqual(AppViewModel.InspectorTab.look.purpose, "Browse and apply a Look")
    }

    func testLUTSurvivesNavigationAndRelaunchForItsPhoto() async throws {
        let (first, second) = try makePhotoFolder()
        let (lookFolder, lut) = try makeLUTFolder()
        let container = makeInMemoryEditContainer()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake, editStore: EditDocumentStore(modelContainer: container)
        )

        viewModel.library.setFolder(lookFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        viewModel.openImage(url: first)
        try await waitUntil("the first photo") { viewModel.sourceName == "one.png" }

        viewModel.selectLook(lut)
        viewModel.setLookIntensity(0.35)
        try await waitForLUTRequest(fake, id: lut.lutID, intensity: 0.35)

        viewModel.openImage(url: second)
        try await waitUntil("the second photo") { viewModel.sourceName == "two.png" }
        XCTAssertTrue(viewModel.document.lut.isIdentity)
        viewModel.openImage(url: first)
        try await waitUntil("the first photo again") {
            viewModel.sourceName == "one.png" && viewModel.document.lut.intensity == 0.35
        }
        XCTAssertEqual(viewModel.document.lut.lutID, lut.lutID)

        await viewModel.flushPendingWrites()
        let relaunched = makeAppViewModel(
            engine: FakeRenderEngine(), editStore: EditDocumentStore(modelContainer: container)
        )
        relaunched.library.setFolder(lookFolder)
        while relaunched.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        relaunched.openImage(url: first)
        try await waitUntil("the relaunched Look") {
            relaunched.sourceName == "one.png"
                && relaunched.document.lut.lutID == lut.lutID
                && relaunched.document.lut.intensity == 0.35
                && relaunched.selectedLook != nil
        }
    }

    func testLUTDoesNotCrossReferenceIdenticalReferencedPhotos() async throws {
        let (first, second) = try makePhotoFolder()
        let (lookFolder, lut) = try makeLUTFolder()
        let container = makeInMemoryEditContainer()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: EditDocumentStore(modelContainer: container)
        )

        viewModel.collection.loadFromFolder(first.deletingLastPathComponent())
        await viewModel.collection.scanCompletion()
        viewModel.library.setFolder(lookFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        viewModel.openImage(url: first)
        try await waitUntil("the first referenced photo") { viewModel.sourceName == "one.png" }
        viewModel.selectLook(lut)
        viewModel.setLookIntensity(0.35)
        try await waitForLUTRequest(fake, id: lut.lutID, intensity: 0.35)

        viewModel.openImage(url: second)
        try await waitUntil("the second referenced photo") { viewModel.sourceName == "two.png" }
        XCTAssertTrue(
            viewModel.document.lut.isIdentity,
            "a referenced photo with identical bytes inherited the first photo's Look"
        )

        await viewModel.flushPendingWrites()
        let relaunched = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container)
        )
        relaunched.collection.loadFromFolder(first.deletingLastPathComponent())
        await relaunched.collection.scanCompletion()
        relaunched.library.setFolder(lookFolder)
        while relaunched.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        relaunched.openImage(url: first)
        try await waitUntil("the persisted first referenced photo") {
            relaunched.sourceName == "one.png"
                && relaunched.document.lut.lutID == lut.lutID
                && relaunched.document.lut.intensity == 0.35
        }
        relaunched.openImage(url: second)
        try await waitUntil("the persisted second referenced photo") {
            relaunched.sourceName == "two.png"
        }
        XCTAssertTrue(
            relaunched.document.lut.isIdentity,
            "relaunch restored the first photo's Look onto the second photo"
        )
    }

    func testCanonicalLookStateDistinguishesMissingReferenceFromExplicitNone() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let source = try Fixtures.writeGradientPNG(
            width: 8, height: 8, named: "missing-look-source.png", in: tempDirectory
        )
        viewModel.openImage(url: source)
        try await waitUntil("the source image") { viewModel.sourceName == source.lastPathComponent }

        let missing = LUTID(raw: tempDirectory.appendingPathComponent("Moved Look.cube").path)
        viewModel.updateDocument {
            $0.lut.lutID = missing
            $0.lut.intensity = 0.42
        }

        XCTAssertEqual(viewModel.selectedLookID, missing)
        XCTAssertNil(viewModel.selectedLook, "an unresolved Look must not be mistaken for None")
        XCTAssertFalse(viewModel.isLookNoneSelected)
        XCTAssertEqual(viewModel.lookIntensity, 0.42)
        XCTAssertEqual(
            viewModel.lutResolutionStatus,
            "Look “Moved Look.cube” is unavailable; the stored reference was kept."
        )

        viewModel.selectLook(nil)
        XCTAssertNil(viewModel.selectedLookID)
        XCTAssertTrue(viewModel.isLookNoneSelected)
        XCTAssertEqual(viewModel.lookIntensity, 0.42, "clearing a Look keeps its chosen intensity")
    }

    func testCanonicalLookAuditionFollowsTheLibraryOrder() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let folder = tempDirectory.appendingPathComponent("audition-looks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let firstURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "01 First.cube", in: folder
        )
        let secondURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "02 Second.cube", in: folder
        )
        let first = try CubeLUT(url: firstURL)
        let second = try CubeLUT(url: secondURL)

        viewModel.library.setFolder(folder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        viewModel.selectLook(first)
        viewModel.selectNextLook()
        XCTAssertEqual(viewModel.selectedLookID, second.lutID)
        viewModel.selectPreviousLook()
        XCTAssertEqual(viewModel.selectedLookID, first.lutID)
        viewModel.selectPreviousLook()
        XCTAssertNil(viewModel.selectedLookID, "Up from the first Look must return to None")
        XCTAssertTrue(viewModel.isLookNoneSelected)
        viewModel.selectPreviousLook()
        XCTAssertNil(viewModel.selectedLookID, "Up from None is a no-op")
        viewModel.selectNextLook()
        XCTAssertEqual(viewModel.selectedLookID, first.lutID, "Down from None should select the first Look")
        viewModel.selectNextLook()
        viewModel.selectNextLook()
        XCTAssertEqual(viewModel.selectedLookID, second.lutID, "Down at the last Look is a no-op")
    }

    func testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 24, height: 16, named: "import-source.png", in: tempDirectory
        )
        let lookURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "External Look.cube", in: tempDirectory
        )
        let container = makeInMemoryEditContainer()
        let fake = FakeRenderEngine()
        let preferences = makeTestUserDefaults()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: EditDocumentStore(modelContainer: container),
            preferences: preferences
        )
        viewModel.openImage(url: source)
        try await waitUntil("the source image") { viewModel.sourceName == "import-source.png" }

        viewModel.importLook(from: lookURL)
        while viewModel.library.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        let imported = try XCTUnwrap(viewModel.library.allLUTs.first { $0.url == lookURL })

        // Import audition selects the new file automatically. Clear that selection, then invoke
        // the same ID-based action used by a browser row click. This catches a passive custom row
        // whose tag changes but never reaches AppViewModel.
        viewModel.setCanvasZoom(2)
        XCTAssertEqual(viewModel.canvasState.navigation.zoom, 2, "exercise the over-100% canvas path")
        // Import completion publishes the Look before the automatically auditioned preview has
        // necessarily reached the renderer. Establish that request first; otherwise the ID-click
        // waiter can mistake the delayed audition for the click's request after LUMO-308 added the
        // speculative opening preview.
        try await waitForLUTRequest(fake, id: imported.lutID, intensity: 1)
        let auditionedCount = await fake.previewRequests.count
        viewModel.selectLook(nil)
        // The clear's preview is submitted asynchronously through the coordinator/scheduler,
        // so the click baseline must be settled after that render lands. Reading the count
        // immediately races it, and the click's submit supersedes the clear's while Look-browser
        // candidates (thumbnail lane, hardcoded intensity 1) share the same recording seam —
        // under parallel load that churn can leave the click's waiter timing out against an
        // unsettled baseline (LUMO-321). A nil-LUT record is unambiguous here: candidates always
        // carry a concrete Look, and every earlier cleared-state render predates the audition.
        try await waitForNewLUTRequest(fake, after: auditionedCount, id: nil, intensity: 1)
        let requestsBeforeClick = await fake.previewRequests.count
        viewModel.selectLook(id: imported.lutID)

        XCTAssertEqual(viewModel.selectedLookID, imported.lutID)
        XCTAssertEqual(viewModel.selectedLook, imported)
        // The waiter's success is the assertion: it returns only after a new request carrying
        // the clicked Look reaches the engine. (A separate count comparison here proved nothing
        // beyond that — the log is append-only — and failed as a knock-on whenever this waiter
        // timed out.)
        try await waitForNewLUTRequest(
            fake, after: requestsBeforeClick, id: imported.lutID, intensity: 1
        )

        viewModel.setLookIntensity(0.35)
        await viewModel.flushPendingWrites()
        let relaunched = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container),
            preferences: preferences
        )
        while relaunched.library.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        relaunched.openImage(url: source)
        try await waitUntil("the persisted imported Look") {
            relaunched.sourceName == "import-source.png"
                && relaunched.selectedLookID == imported.lutID
                && relaunched.selectedLook != nil
                && relaunched.lookIntensity == 0.35
        }
    }

    func testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach() async throws {
        let (first, second) = try makePhotoFolder()
        let third = try Fixtures.writeGradientPNG(width: 24, height: 16, named: "three.png", in: first.deletingLastPathComponent())
        let (lookFolder, lut) = try makeLUTFolder()
        let container = makeInMemoryEditContainer()
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container)
        )
        viewModel.collection.loadFromFolder(first.deletingLastPathComponent())
        await viewModel.collection.scanCompletion()
        viewModel.library.setFolder(lookFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        guard let firstIndex = viewModel.collection.items.firstIndex(where: { $0.url == first }) else {
            return XCTFail("first photo was not scanned")
        }
        viewModel.selectCollectionImage(at: firstIndex)
        try await waitUntil("the source photo") { viewModel.sourceName == "one.png" }

        viewModel.selectLook(lut)
        viewModel.setLookIntensity(0.6)
        viewModel.copyAllEdits()
        guard let secondIndex = viewModel.collection.items.firstIndex(where: { $0.url == second }),
              let thirdIndex = viewModel.collection.items.firstIndex(where: { $0.url == third }) else {
            return XCTFail("destination photos were not scanned")
        }
        viewModel.collection.setSelection(at: secondIndex)
        viewModel.collection.setSelection(at: thirdIndex, additive: true)
        viewModel.pasteEdits()

        // The destinations have never been opened. Their queued records must still be present in a
        // fresh model, otherwise a quit immediately after multi-paste silently loses the Look.
        await viewModel.flushPendingWrites()
        let secondItem = try XCTUnwrap(
            viewModel.collection.items.first(where: { $0.url == second })
        )
        let persistedDestination = await viewModel.editStore.load(
            for: EditSourceReference(
                assetID: secondItem.id,
                url: secondItem.url
            )
        )
        XCTAssertEqual(
            persistedDestination.document.lut,
            LUTSettings(lutID: lut.lutID, intensity: 0.6),
            "pasted destination was not durable before relaunch"
        )
        let relaunched = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(modelContainer: container)
        )
        relaunched.collection.loadFromFolder(first.deletingLastPathComponent())
        await relaunched.collection.scanCompletion()
        relaunched.library.setFolder(lookFolder)
        while relaunched.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        relaunched.openImage(url: second)
        let relaunchedDeadline = Date().addingTimeInterval(5)
        while Date() < relaunchedDeadline
            && !(relaunched.sourceName == "two.png"
                && relaunched.document.lut.lutID == lut.lutID
                && relaunched.document.lut.intensity == 0.6) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(
            relaunched.sourceName == "two.png"
                && relaunched.document.lut.lutID == lut.lutID
                && relaunched.document.lut.intensity == 0.6,
            "persisted pasted Look did not become active: source=\(relaunched.sourceName), "
                + "asset=\(relaunched.collection.selectedItem?.id.raw ?? "nil"), "
                + "look=\(relaunched.document.lut.lutID?.raw ?? "nil"), "
                + "intensity=\(relaunched.document.lut.intensity), "
                + "storeStatus=\(relaunched.editStoreStatus ?? "nil")"
        )

        for url in [second, third] {
            let name = url.lastPathComponent
            viewModel.openImage(url: url)
            try await waitUntil("\(name) after paste") { viewModel.sourceName == name }
            XCTAssertEqual(viewModel.document.lut.lutID, lut.lutID)
            XCTAssertEqual(viewModel.document.lut.intensity, 0.6)
            XCTAssertEqual(viewModel.undoDepth, 1)
            viewModel.undo()
            XCTAssertTrue(viewModel.document.lut.isIdentity)
        }

        viewModel.openImage(url: first)
        try await waitUntil("the unchanged source") { viewModel.sourceName == "one.png" }
        XCTAssertEqual(viewModel.document.lut.lutID, lut.lutID)
        XCTAssertEqual(viewModel.document.lut.intensity, 0.6)
    }

    private func waitForLUTRequest(
        _ fake: FakeRenderEngine, id: LUTID?, intensity: Double
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let requests = await fake.previewRequests
            if requests.contains(where: {
                $0.document.lut.lutID == id && $0.document.lut.intensity == intensity
            }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for a preview request carrying the LUT")
    }

    private func waitForNewLUTRequest(
        _ fake: FakeRenderEngine, after count: Int, id: LUTID?, intensity: Double
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let requests = await fake.previewRequests
            if requests.count > count,
               requests.dropFirst(count).contains(where: {
                   $0.document.lut.lutID == id && $0.document.lut.intensity == intensity
               }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for a new preview request carrying the LUT")
    }
}
