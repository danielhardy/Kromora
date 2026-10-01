import AppKit
import CoreImage
import Foundation
import QuartzCore
import SwiftUI
import XCTest

@testable import KromoraKit

/// Release-only qualification of the warm Edit and 30-cell grid paths. The test mounts the
/// shipping ContentView in a visible window; confirmation counts come from PreviewSurface's
/// drawable callback and renderer admissions come from PreviewCoordinator.
///
/// Environment:
/// - `KROMORA_LAST_KNOWN_FRAME_BENCHMARK` opts in (the capture script sets it).
/// - `KROMORA_LAST_KNOWN_FRAME_RAW` / `KROMORA_LAST_KNOWN_FRAME_ITERATIONS` choose the source and
///   warm sample count (5...100, default 30).
/// - `KROMORA_LAST_KNOWN_FRAME_REPORT` appends each JSON record to that file, so a consumer does
///   not have to parse them out of interleaved xctest output.
/// - `KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS` fails the test when a wall-clock budget misses.
///   Without it the test fails only for harness errors and structural (count) criteria, and the
///   budget verdicts are reported in the records.
@MainActor
final class LastKnownFrameReleaseBenchmark: TempDirectoryTestCase {
    private enum BenchmarkError: Error {
        case presentationTimedOut(String)
    }

    /// The KRMA-734 grid budget is defined for 30 visible cells: 29 generated JPEGs plus the RAW.
    private static let gridCellCount = 30

    private struct Report: Encodable {
        let benchmark: String
        let source: String
        let sourceFormat: String
        let sourceDimensions: String
        let machine: String
        let osVersion: String
        let commit: String
        let viewportPoints: String
        let backingPixels: String
        let coldWarmState: String
        let cacheState: String
        let sampleCount: Int
        let p50Milliseconds: Double
        let p95Milliseconds: Double
        let confirmedP95Milliseconds: Double?
        let provisionalFrames: Int
        let confirmedFrames: Int
        let renderAdmissions: Int
        let crossfades: Int
        let thumbnailSwaps: Int
        let gridMounts: Int
        let bodyEvaluations: Int
        let mainActorBeforeSuspensionP95Milliseconds: Double
        let zeroPresentedTimeFallbacks: Int
        let budget: String
        let criteriaPassed: Bool

        init(
            _ context: ReportContext, _ benchmark: String,
            coldWarm: String, cacheState: String, sampleCount: Int, p50: Double, p95: Double,
            confirmedP95: Double?, provisionalFrames: Int, confirmedFrames: Int,
            renderAdmissions: Int, crossfades: Int, thumbnailSwaps: Int = 0, gridMounts: Int = 1,
            bodyEvaluations: Int, mainActor: Double, fallbacks: Int, budget: String,
            criteriaPassed: Bool
        ) {
            self.benchmark = benchmark
            source = context.source
            sourceFormat = context.sourceFormat
            sourceDimensions = context.sourceDimensions
            machine = context.machine
            osVersion = context.osVersion
            commit = context.commit
            viewportPoints = context.viewportPoints
            backingPixels = context.backingPixels
            coldWarmState = coldWarm
            self.cacheState = cacheState
            self.sampleCount = sampleCount
            p50Milliseconds = p50
            p95Milliseconds = p95
            confirmedP95Milliseconds = confirmedP95
            self.provisionalFrames = provisionalFrames
            self.confirmedFrames = confirmedFrames
            self.renderAdmissions = renderAdmissions
            self.crossfades = crossfades
            self.thumbnailSwaps = thumbnailSwaps
            self.gridMounts = gridMounts
            self.bodyEvaluations = bodyEvaluations
            mainActorBeforeSuspensionP95Milliseconds = mainActor
            zeroPresentedTimeFallbacks = fallbacks
            self.budget = budget
            self.criteriaPassed = criteriaPassed
        }
    }

    /// One Library → Edit selection, timed from before `selectCollectionImage` to the drawable
    /// callbacks recorded by the presentation session.
    private struct Handoff {
        let mainActorMilliseconds: Double
        let firstPixelMilliseconds: Double
        let confirmedMilliseconds: Double
        let provisionalFrames: Int
        let confirmedFrames: Int
        let renderAdmissions: Int
        let crossfades: Int
        let bodyEvaluations: Int
    }

