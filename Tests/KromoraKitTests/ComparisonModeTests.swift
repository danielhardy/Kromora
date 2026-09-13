import XCTest
@testable import KromoraKit

/// Comparison presentation is a user preference, not part of a photo's edit document. These tests
/// keep the first-launch, photo-switch, and relaunch contracts together so a new default cannot be
/// accidentally hidden by the existing per-photo persistence tests.
@MainActor
final class ComparisonModeTests: TempDirectoryTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "KromoraComparisonModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
    }

    private func waitUntil(
        _ description: String,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            if Date() > deadline {
                return XCTFail("timed out waiting for \(description)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testFirstLaunchDefaultsToSinglePhoto() {
        let viewModel = makeViewModel(defaults: makeDefaults())

        XCTAssertFalse(viewModel.isSideBySide)
        XCTAssertFalse(viewModel.isSideBySideVisible)
    }

    func testSelectedModeIsRememberedAcrossRelaunch() {
        let defaults = makeDefaults()
        let firstLaunch = makeViewModel(defaults: defaults)
        firstLaunch.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }

        XCTAssertTrue(firstLaunch.toggleSideBySide())
        XCTAssertTrue(firstLaunch.isSideBySide)

        let relaunched = makeViewModel(defaults: defaults)
        XCTAssertTrue(relaunched.isSideBySide)
    }

    func testSelectedModeSurvivesPhotoSwitch() async throws {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )

        viewModel.openImage(url: first)
        try await waitUntil("the first photo") { viewModel.sourceName == first.lastPathComponent }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.isSideBySideVisible)

        viewModel.openImage(url: second)
        try await waitUntil("the second photo") { viewModel.sourceName == second.lastPathComponent }

        XCTAssertTrue(viewModel.isSideBySide)
        XCTAssertTrue(viewModel.isSideBySideVisible,
                      "a retained side-by-side preference must remain visible for an identity photo")
        XCTAssertTrue(viewModel.isComparisonPresentationAvailable)
        XCTAssertFalse(viewModel.isShowingOriginal, "Space comparison must not leak across photos")
    }

    func testUneditedPhotoPopulatesBothSurfacesWithNoEditRecord() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        enableSideBySide(on: viewModel)
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "no-record.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitForBothSurfaces(viewModel, fake: fake, image: image)

        try await assertIdentityComparison(viewModel, fake: fake, image: image)
    }

    func testUneditedPhotoPopulatesBothSurfacesWithAnEmptyPersistedDocument() async throws {
        let defaults = makeDefaults()
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "empty-record.png", in: tempDirectory
        )
        let container = makeInMemoryEditContainer()
        let store = EditDocumentStore(modelContainer: container)
        try await store.save(
            EditDocument(),
            for: EditSourceReference(assetID: .file(image), url: image)
        )

        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: EditDocumentStore(modelContainer: container),
            preferences: defaults
        )
        enableSideBySide(on: viewModel)
        viewModel.openImage(url: image)

        try await waitForBothSurfaces(viewModel, fake: fake, image: image)
        try await assertIdentityComparison(viewModel, fake: fake, image: image)
    }

    func testResetPhotoKeepsRetainedSideBySideSurfacesValid() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        enableSideBySide(on: viewModel)
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "reset.png", in: tempDirectory
        )
        viewModel.openImage(url: image)
        try await waitForBothSurfaces(viewModel, fake: fake, image: image)

        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the edited comparison") {
            viewModel.originalPreviewSurface.image != nil
                && viewModel.document.hasVisibleLookEdits
        }
        viewModel.resetPhoto()
        try await waitUntil("the reset comparison") {
            viewModel.document.isIdentity
                && viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }

        XCTAssertTrue(viewModel.isSideBySide)
        XCTAssertTrue(viewModel.toggleSideBySide(), "the retained comparison must be dismissible")
        XCTAssertFalse(viewModel.isSideBySide)
    }

    func testSpaceIsSingleViewOnly() {
        let viewModel = makeViewModel(defaults: makeDefaults())
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        XCTAssertTrue(viewModel.toggleSideBySide())

        XCTAssertFalse(viewModel.showOriginal(true))
        XCTAssertFalse(viewModel.isShowingOriginal)
    }

    func testUndoToIdentityClearsTransientOriginal() {
        let viewModel = makeViewModel(defaults: makeDefaults())
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        XCTAssertTrue(viewModel.showOriginal(true))
        XCTAssertTrue(viewModel.isShowingOriginal)

        viewModel.undo()

        XCTAssertTrue(viewModel.document.isIdentity)
        XCTAssertFalse(viewModel.isShowingOriginal)
    }

    func testEnteringSideBySideAfterSettledPreviewRequestsAndPublishesBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "settled-entry.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the settled adjusted preview") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        let expectedDocument = viewModel.document
        try await waitUntil("the settled edited preview") {
            guard viewModel.document == expectedDocument else { return false }
            let requests = await fake.previewRequests
            return requests.contains { $0.document == expectedDocument }
        }

        let requestCountBeforeToggle = await fake.previewRequests.count
        XCTAssertTrue(viewModel.toggleSideBySide())

        try await waitUntil("the baseline preview") {
            viewModel.isSideBySideVisible
                && viewModel.originalPreviewSurface.image != nil
        }
        let requests = await fake.previewRequests
        XCTAssertGreaterThan(requests.count, requestCountBeforeToggle)
        let managedURL = try XCTUnwrap(viewModel.sourceURL)
        XCTAssertTrue(requests.contains {
            $0.document == viewModel.document.comparisonBaseline
                && $0.lutID == nil
                && $0.source?.backing == .url(managedURL)
        })
        XCTAssertNotNil(viewModel.previewSurface.image)
        XCTAssertNotNil(viewModel.originalPreviewSurface.image)
    }

    func testEntryDoesNotWaitForDrawableConfirmationBeforeRequestingBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        // The real MTKView owns this lifecycle. Modeling it here keeps the regression test focused
        // on the gap between a settled publication and its later drawable confirmation.
        viewModel.previewSurface.attachPresentationLifecycle()
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "drawable-entry.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the initial preview publication") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        let expectedDocument = viewModel.document
        try await waitUntil("the settled edited publication") {
            guard viewModel.document == expectedDocument else { return false }
            let requests = await fake.previewRequests
            return requests.contains { $0.document == expectedDocument }
        }

        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the baseline without drawable confirmation") {
            viewModel.isSideBySideVisible
                && viewModel.originalPreviewSurface.image != nil
        }
        let requests = await fake.previewRequests
        XCTAssertTrue(requests.contains {
            $0.document == viewModel.document.comparisonBaseline && $0.lutID == nil
        })
    }

    /// Standard-image Temperature is a post-render adjustment and has historically been stripped
    /// from `EditDocument.comparisonBaseline`. Keep that contract visible at the request boundary:
    /// the adjusted request receives the new value while the Original request remains unchanged.
    func testStandardTemperatureEditLeavesOriginalRequestAtItsBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "standard-temperature.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the settled standard preview") {
            viewModel.sourceName == image.lastPathComponent && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the adjusted standard preview") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 0.5)] }
        }
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the standard baseline preview") {
            viewModel.originalPreviewSurface.image != nil
        }

        let baseline = viewModel.document.comparisonBaseline
        let beforeTemperature = await fake.previewRequests
        viewModel.whiteBalanceBinding(for: .temperature).wrappedValue = 9000

        try await waitUntil("the adjusted standard temperature preview") {
            await fake.previewRequests.contains {
                $0.document.adjustments.contains {
                    if case .temperatureTint(let temp, _) = $0 { return temp == 4000 }
                    return false
                }
            }
        }
        let afterTemperature = await fake.previewRequests
        let newRequests = Array(afterTemperature.dropFirst(beforeTemperature.count))
        XCTAssertTrue(newRequests.contains { $0.document.adjustments.contains { $0.slot == .temperatureTint } })
        XCTAssertTrue(
            newRequests.filter {
                !$0.document.adjustments.contains { $0.slot == .temperatureTint }
            }.allSatisfy { $0.document == baseline },
            "every Original-side request after a standard Temperature edit must keep the baseline"
        )

        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the reopened standard baseline preview") {
            viewModel.originalPreviewSurface.image != nil
        }
        let reopenedRequests = await fake.previewRequests
        XCTAssertTrue(
            reopenedRequests.last?.document == baseline,
            "reopening split view must reuse the same standard-image baseline"
        )
    }

    /// RAW Temperature lives in `rawDevelop`, so a dynamic `originalForComparison` would otherwise
    /// change under the slider. The request log proves both sides of the split: only the adjusted
    /// request receives the new decoder temperature, while the Original request keeps the snapshot
    /// captured before the edit.
    func testRAWTemperatureEditLeavesOriginalRequestAtItsBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        // FakeRenderEngine models RAW preparation from the extension, so the fixture need not be a
        // licensed camera file. This covers the RAW-aware routing without depending on a decoder.
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "raw-temperature.dng", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the settled RAW preview") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.sourceIsRAW
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the adjusted RAW preview") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 0.5)] }
        }
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the RAW baseline preview") {
            viewModel.originalPreviewSurface.image != nil
        }

        let baseline = viewModel.document.comparisonBaseline
        let beforeTemperature = await fake.previewRequests
        viewModel.whiteBalanceBinding(for: .temperature).wrappedValue = 9000

        try await waitUntil("the adjusted RAW temperature preview") {
            await fake.previewRequests.contains {
                $0.document.rawDevelop.neutralTemperature == 9000
            }
        }
        let afterTemperature = await fake.previewRequests
        let newRequests = Array(afterTemperature.dropFirst(beforeTemperature.count))
        XCTAssertTrue(
            newRequests.contains { $0.document.rawDevelop.neutralTemperature == 9000 },
            "the adjusted RAW request must receive the new Temperature"
        )
        XCTAssertTrue(
            newRequests.filter { $0.document.rawDevelop.neutralTemperature != 9000 }
                .allSatisfy { $0.document == baseline },
            "no non-adjusted request may adopt the new RAW Temperature"
        )

        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the reopened RAW baseline preview") {
            viewModel.originalPreviewSurface.image != nil
        }
        let reopenedRequests = await fake.previewRequests
        XCTAssertTrue(
            reopenedRequests.last?.document == baseline,
            "reopening split view must reuse the same RAW baseline"
        )
    }

    /// RAW Tint, like RAW Temperature, is evaluated against the developed source. The request log
    /// proves that only the adjusted request receives the new decoder tint while the Original
    /// request keeps the snapshot captured before the edit.
    func testRAWTintEditLeavesOriginalRequestAtItsBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        // FakeRenderEngine models RAW preparation from the extension, so the fixture need not be a
        // licensed camera file. This covers the RAW-aware routing without depending on a decoder.
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "raw-tint.dng", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the settled RAW preview") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.sourceIsRAW
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the adjusted RAW preview") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 0.5)] }
        }
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the RAW baseline preview") {
            viewModel.originalPreviewSurface.image != nil
        }

        let baseline = viewModel.document.comparisonBaseline
        let beforeTint = await fake.previewRequests
        viewModel.whiteBalanceBinding(for: .tint).wrappedValue = 22

        try await waitUntil("the adjusted RAW tint preview") {
            await fake.previewRequests.contains {
                $0.document.rawDevelop.neutralTint == 22
            }
        }
        let afterTint = await fake.previewRequests
        let newRequests = Array(afterTint.dropFirst(beforeTint.count))
        XCTAssertTrue(
            newRequests.contains { $0.document.rawDevelop.neutralTint == 22 },
            "the adjusted RAW request must receive the new Tint"
        )
        XCTAssertTrue(
            newRequests.filter { $0.document.rawDevelop.neutralTint != 22 }
                .allSatisfy { $0.document == baseline },
            "no non-adjusted request may adopt the new RAW Tint"
        )

        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the reopened RAW baseline preview") {
            viewModel.originalPreviewSurface.image != nil
        }
        let reopenedRequests = await fake.previewRequests
        XCTAssertTrue(
            reopenedRequests.last?.document == baseline,
            "reopening split view must reuse the same RAW baseline"
        )
    }

    func testLateBaselineFromPreviousPhotoCannotPublish() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore(),
            preferences: defaults
        )
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "late-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "late-second.png", in: tempDirectory
        )

        viewModel.openImage(url: first)
        try await waitUntil("the first main preview request") { await fake.previewRequests.count >= 1 }
        try await waitUntil("the first main preview") { viewModel.previewSurface.image != nil }
        let firstManagedURL = try XCTUnwrap(viewModel.sourceURL)

        await fake.gatePreviews()
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the edited first preview request") {
            let requests = await fake.previewRequests
            return requests.contains {
                $0.source?.backing == .url(firstManagedURL) && $0.document == viewModel.document
            }
        }
        XCTAssertTrue(viewModel.toggleSideBySide())
        await fake.releaseNextPreview()
        try await waitUntil("the first baseline request") { await fake.previewRequests.count == 3 }

        viewModel.openImage(url: second)
        XCTAssertNil(viewModel.originalPreviewSurface.image,
                     "the source switch must clear the previous baseline immediately")
        try await waitUntil("the second source") { viewModel.sourceName == second.lastPathComponent }
        let secondManagedURL = try XCTUnwrap(viewModel.sourceURL)
        await fake.releaseNextPreview()
        try await waitUntil("the second main preview request") { await fake.previewRequests.count >= 4 }
        XCTAssertNil(viewModel.originalPreviewSurface.image,
                     "a late baseline from the previous source must not repopulate the pane")
        await fake.releasePreviews()

        try await waitUntil("the second comparison") {
            viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }
        let requests = await fake.previewRequests
        let diagnostics = requests.map { request in
            let source = request.source?.backing == .url(secondManagedURL) ? "second" : "first"
            let token = request.source?.traceToken ?? "missing-source"
            let asset = request.source?.portableIdentity.assetID.raw ?? "missing-asset"
            return "\(source):token=\(token):asset=\(asset):requestRevision=\(request.requestRevision):document=\(request.document.editHash)"
        }.joined(separator: ",")
        XCTAssertTrue(
            requests.contains { $0.source?.backing == .url(firstManagedURL) && $0.document == EditDocument() },
            "missing first-photo baseline; requests=\(diagnostics)"
        )
        XCTAssertTrue(
            requests.contains { $0.source?.backing == .url(secondManagedURL) && $0.document == EditDocument() },
            "missing second-photo baseline; requests=\(diagnostics)"
        )
        XCTAssertTrue(requests.filter { $0.source?.backing == .url(secondManagedURL) }.allSatisfy {
            $0.document == EditDocument()
        }, "second-photo request crossed an edit identity fence; requests=\(diagnostics)")
    }

    private func enableSideBySide(on viewModel: AppViewModel) {
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.25)] }
        XCTAssertTrue(viewModel.toggleSideBySide())
    }

    private func waitForBothSurfaces(
        _ viewModel: AppViewModel,
        fake: FakeRenderEngine,
        image: URL
    ) async throws {
        try await waitUntil("the identity comparison surfaces") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }
        try await waitUntil("the identity render requests") {
            await fake.previewRequests.count >= 2
        }
    }

    private func assertIdentityComparison(
        _ viewModel: AppViewModel,
        fake: FakeRenderEngine,
        image: URL
    ) async throws {
        XCTAssertTrue(viewModel.document.isIdentity)
        XCTAssertTrue(viewModel.previewSurface.image != nil)
        XCTAssertTrue(viewModel.originalPreviewSurface.image != nil)
        XCTAssertTrue(viewModel.isSideBySide)
        XCTAssertTrue(viewModel.isSideBySideVisible)

        let requests = await fake.previewRequests
        XCTAssertGreaterThanOrEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.document.isIdentity })
        let managedURL = try XCTUnwrap(viewModel.sourceURL)
        XCTAssertTrue(requests.allSatisfy { $0.source?.backing == .url(managedURL) })
        XCTAssertEqual(viewModel.sourceName, image.lastPathComponent)
    }

    func testReturningToSinglePhotoModeIsAlsoRemembered() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }

        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertFalse(viewModel.isSideBySide)

        let relaunched = makeViewModel(defaults: defaults)
        XCTAssertFalse(relaunched.isSideBySide)
    }
}
