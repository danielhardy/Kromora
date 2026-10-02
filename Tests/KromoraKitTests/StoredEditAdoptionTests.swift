import XCTest

@testable import KromoraKit

/// KRMA-755: the Edit panel binds to `AppViewModel.document`. The stored edit document is a small
/// read that starts at selection, so it must reach the panel as soon as it is read, not after the
/// (slow) source preparation that the pixels no longer wait on.
@MainActor
final class StoredEditAdoptionTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Imports photos, gives each a stored exposure edit, and returns the package URL so a second
    /// view model can reopen it the way a relaunch would.
    private func makePackage(storedExposures: [String: Double]) async throws -> URL {
        let names = storedExposures.keys.sorted()
        let photos = try names.map {
            try Fixtures.writeGradientPNG(width: 16, height: 12, named: $0, in: tempDirectory)
        }
        let packageURL = tempDirectory.appendingPathComponent("StoredEdit.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL)
        _ = try session.importURLs(photos, duplicatePolicy: .importAnyway)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL,
            portableLibrarySession: session
        )
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        for name in names {
            let index = try XCTUnwrap(
                viewModel.collection.items.firstIndex { $0.displayName == name })
            viewModel.collection.setSelection(at: index)
            viewModel.openActiveCollectionImage()
            try await waitUntil("\(name) to open") {
                viewModel.sourceName == name && viewModel.previewState == .ready
            }
            viewModel.updateDocument { $0.light.exposure = storedExposures[name] ?? 0 }
        }
        let flushed = await viewModel.flushPendingWrites()
        XCTAssertEqual(flushed, .success)
        await viewModel.shutdown()
        return packageURL
    }

    /// Reopens the package with source preparation held open.
    private func reopen(
        _ packageURL: URL, freshFrameStore: Bool = false
    ) async throws -> (AppViewModel, FakeRenderEngine, PortableLibrarySession) {
        let session = try PortableLibrarySession(at: packageURL)
        let fake = FakeRenderEngine()
        await fake.gateSourcePreparation()
        let viewModel = makeAppViewModel(
            engine: fake,
            previewFrameStoreDirectory: freshFrameStore
                ? tempDirectory.appendingPathComponent("empty-frames", isDirectory: true) : nil,
            portablePackageURL: packageURL, portableLibrarySession: session
        )
        // A failing assertion must not leave the gated preparation suspended, or the run never exits.
        addTeardownBlock {
            await fake.releaseSourcePreparation()
            await viewModel.shutdown()
        }
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        return (viewModel, fake, session)
    }

    private func select(_ name: String, in viewModel: AppViewModel) throws {
        let index = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.displayName == name })
        viewModel.collection.setSelection(at: index)
        viewModel.openActiveCollectionImage()
    }

    private func waitForPreparationToStart(_ fake: FakeRenderEngine) async throws {
        let deadline = Date().addingTimeInterval(5)
        while await fake.sourcePreparationCount == 0 {
            XCTAssertLessThan(Date(), deadline, "source preparation did not start")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testStoredEditsReachThePanelWhileSourcePreparationIsStillPending() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        let (viewModel, fake, _) = try await reopen(packageURL)
        try select("one.png", in: viewModel)
        try await waitForPreparationToStart(fake)

        // Source preparation is held open. The stored document must still reach the panel.
        try await waitUntil("the stored exposure to reach the panel") {
            viewModel.document.light.exposure == 1.5
        }
        XCTAssertEqual(viewModel.previewState, .loading, "the source must still be preparing")

        await fake.releaseSourcePreparation()
        try await waitUntil("the photo to settle") { viewModel.previewState == .ready }
        XCTAssertEqual(viewModel.document.light.exposure, 1.5)
    }

    func testTheFirstRenderUsesTheStoredDocumentSoNoCorrectiveRenderFollows() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        // The first session stored an exact frame, which would skip the render this test inspects,
        // so reopen with an empty frame store.
        let (viewModel, fake, _) = try await reopen(packageURL, freshFrameStore: true)
        try select("one.png", in: viewModel)
        try await waitForPreparationToStart(fake)
        try await waitUntil("the stored exposure to reach the panel") {
            viewModel.document.light.exposure == 1.5
        }

        await fake.releaseSourcePreparation()
        try await waitUntil("the photo to settle") { viewModel.previewState == .ready }

        // The canvas reaches the engine through whichever seam the surface uses; look at all of them.
        let rendered =
            await fake.previewRequests.map(\.document.light.exposure)
            + fake.textureRequests.map(\.document.light.exposure)
            + fake.renderRequests.map(\.document.light.exposure)
        XCTAssertFalse(rendered.isEmpty, "a canvas render must have run")
        XCTAssertEqual(
            Set(rendered), [1.5],
            "no canvas render may use the identity document when the stored one was known first"
        )
    }

    func testASupersededSelectionNeverPublishesTheOldPhotosStoredValues() async throws {
        let packageURL = try await makePackage(
            storedExposures: ["one.png": 1.5, "two.png": -0.5])
        let (viewModel, fake, _) = try await reopen(packageURL)
        try select("one.png", in: viewModel)
        // B supersedes A before A's source preparation ever finishes.
        try select("two.png", in: viewModel)
        try await waitForPreparationToStart(fake)

        try await waitUntil("the second photo's stored exposure") {
            viewModel.document.light.exposure == -0.5
        }
        // Give a stale publication every chance to land, then require B's values to stay.
        for _ in 0..<30 {
            XCTAssertEqual(viewModel.document.light.exposure, -0.5)
            try await Task.sleep(for: .milliseconds(10))
        }
        await fake.releaseSourcePreparation()
        try await waitUntil("the second photo to settle") { viewModel.previewState == .ready }
        XCTAssertEqual(viewModel.sourceName, "two.png")
        XCTAssertEqual(viewModel.document.light.exposure, -0.5)
    }

    func testPhotoSwitchMarksSliderPresentationPendingUntilIncomingDocumentArrives() async throws {
        let packageURL = try await makePackage(
            storedExposures: ["one.png": 1.5, "two.png": -0.5])
        let (viewModel, fake, _) = try await reopen(packageURL)
        try select("one.png", in: viewModel)
        try await waitForPreparationToStart(fake)
        try await waitUntil("the first photo's stored exposure") {
            viewModel.document.light.exposure == 1.5
        }
        await fake.releaseSourcePreparation()
        try await waitUntil("the first photo to settle") { viewModel.previewState == .ready }

        try select("two.png", in: viewModel)
        XCTAssertTrue(viewModel.isInspectorSourceDocumentPending)
        try await waitUntil("the second photo's stored exposure") {
            viewModel.document.light.exposure == -0.5
                && !viewModel.isInspectorSourceDocumentPending
        }
    }
}