    /// Run-wide values every record repeats.
    private struct ReportContext {
        let source: String
        let sourceFormat: String
        let sourceDimensions: String
        let machine: String
        let osVersion: String
        let commit: String
        let viewportPoints: String
        let backingPixels: String
    }

    func testReleaseLastKnownFrameBudgets() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["KROMORA_LAST_KNOWN_FRAME_BENCHMARK"] != nil,
            "set KROMORA_LAST_KNOWN_FRAME_BENCHMARK=1 in a logged-in Release capture"
        )
        let rawPath = environment["KROMORA_LAST_KNOWN_FRAME_RAW"] ?? "realworldtest/DSC01019.ARW"
        let rawURL = URL(
            fileURLWithPath: rawPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        .standardizedFileURL
        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw XCTSkip("RAW benchmark source is missing: \(rawURL.path)")
        }
        let enforcesBudgets = environment["KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS"] != nil
        let dimensions = try XCTUnwrap(Fixtures.storedSize(of: rawURL))
        let urls = try makeGridFixtures(count: Self.gridCellCount - 1)
        let sourceInGrid = tempDirectory.appendingPathComponent(rawURL.lastPathComponent)
        try FileManager.default.copyItem(at: rawURL, to: sourceInGrid)
        let model = makeAppViewModel(
            engine: RenderEngine(),
            libraryFolderURL: tempDirectory.appendingPathComponent("managed-library"),
            previewFrameStoreDirectory: tempDirectory.appendingPathComponent("last-known-frames")
        )
        let importSummary = model.openImages(urls: urls + [sourceInGrid])
        guard let importSummary,
            importSummary.imported + importSummary.duplicates == Self.gridCellCount
        else {
            throw XCTSkip(
                "The benchmark fixtures could not be imported: "
                    + (importSummary?.failureReasons.joined(separator: "; ") ?? "no result")
            )
        }

        let window = try await makeCaptureWindow(model: model)
        defer {
            window.orderOut(nil)
            window.close()
        }
        let backing = window.convertToBacking(window.contentView?.bounds ?? .zero).size
        let context = ReportContext(
            source: rawURL.lastPathComponent,
            sourceFormat: rawURL.pathExtension.lowercased(),
            sourceDimensions: "\(Int(dimensions.width))x\(Int(dimensions.height))",
            machine: Self.machineDescription(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            commit: Self.gitCommit(),
            viewportPoints:
                "\(Int(window.contentView?.bounds.width ?? 0))x\(Int(window.contentView?.bounds.height ?? 0))",
            backingPixels: "\(Int(backing.width))x\(Int(backing.height))"
        )

        // Metal reports presentedTime == 0 for a drawable the compositor skipped, and the surface
        // then withholds confirmation (and stops retrying after a bounded number of skips). A
        // composited-but-skipped frame would strand the session at "provisional", so use the same
        // capture-host clock as the other Release benchmarks, and report how often it was needed.
        var zeroPresentedTimeFallbacks = 0
        model.previewSurface.zeroPresentedTimeFallback = {
            zeroPresentedTimeFallbacks += 1
            return LiveEditTelemetryClock.now
        }

        // First visit hydrates the actual visible mosaic and warms its in-memory thumbnails.
        let coldGridStart = CACurrentMediaTime()
        let firstGridMount =
            RenderDiagnostics.snapshot.gridMounts
            - (model.navigation.isGrid ? 1 : 0)
        XCTAssertTrue(model.navigate(to: .grid))
        try await waitForVisibleGrid(model, window: window, mountedAfter: firstGridMount)
        let coldGridMS = milliseconds(since: coldGridStart)

        guard
            let rawIndex = model.collection.items.firstIndex(where: {
                $0.url?.lastPathComponent == sourceInGrid.lastPathComponent
            })
        else {
            throw XCTSkip("The real RAW must be inside the scanned collection folder")
        }
        // Start in Edit and wait for the confirmed drawable so the package preview store holds
        // the exact frame for this photo before the warm samples begin.
        _ = try await selectAndAwaitDrawables(model, window: window, index: rawIndex)
        try await settle(.milliseconds(300))
        let (frameStore, storedFrame) = try await storeExactWarmFrame(model: model)

        // Exact warm Edit: the stored frame is the right pixels, so no render is admitted.
        _ = try await returnToGrid(model, window: window)
        let exact = try await selectAndAwaitDrawables(model, window: window, index: rawIndex)
        let exactPassed = exact.renderAdmissions == 0 && exact.confirmedFrames == 1
        try emit(
            Report(
                context, "exact-warm-edit", coldWarm: "warm", cacheState: "exact stored preview",
                sampleCount: 1, p50: exact.firstPixelMilliseconds,
                p95: exact.firstPixelMilliseconds,
                confirmedP95: exact.confirmedMilliseconds,
                provisionalFrames: exact.provisionalFrames, confirmedFrames: exact.confirmedFrames,
                renderAdmissions: exact.renderAdmissions, crossfades: exact.crossfades,
                bodyEvaluations: exact.bodyEvaluations,
                mainActor: exact.mainActorMilliseconds, fallbacks: zeroPresentedTimeFallbacks,
                budget: "zero preview renders; one confirmed frame per sample",
                criteriaPassed: exactPassed
            ))
        XCTAssertTrue(exactPassed, "Exact warm Edit must use zero renders and one confirmed frame")

        // Stale warm Edit: the stored frame carries an edit signature that no longer matches, so
        // it can only be a provisional stand-in for one real render.
        try await storeStaleVariant(of: storedFrame, in: frameStore)
        _ = try await returnToGrid(model, window: window)
        let stale = try await selectAndAwaitDrawables(model, window: window, index: rawIndex)
        let stalePassed = stale.provisionalFrames == 1 && stale.confirmedFrames <= 1
        try emit(
            Report(
                context, "stale-warm-edit", coldWarm: "warm",
                cacheState: "stale saved edit signature", sampleCount: 1,
                p50: stale.firstPixelMilliseconds, p95: stale.firstPixelMilliseconds,
                confirmedP95: stale.confirmedMilliseconds,
                provisionalFrames: stale.provisionalFrames, confirmedFrames: stale.confirmedFrames,
                renderAdmissions: stale.renderAdmissions, crossfades: stale.crossfades,
                bodyEvaluations: stale.bodyEvaluations,
                mainActor: stale.mainActorMilliseconds, fallbacks: zeroPresentedTimeFallbacks,
                budget: "one provisional; at most one confirmed replacement per sample",
                criteriaPassed: stalePassed
            ))
        XCTAssertTrue(
            stalePassed,
            "Stale warm Edit must show one provisional and at most one confirmed frame"
        )

        // Warm Library → Edit handoffs. Each sample leaves Edit for the grid, waits for the grid
        // to mount and Edit to unmount, then selects the photo again, so the Edit surface really
        // remounts instead of reselecting a photo that is already on screen.
        let iterations = boundedIterations(environment)
        var handoffs: [Handoff] = []
        var editThumbnailSwaps = 0
        for _ in 0..<iterations {
            editThumbnailSwaps += try await returnToGrid(model, window: window).thumbnailSwaps
            handoffs.append(
                try await selectAndAwaitDrawables(model, window: window, index: rawIndex))
        }

        // Warm re-entry of a 30-cell grid is measured after its visible thumbnails have been
        // hydrated: from the navigation request to the first display pass with every visible
        // cell populated.
        var gridTimes: [Double] = []
        var gridThumbnailSwaps = 0
        var gridMounts = 0
        var gridBodyEvaluations = 0
        for _ in 0..<iterations {
            let mountsBefore = RenderDiagnostics.snapshot.gridMounts
            let bodiesBefore = bodyEvaluations()
            let grid = try await returnToGrid(model, window: window)
            gridTimes.append(grid.milliseconds)
            gridThumbnailSwaps += grid.thumbnailSwaps
            gridMounts += RenderDiagnostics.snapshot.gridMounts - mountsBefore
            gridBodyEvaluations += bodyEvaluations() - bodiesBefore
            _ = try await selectAndAwaitDrawables(model, window: window, index: rawIndex)
        }

        let gridPassed =
            gridTimes.count == iterations
            && gridMounts == iterations
            && percentile(gridTimes, 0.95) <= 100
        let gridReport = Report(
            context, "warm-30-cell-grid",
            coldWarm: "warm; cold hydration \(format(coldGridMS)) ms",
            cacheState: "visible thumbnails hydrated before warm samples",
            sampleCount: gridTimes.count, p50: percentile(gridTimes, 0.50),
            p95: percentile(gridTimes, 0.95), confirmedP95: nil,
            provisionalFrames: 0, confirmedFrames: 0, renderAdmissions: 0, crossfades: 0,
            thumbnailSwaps: gridThumbnailSwaps, gridMounts: gridMounts,
            bodyEvaluations: gridBodyEvaluations, mainActor: 0,
            fallbacks: zeroPresentedTimeFallbacks, budget: "p95 <= 100 ms",
            criteriaPassed: gridPassed
        )
        let firstPixels = handoffs.map(\.firstPixelMilliseconds)
        let mainActorTimes = handoffs.map(\.mainActorMilliseconds)
        let editPassed =
            handoffs.count == iterations
            && percentile(firstPixels, 0.95) <= 50
            && percentile(mainActorTimes, 0.95) <= 2
        let editReport = Report(
            context, "warm-edit-navigation", coldWarm: "warm",
            cacheState: "warm app and preview caches", sampleCount: handoffs.count,
            p50: percentile(firstPixels, 0.50), p95: percentile(firstPixels, 0.95),
            confirmedP95: percentile(handoffs.map(\.confirmedMilliseconds), 0.95),
            provisionalFrames: handoffs.reduce(0) { $0 + $1.provisionalFrames },
            confirmedFrames: handoffs.reduce(0) { $0 + $1.confirmedFrames },
            renderAdmissions: handoffs.reduce(0) { $0 + $1.renderAdmissions },
            crossfades: handoffs.reduce(0) { $0 + $1.crossfades },
            thumbnailSwaps: editThumbnailSwaps, gridMounts: handoffs.count,
            bodyEvaluations: handoffs.reduce(0) { $0 + $1.bodyEvaluations },
            mainActor: percentile(mainActorTimes, 0.95), fallbacks: zeroPresentedTimeFallbacks,
            budget: "correct-photo provisional p95 <= 50 ms; main-actor <= 2 ms",
            criteriaPassed: editPassed
        )
        try emit(gridReport)
        try emit(editReport)
        print(
            "LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=\(verdict(exactPassed)) "
                + "stale=\(verdict(stalePassed)) grid=\(verdict(gridPassed)) "
                + "edit=\(verdict(editPassed))"
        )
        if enforcesBudgets {
            XCTAssertTrue(gridPassed, "Warm 30-cell grid p95 must be <= 100 ms")
            XCTAssertTrue(
                editPassed, "Warm Edit first pixel p95 must be <= 50 ms with <= 2 ms main-actor"
            )
        }
    }

    // MARK: - Window

    /// Mounts the shipping ContentView in a titled window that WindowServer actually composites.
    /// xctest is a background process that only spins the run loop, so the app never finishes
    /// launching, never activates, and its window stays occluded unless the harness does both and
    /// then keeps draining AppKit's event queue (see `settle`).
    private func makeCaptureWindow(model: AppViewModel) async throws -> NSWindow {
        let app = NSApplication.shared
        guard app.setActivationPolicy(.regular) else {
            throw XCTSkip("Release drawable capture requires a regular GUI application")
        }
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1440, height: 1000),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: ContentView(viewModel: model))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.displayIfNeeded()

        let visibleDeadline = Date().addingTimeInterval(5)
        var turns = 0
        while !window.occlusionState.contains(.visible), Date() < visibleDeadline {
            try await settle(.milliseconds(10))
            turns += 1
            if turns.isMultiple(of: 25) {
                app.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        window.displayIfNeeded()
        guard window.occlusionState.contains(.visible) else {
            window.orderOut(nil)
            window.close()
            throw XCTSkip(
                "Release drawable capture requires an onscreen window (unlock the display and "
                    + "keep it awake); occlusionState=\(window.occlusionState.rawValue), "
                    + "isVisible=\(window.isVisible), keyWindow=\(window.isKeyWindow), "
                    + "appActive=\(app.isActive), activationPolicy=\(app.activationPolicy().rawValue)"
            )
        }
        return window
    }

    // MARK: - Warm frame fixtures

    /// Encodes the frame currently on screen into the package preview store under its exact
    /// signature, then reads it back so the stale variant can reuse its bytes.
    private func storeExactWarmFrame(
        model: AppViewModel
    ) async throws -> (LatestPreviewFrameStore, LatestPreviewFrameStore.Hit) {
        let frameStore = LatestPreviewFrameStore(
            directory: tempDirectory.appendingPathComponent("last-known-frames")
        )
        let source = try XCTUnwrap(model.admissionImageSource)
        let displayedImage = try XCTUnwrap(model.previewSurface.image)
        let previewRequest = RenderRequest(
            source: source, document: model.document, quality: .preview
        )
        guard
            let raster = await RenderEngine.shared.makeCanonicalPreviewRaster(
                displayedImage, space: previewRequest.space,
                longEdge: LatestPreviewFrameStore.canonicalLongEdge
            )
        else {
            throw XCTSkip("The displayed warm frame could not be encoded for the cache fixture")
        }
        let identity = source.portableIdentity
        await frameStore.enqueueWrite(
            PresentationFrame(
                metadata: PresentationFrameMetadata(
                    identity: identity, kind: .preview2048,
                    signature: FrameSignature(
                        source: identity, editHash: previewRequest.document.editHash,
                        look: previewRequest.lookSignature, workingSpace: previewRequest.space,
                        pixelEpoch: RenderPipeline.pixelEpoch
                    ),
                    geometry: PresentedGeometry(
                        crop: previewRequest.document.crop,
                        rotation: previewRequest.document.rotation,
                        orientedAspectRatio: Double(
                            displayedImage.extent.width / displayedImage.extent.height)
                    ),
                    rasterColorSpace: raster.rasterColorSpace,
                    perceptualDigest: raster.perceptualDigest, presentedAt: Date(),
                    pixelWidth: raster.pixelWidth, pixelHeight: raster.pixelHeight
                ),
                rasterData: raster.jpegData
            ))
        await frameStore.waitForPendingWrites()
        guard let storedFrame = await frameStore.read(for: identity) else {
            throw XCTSkip("The generated exact warm frame could not be reopened")
        }
        return (frameStore, storedFrame)
    }

    private func storeStaleVariant(
        of storedFrame: LatestPreviewFrameStore.Hit, in frameStore: LatestPreviewFrameStore
    ) async throws {
        let metadata = storedFrame.frame.metadata
        let signature = metadata.signature
        await frameStore.enqueueWrite(
            PresentationFrame(
                metadata: PresentationFrameMetadata(
                    identity: metadata.identity, kind: metadata.kind,
                    signature: FrameSignature(
                        source: signature.source, editHash: "krma742-stale-edit",
                        look: signature.look, workingSpace: signature.workingSpace,
                        pixelEpoch: signature.pixelEpoch
                    ),
                    geometry: metadata.geometry, rasterColorSpace: metadata.rasterColorSpace,
                    perceptualDigest: metadata.perceptualDigest,
                    presentedAt: metadata.presentedAt,
                    pixelWidth: metadata.pixelWidth, pixelHeight: metadata.pixelHeight
                ),
                rasterData: storedFrame.frame.rasterData
            ))
        await frameStore.waitForPendingWrites()
    }

    private func makeGridFixtures(count: Int) throws -> [URL] {
        try (0..<count).map { index in
            try Fixtures.writeJPEG(
                width: 160 + index, height: 120, orientation: 1,
                named: String(format: "grid-%02d.jpg", index), in: tempDirectory
            )
        }
    }

    // MARK: - Measured transitions

    /// Selects a photo from the Library grid and waits for the presentation session this
    /// selection created to confirm. Latencies are the session's own drawable-callback clock
    /// (which starts at the top of `selectCollectionImage`) re-based to a timestamp taken before
    /// the call, so there is no polling interval or sleep inside any reported number.
    private func selectAndAwaitDrawables(
        _ model: AppViewModel, window: NSWindow, index: Int
    ) async throws -> Handoff {
        let gridUnmounts = RenderDiagnostics.snapshot.gridUnmounts
        let rendersBefore = model.previewRenderAdmissionCountForDiagnostics
        let crossfadesBefore = model.previewSurface.crossfadeAdmissionCount
        let bodiesBefore = bodyEvaluations()
        let startUptime = DispatchTime.now().uptimeNanoseconds
        let mainActorStart = CACurrentMediaTime()
        model.selectCollectionImage(at: index)
        let mainActorMilliseconds = milliseconds(since: mainActorStart)
        print("LAST_KNOWN_FRAME_SELECTION_SYNC_MS \(mainActorMilliseconds)")

        try await waitForConfirmedPresentation(model, window: window, startedAt: startUptime)
        try await waitForGridUnmount(after: gridUnmounts)
        let session = try XCTUnwrap(model.presentationSessionForDiagnostics)
        let offset = Double(session.selectionUptime &- startUptime) / 1_000_000
        return Handoff(
            mainActorMilliseconds: mainActorMilliseconds,
            firstPixelMilliseconds: offset + (session.firstPixelLatencyMilliseconds ?? .infinity),
            confirmedMilliseconds: offset + (session.confirmedLatencyMilliseconds ?? .infinity),
            provisionalFrames: session.provisionalFrameCount,
            confirmedFrames: session.confirmedFrameCount,
            renderAdmissions: model.previewRenderAdmissionCountForDiagnostics - rendersBefore,
            crossfades: model.previewSurface.crossfadeAdmissionCount - crossfadesBefore,
            bodyEvaluations: bodyEvaluations() - bodiesBefore
        )
    }

    /// Navigates Edit → Library and returns once a newly mounted grid has every visible cell
    /// populated and one display pass has run. The elapsed time is the warm grid re-entry.
    private func returnToGrid(
        _ model: AppViewModel, window: NSWindow
    ) async throws -> (milliseconds: Double, thumbnailSwaps: Int) {
        let thumbnailsBefore = thumbnailSnapshot(model)
        let mountsBefore = RenderDiagnostics.snapshot.gridMounts
        let start = CACurrentMediaTime()
        XCTAssertTrue(model.navigate(to: .grid))
        try await waitForVisibleGrid(model, window: window, mountedAfter: mountsBefore)
        try XCTUnwrap(window.contentView).layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return (
            milliseconds(since: start),
            changedThumbnails(from: thumbnailsBefore, to: thumbnailSnapshot(model))
        )
    }

    // MARK: - Waiting

    private func waitForVisibleGrid(
        _ model: AppViewModel, window: NSWindow, mountedAfter previousMounts: Int
    ) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            try requireVisible(window)
            let visibleIDs = model.collection.visibleEditedThumbnailAssetIDs
            if RenderDiagnostics.snapshot.gridMounts > previousMounts
                && !visibleIDs.isEmpty
                && visibleIDs.allSatisfy({ id in
                    model.collection.items.first(where: { $0.id == id })?.thumbnail != nil
                })
            {
                return
            }
            try await settle(.milliseconds(1))
        }
        throw BenchmarkError.presentationTimedOut(
            "a newly mounted grid with hydrated visible cells did not appear before the deadline"
        )
    }

    private func waitForGridUnmount(after previousUnmounts: Int) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if RenderDiagnostics.snapshot.gridUnmounts > previousUnmounts { return }
            try await settle(.milliseconds(1))
        }
        throw BenchmarkError.presentationTimedOut(
            "LibraryGridView did not unmount after navigating to Edit"
        )
    }

    /// Waits for a drawable-confirmed session created at or after `startedAt`. Requiring a new
    /// session means a confirmation left over from the previous selection can never satisfy it.
    private func waitForConfirmedPresentation(
        _ model: AppViewModel, window: NSWindow, startedAt: UInt64
    ) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            try requireVisible(window)
            if let session = model.presentationSessionForDiagnostics,
                session.selectionUptime >= startedAt, session.state == .confirmed,
                model.previewState == .ready
            {
                return
            }
            try await settle(.milliseconds(1))
        }
        throw BenchmarkError.presentationTimedOut(
            "drawable confirmation timed out; renderAdmissions="
                + "\(model.previewRenderAdmissionCountForDiagnostics), "
                + "appActive=\(NSApp.isActive), occlusion=\(window.occlusionState.rawValue), "
                + "key=\(window.isKeyWindow), navLoading=\(model.isNavigationLoading), "
                + "mode=\(model.navigation.mode), state=\(model.previewState), "
                + "status=\(model.statusMessage), "
                + "session=\(String(describing: model.presentationSessionForDiagnostics))"
        )
    }

    /// Sleeps while draining AppKit's event queue. A real app's `NSApplication.run()` does this
    /// continuously; xctest does not, and without it the app never activates and its windows
    /// stay occluded, so drawable callbacks never present.
    private func settle(_ duration: Duration) async throws {
        pumpAppKitEvents()
        try await Task.sleep(for: duration)
        pumpAppKitEvents()
    }

    private func pumpAppKitEvents() {
        while let event = NSApp.nextEvent(
            matching: .any, until: .distantPast, inMode: .default, dequeue: true
        ) {
            NSApp.sendEvent(event)
        }
    }

    private func requireVisible(_ window: NSWindow) throws {
        guard window.occlusionState.contains(.visible) else {
            throw XCTSkip(
                "Drawable capture stopped because its window is no longer onscreen (the display "
                    + "locked or slept, or another window covered it); "
                    + "occlusionState=\(window.occlusionState.rawValue)"
            )
        }
    }

    // MARK: - Reporting

    private func boundedIterations(_ environment: [String: String]) -> Int {
        let requested = Int(environment["KROMORA_LAST_KNOWN_FRAME_ITERATIONS"] ?? "30") ?? 30
        return min(100, max(5, requested))
    }

    private func emit(_ report: Report) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = String(decoding: try encoder.encode(report), as: UTF8.self)
        print("LAST_KNOWN_FRAME_BENCHMARK \(line)")
        guard let path = ProcessInfo.processInfo.environment["KROMORA_LAST_KNOWN_FRAME_REPORT"]
        else { return }
        let url = URL(fileURLWithPath: path)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    private func verdict(_ passed: Bool) -> String { passed ? "PASS" : "FAIL" }

    private func bodyEvaluations() -> Int {
        let snapshot = RenderDiagnostics.snapshot
        return snapshot.contentViewBodyEvaluations + snapshot.inspectorBodyEvaluations
            + snapshot.gridBodyEvaluations + snapshot.toolbarBodyEvaluations
    }

    private func thumbnailSnapshot(_ model: AppViewModel) -> [PhotoAssetID: ObjectIdentifier] {
        Dictionary(
            uniqueKeysWithValues: model.collection.items.compactMap { item in
                item.thumbnail.map { (item.id, ObjectIdentifier($0)) }
            })
    }

    private func changedThumbnails(
        from before: [PhotoAssetID: ObjectIdentifier],
        to after: [PhotoAssetID: ObjectIdentifier]
    ) -> Int {
        before.reduce(into: 0) { swaps, entry in
            if let current = after[entry.key], current != entry.value { swaps += 1 }
        }
    }

    /// Nearest-rank percentile: with 30 samples p95 is the 29th smallest value.
    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .infinity }
        let rank = Int((percentile * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    private func milliseconds(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1_000
    }

    private func format(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func machineDescription() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        return String(
            decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
            as: UTF8.self)
    }

    private static func gitCommit() -> String {
        if let commit = ProcessInfo.processInfo.environment["KROMORA_GIT_COMMIT"] { return commit }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "unknown" }
        process.waitUntilExit()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        )
        let commit = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit.isEmpty ? "unknown" : commit
    }
}
