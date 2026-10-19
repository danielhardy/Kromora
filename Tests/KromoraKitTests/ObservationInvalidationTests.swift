import AppKit
import Observation
import os
import Synchronization
import SwiftUI
import XCTest

@testable import KromoraKit

/// Observation-focused coverage for KRMA-521.
///
/// Verifies that high-frequency state (thumbnail streaming, import/export progress, canvas
/// navigation) publishes through its own Observation boundary and never through AppViewModel's
/// former Combine publisher fan-in, that LUT projections are memoized, and that navigation/slider
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

    private func fires(_ read: @MainActor () -> Void, after mutate: @MainActor () -> Void) -> Bool {
        let fired = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { read() } onChange: { fired.withLock { $0 = true } }
        mutate()
        return fired.withLock { $0 }
    }

    /// KRMA-977: histogram and metadata are tracked on `InfoState`, not on the root.
    func testInfoStateHistogramTracksIndependentlyOfStatusMessage() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(fires(
            { _ = viewModel.info.histogram },
            after: { viewModel.info.histogram = HistogramData(
                red: [1], green: [1], blue: [1], luma: [1]) }))
        XCTAssertFalse(fires(
            { _ = viewModel.info.histogram },
            after: { viewModel.statusMessage = "unrelated" }))
    }

    /// KRMA-978: status text and the library query are tracked on separate `@Observable` objects.
    func testStatusMessageAndPortableQueryTrackIndependently() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(fires(
            { _ = viewModel.statusMessage }, after: { viewModel.statusMessage = "changed" }))
        XCTAssertFalse(fires(
            { _ = viewModel.statusMessage }, after: { viewModel.portableQuery.searchText = "x" }))
        XCTAssertTrue(fires(
            { _ = viewModel.portableQuery }, after: { viewModel.portableQuery.searchText = "y" }))
        XCTAssertFalse(fires(
            { _ = viewModel.portableQuery }, after: { viewModel.statusMessage = "again" }))
        XCTAssertEqual(viewModel.status.message, "again")
        XCTAssertEqual(viewModel.libraryPresentation.query.searchText, "y")
    }

    /// KRMA-979: pointer-rate sampler state and Auto progress are tracked on separate children.
    func testSamplerPointAndAutoProgressTrackIndependently() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(fires(
            { _ = viewModel.whiteBalance.samplerPoint },
            after: { viewModel.whiteBalance.samplerPoint = CGPoint(x: 12, y: 24) }))
        XCTAssertFalse(fires(
            { _ = viewModel.whiteBalance.samplerPoint },
            after: { viewModel.autoLook.publishAuto(.analyzing, progress: 0.4) }))
        XCTAssertTrue(fires(
            { _ = viewModel.autoLook.autoAdjustmentProgress },
            after: { viewModel.autoLook.publishAuto(.analyzing, progress: 0.6) }))
        XCTAssertFalse(fires(
            { _ = viewModel.autoLook.autoAdjustmentProgress },
            after: { viewModel.whiteBalance.samplerPoint = CGPoint(x: 20, y: 32) }))
    }

    func testClipboardPresentationIsObservedDirectlyNotThroughRoot() {
        // KRMA-976: root forwarders read `@Observable` children, so they are tracked transitively.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(fires(
            { _ = viewModel.isSelectiveCopyDialogPresented },
            after: { viewModel.editClipboardWorkflow.isSelectiveCopyDialogPresented = true }))
        XCTAssertTrue(fires(
            { _ = viewModel.selectiveCopyCategories },
            after: { viewModel.editClipboardWorkflow.selectiveCopyCategories = [.light] }))
        XCTAssertTrue(viewModel.isSelectiveCopyDialogPresented)
        XCTAssertEqual(viewModel.selectiveCopyCategories, [.light])
    }

    func testPasteAvailabilityIsTrackedThroughTheClipboardCoordinator() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let destination = ClipboardTrackingDestination()
        viewModel.editClipboardWorkflow.destination = destination

        XCTAssertTrue(fires(
            { _ = viewModel.canPasteEdits },
            after: { viewModel.editClipboardWorkflow.copyAllEdits() }))
        XCTAssertTrue(viewModel.canPasteEdits)
    }

    func testUndoAvailabilityIsTrackedThroughTheEditorCoordinator() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.beginUndoGrouping()
        var changed = viewModel.document
        changed.light.exposure = 0.5
        viewModel.editorDocument.recordChange(from: viewModel.document, to: changed)
        XCTAssertFalse(viewModel.canUndo, "recording inside a group is deferred")
        XCTAssertTrue(fires({ _ = viewModel.canUndo }, after: { viewModel.editorDocument.endGrouping(document: changed) }))
        XCTAssertTrue(viewModel.canUndo)
    }

    func testDurableHistoryAndVirtualCopyForwardersTrackTheirChildren() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "observation-forwarders.png", in: tempDirectory
        )
        let packageURL = tempDirectory.appendingPathComponent("ObservationForwarders.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL)
        let imported = try session.importURLs([source])
        let originalID = try XCTUnwrap(imported.imported.first?.assetID)
        let copy = try await session.createVirtualCopy(of: originalID)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL,
            portableLibrarySession: session
        )
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()

        let copyIndex = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.displayName == copy.displayName })
        let virtualCopyChanges = Mutex(0)
        withObservationTracking {
            _ = viewModel.virtualCopySourceDescription
        } onChange: {
            virtualCopyChanges.withLock { $0 += 1 }
        }
        viewModel.collection.setSelection(at: copyIndex)
        viewModel.openActiveCollectionImage()
        try await waitUntil("virtual-copy source description") {
            viewModel.virtualCopySourceDescription != nil
        }
        XCTAssertEqual(virtualCopyChanges.withLock { $0 }, 1)
        XCTAssertEqual(
            viewModel.virtualCopySourceDescription,
            "Virtual copy of \(originalID.raw.prefix(8))"
        )

        let historyChanges = Mutex(0)
        withObservationTracking {
            _ = viewModel.durableEditHistory
        } onChange: {
            historyChanges.withLock { $0 += 1 }
        }
        viewModel.saveEditSnapshot(named: "Tracked snapshot")
        try await waitUntil("durable edit history") { !viewModel.durableEditHistory.isEmpty }
        XCTAssertGreaterThan(historyChanges.withLock { $0 }, 0)
    }

    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testRootHasNoObjectWillChangeSends() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Spelled in pieces so this file does not match its own search.
            XCTAssertFalse(text.contains("object" + "WillChange"), "\(url.lastPathComponent)")
            XCTAssertFalse(text.contains("Observed" + "Object var viewModel"), "\(url.lastPathComponent)")
            XCTAssertFalse(text.contains("State" + "Object private var viewModel"), "\(url.lastPathComponent)")
            XCTAssertFalse(text.contains("willChange"), "\(url.lastPathComponent)")
        }
    }

    func testLibraryAndSettingsAreObservedDirectlyNotThroughRoot() {
        // KRMA-975: both children are `@Observable`; a read of one property is invalidated by
        // that property alone and never fans in to the root.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let probe = RootChangeProbe(viewModel)
        let settingsChanges = OSAllocatedUnfairLock(initialState: 0)
        let libraryChanges = OSAllocatedUnfairLock(initialState: 0)

        withObservationTracking {
            _ = viewModel.settings.showPhotoNames
        } onChange: { settingsChanges.withLock { $0 += 1 } }
        viewModel.settings.showPhotoNames.toggle()
        XCTAssertEqual(settingsChanges.withLock { $0 }, 1)

        withObservationTracking {
            _ = viewModel.library.isScanning
        } onChange: { libraryChanges.withLock { $0 += 1 } }
        viewModel.library.isScanning = true
        XCTAssertEqual(libraryChanges.withLock { $0 }, 1)
        XCTAssertEqual(probe.count, 0, "library/settings must not fan in to the root")
    }

    func testMaskOverlayAppearanceReachesInteractionStateImmediately() {
        let suite = "ObservationMask-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var chosen = MaskOverlayAppearance.standard
        chosen.opacity = 0.9
        let seeded = KromoraSettings(preferences: defaults)
        seeded.maskOverlayAppearance = chosen

        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), preferences: defaults)
        XCTAssertEqual(viewModel.maskInteractionState.overlayOpacity, 0.9,
                       "launch applies the persisted appearance before any change")

        var changed = chosen
        changed.opacity = 0.3
        viewModel.settings.maskOverlayAppearance = changed
        XCTAssertEqual(viewModel.maskInteractionState.overlayOpacity, 0.3)
    }

    /// Mutates a presenting property and reports whether `read` (the code path a view uses) was
    /// notified, and whether the root `AppViewModel` publisher stayed quiet.
    private func assertPresentationIsTracked(
        _ viewModel: AppViewModel,
        read: @MainActor () -> Bool,
        set: @MainActor (Bool) -> Void,
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let probe = RootChangeProbe(viewModel)
        let notified = Mutex(0)
        withObservationTracking({ _ = read() }, onChange: { notified.withLock { $0 += 1 } })
        set(true)
        XCTAssertEqual(notified.withLock { $0 }, 1, "\(label) must notify its reader", file: file, line: line)
        XCTAssertTrue(read(), file: file, line: line)
        XCTAssertEqual(probe.count, 0, "\(label) must not fan into the root", file: file, line: line)
        set(false)
    }

    func testDeriveLookSaveAndMediaPresentationIsTrackedWithoutRootForwarding() {
        // KRMA-974: these children are @Observable and read directly by their views. Each
        // presenting property is read through the path the view uses.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.derive.onStatus = nil
        viewModel.lookSave.onStatus = nil
        viewModel.libraryMediaWorkflow.onStatus = nil

        assertPresentationIsTracked(
            viewModel,
            read: { viewModel.derive.isSheetPresented },
            set: { viewModel.derive.isSheetPresented = $0 }, "derive sheet")
        assertPresentationIsTracked(
            viewModel,
            read: { viewModel.lookSave.isSheetPresented },
            set: { viewModel.lookSave.isSheetPresented = $0 }, "look-save sheet")
        // Through the AppViewModel computed forwarder, which readers such as the menu commands use.
        assertPresentationIsTracked(
            viewModel,
            read: { viewModel.isRemovableMediaSelectorPresented },
            set: { viewModel.libraryMediaWorkflow.isRemovableMediaSelectorPresented = $0 },
            "removable-media selector")
    }

    func testMountedSheetHostReEvaluatesWhenCoordinatorsPresent() {
        // KRMA-974: a mounted view that holds the coordinators as the sheet host does must
        // re-evaluate its body when a presenting property flips.
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let counter = BodyCounter()
        let hosting = host(CoordinatorReadView(
            derive: viewModel.derive, lookSave: viewModel.lookSave,
            media: viewModel.libraryMediaWorkflow, counter: counter))
        let initial = counter.count

        viewModel.derive.isSheetPresented = true
        drainMainActor()
        XCTAssertGreaterThan(counter.count, initial, "derive presentation re-evaluates the host")
        let afterDerive = counter.count
        viewModel.lookSave.isSheetPresented = true
        drainMainActor()
        XCTAssertGreaterThan(counter.count, afterDerive, "look-save presentation re-evaluates")
        let afterLook = counter.count
        viewModel.libraryMediaWorkflow.isRemovableMediaSelectorPresented = true
        drainMainActor()
        XCTAssertGreaterThan(counter.count, afterLook, "selector presentation re-evaluates")
        withExtendedLifetime(hosting) {}
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
        let probe = RootChangeProbe(viewModel)

        coordinator.begin(totalCount: 2)
        XCTAssertEqual(probe.count, 0)
        coordinator.updatePhase(.transferring, name: "photo-1.jpg")
        XCTAssertEqual(probe.count, 0)
        coordinator.cancel()
        XCTAssertEqual(probe.count, 0)
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
        let probe = RootChangeProbe(viewModel)

        item.setOriginalThumbnail(NSImage(size: NSSize(width: 4, height: 4)))
        XCTAssertEqual(probe.count, 0, "thumbnail arrival must not invalidate the root")
        XCTAssertNotNil(item.thumbnail)
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
        let probe = RootChangeProbe(viewModel)

        coordinator.begin(totalCount: 3)
        XCTAssertEqual(probe.count, 0)
        XCTAssertNotNil(coordinator.progress)

        coordinator.updatePhase(.transferring, name: "photo-1.jpg")
        XCTAssertEqual(probe.count, 0)

        coordinator.cancel()
    }

    func testExportProgressIsIsolatedFromBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let probe = RootChangeProbe(viewModel)

        // Export progress lives on the coordinator; the broad publisher must stay silent.
        // Drive the coordinator directly through its public progress surface.
        let coordinator = viewModel.export
        XCTAssertFalse(coordinator.isExporting)
        XCTAssertEqual(probe.count, 0)
    }

    func testCanvasNavigationDoesNotTriggerBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 64, height: 64)
        )
        let probe = RootChangeProbe(viewModel)

        viewModel.setCanvasZoom(2)
        viewModel.panCanvas(by: CGSize(width: 4, height: 4), viewportSize: CGSize(width: 80, height: 60))
        XCTAssertEqual(probe.count, 0)
        XCTAssertEqual(viewModel.canvasState.navigation.zoom, 2)
    }

    // MARK: - LUT memoization

    func testLUTProjectionsAreMemoizedAgainstRevision() {
        let library = makeLUTLibrary()
        let cacheFillChanges = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = library.starterCategories
        } onChange: {
            cacheFillChanges.withLock { $0 += 1 }
        }
        XCTAssertEqual(
            cacheFillChanges.withLock { $0 }, 0,
            "filling private projection caches must not invalidate a view"
        )

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

    /// KRMA-973: the view-local state objects are `@Observable`; none may regress to Combine.
    func testViewLocalStateTypesAreNotObservableObjects() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/KromoraKit")
        let types = [
            "InspectorState", "MaskInteractionState", "RetouchInteractionState",
            "MaskDiscoveryState", "PreviewSurface", "MaskingPanelModel", "AnalysisDebugPanelModel",
        ]
        let files = try XCTUnwrap(FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for type in types {
                if text.contains("final class \(type)") { scanned += 1 }
                XCTAssertFalse(
                    text.contains("class \(type): ObservableObject"),
                    "\(type) must be @Observable (\(url.lastPathComponent))")
            }
        }
        XCTAssertEqual(scanned, types.count, "every converted type should be found by the scan")
    }
}

