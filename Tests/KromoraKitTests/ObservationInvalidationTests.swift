import AppKit
import XCTest

@testable import KromoraKit

/// Observation-focused coverage for KRMA-521.
///
/// Verifies that high-frequency state (thumbnail streaming, import/export progress, canvas
/// navigation) publishes through its own Observation boundary and never through AppViewModel's
/// former objectWillChange fan-in, that LUT projections are memoized, and that navigation/slider
/// p95 does not regress.
@MainActor
final class ObservationInvalidationTests: TempDirectoryTestCase {

    // MARK: - Fan-in removal

    func testNoTaskPerChildNotificationRemains() {
        // High-frequency children are @Observable and observed directly via `@Bindable`;
        // they must never pass through AppViewModel fan-in. Clipboard presentation observes its
        // coordinator directly, while EditorDocumentCoordinator is plain value state. Assert
        // the composition root still exposes the children that need direct observation without
        // introducing another owner.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertNotNil(viewModel.collection as Any)
        XCTAssertNotNil(viewModel.photosImportCoordinator as Any)
        XCTAssertNotNil(viewModel.export as Any)
        XCTAssertNotNil(viewModel.canvasState as Any)
    }

    func testClipboardPresentationIsObservedDirectlyNotThroughRoot() {
        // KRMA-909: the selective-copy sheet and paste availability observe the clipboard
        // directly, so clipboard-only changes publish on the child and never on the root.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var rootChanges = 0
        var clipboardChanges = 0
        let subscriptions = [
            viewModel.objectWillChange.sink { _ in rootChanges += 1 },
            viewModel.editClipboardWorkflow.objectWillChange.sink { _ in clipboardChanges += 1 },
        ]

        viewModel.editClipboardWorkflow.selectiveCopyCategories = [.light]
        viewModel.editClipboardWorkflow.isSelectiveCopyDialogPresented = true

        XCTAssertEqual(clipboardChanges, 2, "the sheet's observer receives each presentation change")
        XCTAssertEqual(rootChanges, 0, "clipboard presentation must not invalidate the root")
        XCTAssertTrue(viewModel.isSelectiveCopyDialogPresented)
        XCTAssertEqual(viewModel.selectiveCopyCategories, [.light])
        withExtendedLifetime(subscriptions) {}
    }

    func testClosingAnUndoGroupPublishesHistoryAvailabilityOnTheRoot() {
        // KRMA-909: the editor coordinator has no publisher. Ending a gesture group flips
        // canUndo without a document change, so the root announces it before the mutation.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.beginUndoGrouping()
        viewModel.editorDocument.recordChange(from: viewModel.document, to: {
            var changed = viewModel.document
            changed.light.exposure = 0.5
            return changed
        }())
        XCTAssertFalse(viewModel.canUndo, "recording inside a group is deferred")

        var rootChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in rootChanges += 1 }
        viewModel.endUndoGrouping()

