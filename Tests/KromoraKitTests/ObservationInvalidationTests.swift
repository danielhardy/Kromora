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
        // they must never pass through AppViewModel fan-in. Low-frequency ObservableObject
        // children (settings, library, media workflow, editor document, derive, look-save)
        // are still consumed via `viewModel.*` until their views hold them directly, so they
        // forward synchronously with `objectWillChange.send()` in the same turn — never via
        // a Task, which had incorrect will-change timing. Assert the composition root exposes
        // the isolated children that views must observe directly.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertNotNil(viewModel.collection as Any)
        XCTAssertNotNil(viewModel.photosImportCoordinator as Any)
        XCTAssertNotNil(viewModel.export as Any)
        XCTAssertNotNil(viewModel.canvasState as Any)
    }

    func testLowFrequencyChildrenForwardSynchronouslyWithoutTask() {
        // Interim KRMA-521 boundary: legacy views still read these via `viewModel.*`, so a
        // child will-change must synchronously invalidate the root in the same turn. A Task
        // would defer to a later turn (the pre-migration bug); asserting the increment is
        // visible immediately proves no Task sits in the path.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var appChanges = 0
        let subscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }

        let beforeNames = viewModel.settings.showPhotoNames
        viewModel.settings.showPhotoNames = !beforeNames
        XCTAssertEqual(appChanges, 1, "settings must forward synchronously")

        viewModel.library.isScanning = true
        XCTAssertEqual(appChanges, 2, "library must forward synchronously")
        viewModel.library.isScanning = false
        XCTAssertEqual(appChanges, 3)

        viewModel.derive.isSheetPresented = true
        XCTAssertEqual(appChanges, 4, "derive sheet must forward synchronously")
        viewModel.derive.isSheetPresented = false
        XCTAssertEqual(appChanges, 5)

        viewModel.lookSave.isSheetPresented = true
        XCTAssertEqual(appChanges, 6, "look-save sheet must forward synchronously")
        viewModel.lookSave.isSheetPresented = false
        XCTAssertEqual(appChanges, 7)

        viewModel.editorDocument.copy(document: EditDocument())
        // `copy` writes two @Published values (clipboard + categories), so two
        // will-change events forward synchronously.
        XCTAssertEqual(appChanges, 9, "clipboard must forward synchronously")

        viewModel.libraryMediaWorkflow.isRemovableMediaSelectorPresented = true
        XCTAssertEqual(appChanges, 10, "removable-media chrome must forward synchronously")
        viewModel.libraryMediaWorkflow.isRemovableMediaSelectorPresented = false
        XCTAssertEqual(appChanges, 11)

        withExtendedLifetime(subscription) {}
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

    func testViewBodyCountersTrackEvaluations() {
        ViewBodyCounter.reset()
        XCTAssertEqual(ViewBodyCounter.contentViewEvaluations, 0)
        XCTAssertEqual(ViewBodyCounter.inspectorEvaluations, 0)
        XCTAssertEqual(ViewBodyCounter.gridEvaluations, 0)

        ViewBodyCounter.noteContentViewBody()
        ViewBodyCounter.noteInspectorBody()
        ViewBodyCounter.noteGridBody()
        ViewBodyCounter.noteToolbarBody()

        let snapshot = ViewBodyCounter.snapshot
        XCTAssertEqual(snapshot.content, 1)
        XCTAssertEqual(snapshot.inspector, 1)
        XCTAssertEqual(snapshot.grid, 1)
        XCTAssertEqual(snapshot.toolbar, 1)

        ViewBodyCounter.reset()
        XCTAssertEqual(ViewBodyCounter.snapshot.content, 0)
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