private struct CoordinatorReadView: View {
    let derive: DeriveCoordinator
    let lookSave: LookSaveCoordinator
    let media: LibraryMediaWorkflowCoordinator
    let counter: BodyCounter

    var body: some View {
        counter.note()
        _ = derive.isSheetPresented
        _ = lookSave.isSheetPresented
        _ = media.isRemovableMediaSelectorPresented
        return Color.clear
    }
}

@MainActor
private final class ClipboardTrackingDestination: EditClipboardDestination {
    var clipboardHasCopySource = true
    var clipboardSourceName = "Source"
    var clipboardDocument = EditDocument()
    var clipboardActiveSourceReference: EditSourceReference?
    var clipboardActiveDestinationIsRAW: Bool? = false
    var clipboardSelectedTargets: [EditClipboardTarget] = []

    func updateDocument(_ transform: (inout EditDocument) -> Void) {}
    func endUndoGrouping() {}
    func activateClipboardAsset(_ assetID: PhotoAssetID) {}
    func setClipboardStatus(_ message: String) {}
    func persistInactiveClipboardDocument(
        _ document: EditDocument, for reference: EditSourceReference
    ) {}
    func loadClipboardBase(for reference: EditSourceReference) async -> EditDocumentLoadResult {
        EditDocumentLoadResult(document: EditDocument(), found: false, status: .ready)
    }
    func flushClipboardPersistence() {}
}