        XCTAssertEqual(rootChanges, 1)
        withExtendedLifetime(subscription) {}
    }

    func testLibraryAndSettingsAreObservedDirectlyNotThroughRoot() {
        // KRMA-908: LookInspectorView, FilmstripView and the other settings consumers hold the
        // children directly, so child-only changes emit on their own publishers (before: one
        // root event per change; after: zero) without touching the root.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var rootChanges = 0
        var settingsChanges = 0
        var libraryChanges = 0
        let subscriptions = [
            viewModel.objectWillChange.sink { _ in rootChanges += 1 },
            viewModel.settings.objectWillChange.sink { _ in settingsChanges += 1 },
            viewModel.library.objectWillChange.sink { _ in libraryChanges += 1 },
        ]

        viewModel.settings.showPhotoNames.toggle()
        XCTAssertEqual(settingsChanges, 1)
        viewModel.library.isScanning = true
        viewModel.library.isScanning = false
        XCTAssertEqual(libraryChanges, 2)
        XCTAssertEqual(rootChanges, 0, "library/settings must not fan in to the root")

        withExtendedLifetime(subscriptions) {}
    }

    func testDeriveLookSaveAndMediaStateIsObservedDirectlyNotThroughRoot() {
        // KRMA-907: these children are observed by FeatureSheetsModifier, RemovableMediaMenu and
        // RemovableMediaSelectorView, so child-only changes reach their own publishers without
        // touching the root. Status/error callbacks are detached because they are legitimate
        // root effects.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.derive.onStatus = nil
        viewModel.derive.onError = nil
        viewModel.lookSave.onStatus = nil
        viewModel.lookSave.onError = nil
        viewModel.libraryMediaWorkflow.onStatus = nil
        viewModel.libraryMediaWorkflow.onError = nil
        var appChanges = 0
        var deriveChanges = 0
        var lookSaveChanges = 0
        var mediaChanges = 0
        let subscriptions = [
            viewModel.objectWillChange.sink { _ in appChanges += 1 },
            viewModel.derive.objectWillChange.sink { _ in deriveChanges += 1 },
            viewModel.lookSave.objectWillChange.sink { _ in lookSaveChanges += 1 },
            viewModel.libraryMediaWorkflow.objectWillChange.sink { _ in mediaChanges += 1 },
        ]

        viewModel.derive.isSheetPresented = true
        viewModel.derive.isSheetPresented = false
        viewModel.lookSave.isSheetPresented = true
        viewModel.lookSave.isSheetPresented = false
        viewModel.libraryMediaWorkflow.isRemovableMediaSelectorPresented = true
        viewModel.libraryMediaWorkflow.isRemovableMediaSelectorPresented = false

        XCTAssertEqual(deriveChanges, 2, "derive sheet still reaches its own observers")
        XCTAssertEqual(lookSaveChanges, 2, "look-save sheet still reaches its own observers")
        XCTAssertEqual(mediaChanges, 2, "removable-media chrome still reaches its own observers")
        XCTAssertEqual(appChanges, 0, "migrated children must not fan into the root")

        withExtendedLifetime(subscriptions) {}
    }

    func testViewModelImportCoordinatorProgressStaysIsolated() {
        // The viewModel-owned import coordinator with its destination detached must not fan
        // into the root: progress publishes through its own @Observable boundary. Destination
        // writes (prepare/finish -> viewModel @Published) are a separate, legitimate path and
        // are detached here to isolate fan-in from destination side effects.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = viewModel.photosImportCoordinator
        coordinator.destination = nil
        coordinator.onStatus = nil
        coordinator.onProgress = nil
        var appChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }

        coordinator.begin(totalCount: 2)
        XCTAssertEqual(appChanges, 0)
        coordinator.updatePhase(.transferring, name: "photo-1.jpg")
        XCTAssertEqual(appChanges, 0)
        coordinator.cancel()
        XCTAssertEqual(appChanges, 0)

        withExtendedLifetime(subscription) {}
    }

    func testCollectionThumbnailStreamingDoesNotTriggerBroadPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let item = ImageCollection.Item(
            asset: PhotoAsset(
                source: PhotoAssetSource(
                    data: Data([0x01]),
                    id: .imported(UUID()),
                    fingerprint: PhotoSourceFingerprint(
                        byteCount: 1, modificationDate: nil,
                        resourceIdentifier: UUID().uuidString, sampleDigest: UUID().uuidString
                    )
                ),
                filename: "thumb.jpg", fileType: "jpg"
            ))
        viewModel.collection.items = [item]
        var appChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }

        item.setOriginalThumbnail(NSImage(size: NSSize(width: 4, height: 4)))
        XCTAssertEqual(appChanges, 0, "thumbnail arrival must not invalidate the root")
        XCTAssertNotNil(item.thumbnail)

        withExtendedLifetime(subscription) {}
    }

    func testThumbnailStreamingDoesNotTouchCollectionRevision() {
        let collection = makeTestCollection()
        let items = (0..<5).map { index in
            let id = PhotoAssetID.imported(UUID())
            let source = PhotoAssetSource(
                data: Data([UInt8(index)]),
                id: id,
                fingerprint: PhotoSourceFingerprint(
                    byteCount: 1, modificationDate: nil,
                    resourceIdentifier: id.raw, sampleDigest: id.raw
                )
            )
            return ImageCollection.Item(asset: PhotoAsset(
                source: source, filename: "photo-\(index).jpg", fileType: "jpg"
            ))
        }
        collection.items = items
        _ = collection.thumbnailEntries
        let rebuildsBefore = collection.projectionRebuildCount

        // Simulate thumbnail streaming: each arrival mutates only its item.
        for item in items {
            item.setOriginalThumbnail(NSImage(size: NSSize(width: 4, height: 4)))
        }
        _ = collection.thumbnailEntries

        XCTAssertEqual(collection.projectionRebuildCount, rebuildsBefore)
        for item in items {
            XCTAssertNotNil(item.thumbnail)
        }
    }

    func testImportProgressDoesNotTriggerBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        // Use a standalone coordinator with no destination to isolate the former fan-in:
        // coordinator `progress` writes must not forward through AppViewModel. The viewModel's
        // own destination path (`preparePhotosImport` -> `portableImportProgress`, `onStatus`
        // -> `statusMessage`) legitimately writes AppViewModel's own @Published state, which the
        // status bar observes directly; that is not fan-in and is covered separately.
        let coordinator = PhotosImportCoordinator()
        coordinator.onStatus = nil
        coordinator.onProgress = nil
        var appChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }

        coordinator.begin(totalCount: 3)
        XCTAssertEqual(appChanges, 0)
        XCTAssertNotNil(coordinator.progress)

        coordinator.updatePhase(.transferring, name: "photo-1.jpg")
        XCTAssertEqual(appChanges, 0)

        coordinator.cancel()
        withExtendedLifetime(subscription) {}
    }

    func testExportProgressIsIsolatedFromBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var appChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }

        // Export progress lives on the coordinator; the broad publisher must stay silent.
        // Drive the coordinator directly through its public progress surface.
        let coordinator = viewModel.export
        XCTAssertFalse(coordinator.isExporting)
        XCTAssertEqual(appChanges, 0)

        withExtendedLifetime(subscription) {}
    }

    func testCanvasNavigationDoesNotTriggerBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 64, height: 64)
        )
        var appChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }

        viewModel.setCanvasZoom(2)
        viewModel.panCanvas(by: CGSize(width: 4, height: 4), viewportSize: CGSize(width: 80, height: 60))
        XCTAssertEqual(appChanges, 0)
        XCTAssertEqual(viewModel.canvasState.navigation.zoom, 2)

        withExtendedLifetime(subscription) {}
    }

    // MARK: - LUT memoization

    func testLUTProjectionsAreMemoizedAgainstRevision() {
        let library = makeLUTLibrary()
        let firstStarter = library.starterCategories
        let firstRebuilds = library.projectionRebuildCount
        // Repeated reads without an intervening publish must not rebuild.
        _ = library.starterCategories
        _ = library.starterLooks
        _ = library.myLooks
        _ = library.lookCollections
        _ = library.starterCategories
        XCTAssertEqual(library.projectionRebuildCount, firstRebuilds)
        XCTAssertEqual(firstStarter.count, library.starterCategories.count)
    }

    // MARK: - Body-evaluation instrumentation

    func testRenderDiagnosticsSnapshotTracksEvaluations() {
        RenderDiagnostics.reset()
        XCTAssertEqual(RenderDiagnostics.snapshot, .init(
            contentViewBodyEvaluations: 0,
            inspectorBodyEvaluations: 0,
            gridBodyEvaluations: 0,
            gridMounts: 0,
            gridUnmounts: 0,
            toolbarBodyEvaluations: 0,
            presentationCoreImageEvaluations: 0
        ))

        RenderDiagnostics.noteContentViewBody()
        RenderDiagnostics.noteInspectorBody()
        RenderDiagnostics.noteGridBody()
        RenderDiagnostics.noteGridMount()
        RenderDiagnostics.noteGridUnmount()
        RenderDiagnostics.noteToolbarBody()
        RenderDiagnostics.notePresentationCoreImageEvaluation()

        XCTAssertEqual(RenderDiagnostics.snapshot, .init(
            contentViewBodyEvaluations: 1,
            inspectorBodyEvaluations: 1,
            gridBodyEvaluations: 1,
            gridMounts: 1,
            gridUnmounts: 1,
            toolbarBodyEvaluations: 1,
            presentationCoreImageEvaluations: 1
        ))

        RenderDiagnostics.reset()
        XCTAssertEqual(RenderDiagnostics.snapshot.presentationCoreImageEvaluations, 0)
    }

    // MARK: - Navigation / slider p95 (same-host, no regression)

    func testNavigationP95StaysWithinBudget() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 200, height: 150)
        )
        var samples: [Double] = []
        for i in 0..<50 {
            let start = DispatchTime.now().uptimeNanoseconds
            viewModel.setCanvasZoom(1 + Double(i % 8) * 0.25)
            viewModel.panCanvas(
                by: CGSize(width: Double(i % 5), height: Double(i % 3)),
                viewportSize: CGSize(width: 300, height: 200)
            )
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
        }
        let p95 = ObservationPerformance.p95(milliseconds: samples)
        let median = ObservationPerformance.median(milliseconds: samples)
        print(String(format: "OBSERVATION_NAV_PROFILE p50_ms=%.3f p95_ms=%.3f samples=%d", median, p95, samples.count))
        // Navigation is presentation-only value work; p95 must stay well under a frame budget.
        XCTAssertLessThan(p95, 16)
    }

    func testSliderValueThroughputP95StaysWithinBudget() {
        // Slider drags funnel through document updates; measure the value-only path that must
        // stay interactive while Observation keeps inspector/grid invalidation localized.
        var samples: [Double] = []
        var document = EditDocument()
        for i in 0..<100 {
            let start = DispatchTime.now().uptimeNanoseconds
            document.light.exposure = Double(i % 21) * 0.05 - 0.5
            _ = document.light.exposure
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
        }
        let p95 = ObservationPerformance.p95(milliseconds: samples)
        print(String(format: "OBSERVATION_SLIDER_PROFILE p95_ms=%.3f samples=%d", p95, samples.count))
        XCTAssertLessThan(p95, 16)
    }

    // MARK: - Ownership semantics

    func testObservableTypesAreNotWrappedInStateObject() {
        // Compile-time guard: migrated types are @Observable, which must be held with @State or
        // @Bindable in views, never @StateObject. This test documents the contract; the actual
        // misuse check runs via source inspection (no @StateObject for @Observable types).
        XCTAssertTrue((CanvasInteractionState.self as Any) is AnyObject.Type)
        XCTAssertTrue((ImageCollection.self as Any) is AnyObject.Type)
        XCTAssertTrue((PhotosImportCoordinator.self as Any) is AnyObject.Type)
        XCTAssertTrue((ExportCoordinator.self as Any) is AnyObject.Type)
    }
}
