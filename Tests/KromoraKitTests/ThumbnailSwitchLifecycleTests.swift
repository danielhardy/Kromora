import XCTest
@testable import KromoraKit

@MainActor
final class ThumbnailSwitchLifecycleTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "published state did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func loadCollection(
        _ viewModel: AppViewModel,
        first: URL,
        second: URL
    ) async throws {
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertEqual(viewModel.collection.items.map(\.url), [first, second])
    }

    func testEditedThumbnailUsesCurrentDocumentAndIsSharedByBrowsingSurfaces() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "edited-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "edited-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)
        viewModel.collection.beginThumbnailDemand()

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first photo") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
        }
        let firstThumbnailRequestCount = await engine.thumbnailRequests.filter {
            $0.quality == .thumbnail && $0.assetID == viewModel.collection.items[0].id
        }.count

        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.8)] }
        try await waitUntil("the edited thumbnail refresh") {
            await engine.thumbnailRequests.filter {
                $0.quality == .thumbnail && $0.assetID == viewModel.collection.items[0].id
            }.count > firstThumbnailRequestCount
        }

        let thumbnailRequests = await engine.thumbnailRequests.filter {
            $0.quality == .thumbnail && $0.assetID == viewModel.collection.items[0].id
        }
        XCTAssertEqual(thumbnailRequests.last?.document.adjustments, [.exposure(ev: 0.8)])
        // The waiter above observes request admission, not publication: under parallel load the
        // completed bitmap can still be in flight when the request is already recorded (LUMO-321).
        // Wait for the published state this test actually means — the shared edited bitmap —
        // rather than asserting it exactly once.
        try await waitUntil("the published edited thumbnail") {
            viewModel.collection.items[0].thumbnail != nil
                && viewModel.collection.items[0].editedThumbnailRevision != nil
        }

        // Navigation demands a second photo through the same collection path. Its request is
        // independent, while the first photo's completed edited bitmap remains shared by every
        // consumer that observes the Item (filmstrip and grid).
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the second photo") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: -0.4)] }
        try await waitUntil("the second photo edited thumbnail") {
            await engine.thumbnailRequests.contains {
                $0.quality == .thumbnail && $0.assetID == viewModel.collection.items[1].id
            }
        }
    }

    func testDebouncedEditBurstCoalescesToOneTrailingThumbnail() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "burst.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "burst-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the burst photo") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
        }
        let assetID = viewModel.collection.items[0].id
        let initialThumbnailCount = await engine.thumbnailRequests.filter {
            $0.assetID == assetID
        }.count

        for step in 1...10 {
            viewModel.updateDocument(debounced: true) {
                $0.adjustments = [.exposure(ev: Double(step) / 10.0)]
            }
        }

        try await waitUntil("the trailing burst thumbnail") {
            await engine.thumbnailRequests.contains {
                $0.assetID == assetID && $0.document.adjustments == [.exposure(ev: 1.0)]
            }
        }

        let thumbnails = await engine.thumbnailRequests.filter { $0.assetID == assetID }
        XCTAssertEqual(
            thumbnails.count - initialThumbnailCount, 1,
            "a ten-tick edit burst should submit one trailing thumbnail render"
        )
        XCTAssertEqual(thumbnails.last?.document.adjustments, [.exposure(ev: 1.0)])
    }

    func testEditedThumbnailSkipsPreviewInteractionAndRunsOnceAfterItEnds() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "interaction.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "interaction-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the interaction photo") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
        }
        let assetID = viewModel.collection.items[0].id
        let initialThumbnailCount = await engine.thumbnailRequests.filter {
            $0.assetID == assetID
        }.count

        viewModel.beginPreviewInteraction()
        for step in 1...10 {
            viewModel.updateDocument(debounced: true) {
                $0.adjustments = [.exposure(ev: Double(step) / 10.0)]
            }
        }
        await Task.yield()
        let thumbnailCountDuringInteraction = await engine.thumbnailRequests.filter {
            $0.assetID == assetID
        }.count
        XCTAssertEqual(
            thumbnailCountDuringInteraction,
            initialThumbnailCount,
            "thumbnail work stays out of the interactive preview lane"
        )

        viewModel.endPreviewInteraction()
        try await waitUntil("the post-interaction thumbnail") {
            await engine.thumbnailRequests.contains {
                $0.assetID == assetID && $0.document.adjustments == [.exposure(ev: 1.0)]
            }
        }

        let thumbnails = await engine.thumbnailRequests.filter { $0.assetID == assetID }
        XCTAssertEqual(thumbnails.count - initialThumbnailCount, 1)
        XCTAssertEqual(thumbnails.last?.document.adjustments, [.exposure(ev: 1.0)])
    }

    func testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first presented photo") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }

        viewModel.isInspectorPresented = true
        try await waitUntil("the first histogram") { viewModel.histogram != nil }

        viewModel.selectCollectionImage(at: 1)
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the repeated second selection") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
                && viewModel.histogram != nil
        }

        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
        XCTAssertEqual(viewModel.histogramErrorMessage, nil)
        XCTAssertFalse(viewModel.isHistogramLoading)
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
        let requests = await engine.histogramRequests
        XCTAssertTrue(requests.last?.source?.backing == .url(second))
    }

    func testFilmstripSelectionKeepsOriginalComparisonInSync() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "comparison-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "comparison-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)
        viewModel.collection.beginThumbnailDemand()

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first comparison") {
            viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the first original comparison") {
            viewModel.originalPreviewSurface.image != nil
        }

        let previewCountBeforeSwitch = await engine.previewRequests.count
        await engine.gatePreviews()
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the second adjusted request") {
            await engine.previewRequests.count > previewCountBeforeSwitch
        }
        await engine.releaseNextPreview()
        try await waitUntil("the second original request") {
            await engine.previewRequests.count > previewCountBeforeSwitch + 1
        }
        await engine.releaseNextPreview()
        await engine.releasePreviews()
        try await waitUntil("the second comparison") {
            viewModel.sourceURL == second
                && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }

        let requests = await engine.previewRequests
        XCTAssertGreaterThanOrEqual(
            requests.filter { $0.source?.backing == .url(second) }.count, 2,
            "the selected thumbnail needs both an Adjusted and Original request"
        )
        XCTAssertTrue(requests.contains {
            $0.source?.backing == .url(second) && $0.document.isIdentity
        })
    }

    func testFilmstripSelectionSchedulesOriginalBeforeAdjustedDrawableConfirmation() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "drawable-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "drawable-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        viewModel.previewSurface.attachPresentationLifecycle()
        viewModel.isSideBySide = true
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first adjusted publication") {
            viewModel.sourceURL == first && viewModel.previewSurface.image != nil
        }
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the second original publication") {
            viewModel.sourceURL == second
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }

        let requests = await engine.previewRequests
        XCTAssertGreaterThanOrEqual(
            requests.filter { $0.source?.backing == .url(second) }.count, 2,
            "the selected thumbnail needs both an Adjusted and Original request"
        )
        XCTAssertTrue(requests.contains {
            $0.source?.backing == .url(second) && $0.document.isIdentity
        })
    }

    func testComparisonRequestsShareFitGeometryAcrossThumbnailDrivenOrientations() async throws {
        let landscape = try Fixtures.writeGradientPNG(
            width: 24, height: 16, named: "a-landscape.png", in: tempDirectory
        )
        let portrait = try Fixtures.writeGradientPNG(
            width: 16, height: 24, named: "b-portrait.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        viewModel.isSideBySide = true
        try await loadCollection(viewModel, first: landscape, second: portrait)

        for (index, image) in [landscape, portrait].enumerated() {
            viewModel.selectCollectionImage(at: index)
            try await waitUntil("the adjusted and original \(image.lastPathComponent) previews") {
                viewModel.sourceURL == image
                    && viewModel.previewSurface.image != nil
                    && viewModel.originalPreviewSurface.image != nil
            }
            XCTAssertEqual(
                viewModel.previewSurface.presentationImageExtent,
                viewModel.originalPreviewSurface.presentationImageExtent,
                "both visible panes must use the same virtual source bounds"
            )

            // Give the two panes distinct documents so the corresponding requests are unambiguous.
            viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
            try await waitUntil("the edited comparison for \(image.lastPathComponent)") {
                let requests = await engine.previewRequests
                return requests.contains {
                    $0.source?.backing == .url(image)
                        && !$0.document.isIdentity
                } && requests.contains {
                    $0.source?.backing == .url(image)
                        && $0.document.isIdentity
                }
            }

            let requests = await engine.previewRequests.filter {
                $0.source?.backing == .url(image)
            }
            let adjusted = try XCTUnwrap(requests.last(where: { !$0.document.isIdentity }))
            let original = try XCTUnwrap(requests.last(where: { $0.document.isIdentity }))
            XCTAssertEqual(adjusted.scale, original.scale)
            XCTAssertEqual(adjusted.sourceROI, original.sourceROI)
            XCTAssertEqual(
                adjusted.presentationImageExtent,
                original.presentationImageExtent,
                "both panes must use the same virtual source bounds for fit"
            )
        }
    }

    func testSequentialOpenPresentsReplacementWithoutAnotherUserAction() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "sequential-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "sequential-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        let viewModel = makeAppViewModel(engine: engine)

        viewModel.openImage(url: first)
        // One-off opens are copied into the managed library before rendering. Assert the durable
        // source identity while retaining the original filename as the photo under test.
        guard let firstManagedURL = viewModel.collection.items.first(where: {
            $0.displayName == "sequential-first"
        })?.url else {
            return XCTFail("one-off open should add the first managed-library item")
        }
        let firstPreview = try await TestSynchronization.nextEvent(from: reader, "the first preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(firstManagedURL)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        if case .previewCompleted(let request) = firstPreview {
            XCTAssertEqual(request.source?.backing, .url(firstManagedURL))
        }

        // Keep the replacement renderer in flight. The test releases only B and never performs a
        // second model/view action after that release, matching the reported spinner failure.
        await engine.gatePreviews()
        viewModel.openImage(url: second)
        guard let secondManagedURL = viewModel.collection.items.first(where: {
            $0.displayName == "sequential-second"
        })?.url else {
            return XCTFail("one-off open should add the second managed-library item")
        }
        _ = try await TestSynchronization.nextEvent(from: reader, "the second preview request") {
            if case .previewRequested(let request) = $0 {
                return request.source?.backing == .url(secondManagedURL)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        XCTAssertEqual(viewModel.previewState, .loading)
        XCTAssertFalse(viewModel.isLoading, "source preparation is complete while B renders")

        await engine.releaseNextPreview()
        _ = try await TestSynchronization.nextEvent(from: reader, "the second preview completion") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(secondManagedURL)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        XCTAssertFalse(viewModel.isLoading)
    }

    func testRapidThumbnailChangesCannotPublishAnObsoleteSourceOrHistogram() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        await engine.gateSourcePreparation()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        _ = try await TestSynchronization.nextEvent(from: reader, "the first source preparation") {
            if case .sourcePreparationStarted = $0 { return true }
            return false
        } diagnostics: {
            "source preparations=\(await engine.sourcePreparationCount)"
        }
        viewModel.selectCollectionImage(at: 1)
        await engine.releaseSourcePreparation()

        _ = try await TestSynchronization.nextEvent(from: reader, "the latest source preparation") {
            if case .sourcePreparationCompleted(let source, _) = $0 {
                return source.backing == .url(second)
            }
            return false
        } diagnostics: {
            "source preparations=\(await engine.sourcePreparationCount)"
        }
        let secondPreview = try await TestSynchronization.nextEvent(from: reader, "the latest preview") {
            if case .previewRequested(let request) = $0 {
                return request.source?.backing == .url(second)
            }
            return false
        } diagnostics: {
            "source preparations=\(await engine.sourcePreparationCount), previews=\(await engine.previewRequests.count)"
        }
        if case .previewRequested(let request) = secondPreview {
            _ = try await TestSynchronization.nextEvent(from: reader, "the latest preview completion") {
                if case .previewCompleted(let completed) = $0 { return completed == request }
                return false
            } diagnostics: {
                "previews=\(await engine.previewRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
            }
        }
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
        XCTAssertNotEqual(viewModel.sourceURL, first)

        await engine.gateHistogram()
        viewModel.isInspectorPresented = true
        _ = try await TestSynchronization.nextEvent(from: reader, "the current histogram request") {
            if case .histogramRequested(let request) = $0 {
                return request.source?.backing == .url(second)
            }
            return false
        } diagnostics: {
            "histogram requests=\(await engine.histogramRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        viewModel.selectCollectionImage(at: 0)
        await engine.releaseHistograms()

        _ = try await TestSynchronization.nextEvent(from: reader, "the first histogram completion") {
            if case .histogramCompleted(let request, let result) = $0 {
                return request.source?.backing == .url(first) && result != nil
            }
            return false
        } diagnostics: {
            "histogram requests=\(await engine.histogramRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        try await waitUntil("the first photo after the switch back") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.histogram != nil
        }
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
        let histogramRequests = await engine.histogramRequests
        XCTAssertTrue(histogramRequests.last?.source?.backing == .url(first))
    }

    func testDelayedAutoCompletionCannotMakeTheNextThumbnailReady() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "auto-first.png", in: tempDirectory
        )
        // Keep the sources pixel-distinct so the first photo's canonical preview cannot bypass the
        // gated renderer when the second photo is selected.
        let second = try Fixtures.writeClarityPNG(
            width: 16, height: 12, named: "auto-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        _ = try await TestSynchronization.nextEvent(from: reader, "the first photo preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(first)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        try await waitUntil("the first photo readiness") {
            viewModel.previewState == .ready && viewModel.canRunAutoAdjustment
        }

        await engine.gateHistogram()
        viewModel.runAutoAdjustment()
        _ = try await TestSynchronization.nextEvent(from: reader, "the delayed Auto analysis") {
            if case .histogramRequested(let request) = $0 {
                return request.source?.backing == .url(first)
            }
            return false
        } diagnostics: {
            "histogram requests=\(await engine.histogramRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }

        await engine.gatePreviews()
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the next photo source") { viewModel.sourceURL == second }
        XCTAssertEqual(viewModel.autoAdjustmentState, .unavailable(
            "Auto is available when the photo preview is ready."
        ))

        await engine.releaseHistograms()
        _ = try await TestSynchronization.nextEvent(from: reader, "the delayed Auto completion") {
            if case .histogramCompleted(let request, _) = $0 {
                return request.source?.backing == .url(first)
            }
            return false
        } diagnostics: {
            "histogram requests=\(await engine.histogramRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        XCTAssertEqual(viewModel.autoAdjustmentState, .unavailable(
            "Auto is available when the photo preview is ready."
        ), "the old analysis must not publish ready for the loading photo")
        XCTAssertFalse(viewModel.canRunAutoAdjustment)

        await engine.releasePreviews()
        _ = try await TestSynchronization.nextEvent(from: reader, "the next photo presentation") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(second)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count), revisions=\(await engine.renderRequests.map(\.requestRevision))"
        }
        try await waitUntil("the next photo presentation") {
            viewModel.previewState == .ready && viewModel.canRunAutoAdjustment
        }
        XCTAssertEqual(viewModel.previewState, .ready)
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
    }

    func testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "thumbnail-fence.png", in: tempDirectory
        )
        let second = try Fixtures.writeClarityPNG(
            width: 16, height: 12, named: "thumbnail-fence-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: image, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the thumbnail-fence photo") {
            viewModel.sourceURL == image && viewModel.previewState == .ready
        }

        await engine.gateThumbnails()
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.25)] }
        let firstAssetID = viewModel.collection.items[0].id
        _ = try await TestSynchronization.nextEvent(
            from: reader, "the first edited-thumbnail request"
        ) {
            if case .thumbnailRequested(let request) = $0 {
                return request.assetID == firstAssetID
                    && request.document.adjustments == [.exposure(ev: 0.25)]
            }
            return false
        } diagnostics: {
            "thumbnail requests=\(await engine.thumbnailRequests.count), "
                + "asset=\(firstAssetID.raw)"
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.75)] }
        await engine.releaseThumbnails()
        _ = try await TestSynchronization.nextEvent(
            from: reader, "the obsolete thumbnail completion"
        ) {
            if case .thumbnailCompleted(let request) = $0 {
                return request.document.adjustments == [.exposure(ev: 0.25)]
            }
            return false
        } diagnostics: {
            "thumbnail requests=\(await engine.thumbnailRequests.count), "
                + "revisions=\(await engine.thumbnailRequests.map(\.requestRevision))"
        }
        await Task.yield()
        XCTAssertNil(
            viewModel.collection.items[0].editedThumbnailRevision,
            "a late thumbnail must not publish after the document revision changes"
        )

        try await waitUntil("the trailing current-document thumbnail") {
            viewModel.collection.items[0].editedThumbnailRevision != nil
        }
        let thumbnailRequests = await engine.thumbnailRequests
        XCTAssertEqual(
            thumbnailRequests.last?.document.adjustments,
            [.exposure(ev: 0.75)],
            "the trailing thumbnail must use the current document"
        )
    }

    func testLibraryGridHandoffPresentsTheSelectedPhotoWithoutTabSwitching() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await loadCollection(viewModel, first: first, second: second)

        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.selectLibraryItem(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))

        try await waitUntil("the selected grid photo and histogram") {
            viewModel.collection.selection.activeID == viewModel.collection.items[1].id
                && viewModel.sourceURL == second
                && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertNil(viewModel.histogramErrorMessage)
        XCTAssertFalse(viewModel.isHistogramLoading)
    }

    func testFailedSourceAndFailedHistogramLeaveTerminalStates() async throws {
        let missing = tempDirectory.appendingPathComponent("missing.png")
        let sourceEngine = FakeRenderEngine()
        let sourceViewModel = makeAppViewModel(engine: sourceEngine)
        sourceViewModel.openImage(url: missing)

        try await waitUntil("the source failure") {
            sourceViewModel.previewState == .failed && !sourceViewModel.isLoading
        }
        XCTAssertNil(sourceViewModel.sourceImage)
        XCTAssertNotNil(sourceViewModel.errorMessage)

        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "histogram-failure.png", in: tempDirectory
        )
        let histogramEngine = FakeRenderEngine()
        await histogramEngine.setShouldFailHistogram(true)
        let histogramViewModel = makeAppViewModel(engine: histogramEngine)
        histogramViewModel.openImage(url: image)
        try await waitUntil("the image presentation") {
            histogramViewModel.previewState == .ready
        }
        histogramViewModel.isInspectorPresented = true
        try await waitUntil("the histogram failure") {
            !histogramViewModel.isHistogramLoading
                && histogramViewModel.histogramErrorMessage != nil
        }
        XCTAssertNil(histogramViewModel.histogram)
    }

    /// KRMA-308's `refreshMaterializedEditedThumbnails()` re-requests every item that already has a
    /// materialized edited thumbnail after a Look-folder scan, independent of the edit debounce path
    /// above. `applyEditedThumbnail` early-returns when the revision is unchanged (`ImageCollection.swift`),
    /// so a real refresh must be observed as both a revision change and a new published `NSImage`
    /// instance — a no-op would leave both untouched.
    func testEditAndLUTFolderScanRefreshBothUpdateTheMaterializedEditedThumbnail() async throws {
        let photoFolder = tempDirectory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let source = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "refresh.png", in: photoFolder
        )
        let lookFolder = tempDirectory.appendingPathComponent("looks")
        try FileManager.default.createDirectory(at: lookFolder, withIntermediateDirectories: true)

        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        viewModel.library.setFolder(lookFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        viewModel.openImage(url: source)
        try await waitUntil("the source photo") { viewModel.sourceName == "refresh.png" }

        // Reference a Look file that does not exist in the folder yet, so the reference starts
        // unresolved (mirrors LUTWorkflowTests' "missing reference" pattern) and the later scan is
        // what resolves it, not the edit itself.
        let missingLUTURL = lookFolder.appendingPathComponent("Refresh Look.cube")
        viewModel.updateDocument {
            $0.lut.lutID = LUTID(raw: missingLUTURL.path)
            $0.lut.intensity = 1
            $0.adjustments = [.exposure(ev: 0.5)]
        }

        try await waitUntil("the first edited thumbnail") {
            viewModel.collection.items[0].thumbnail != nil
                && viewModel.collection.items[0].editedThumbnailRevision != nil
        }
        let firstRevision = try XCTUnwrap(viewModel.collection.items[0].editedThumbnailRevision)
        XCTAssertTrue(
            firstRevision.hasSuffix(":unresolved"),
            "an unresolved Look reference must not be mistaken for a resolved fingerprint"
        )
        let firstThumbnail = viewModel.collection.items[0].thumbnail

        // Now the Look file appears in the folder, and a folder scan (not an edit) is the only
        // thing that resolves it.
        _ = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Refresh Look.cube", in: lookFolder
        )
        viewModel.library.scan(lookFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        try await waitUntil("the LUT-scan-refreshed edited thumbnail") {
            if let revision = viewModel.collection.items[0].editedThumbnailRevision {
                return revision != firstRevision
            }
            return false
        }
        let secondRevision = try XCTUnwrap(viewModel.collection.items[0].editedThumbnailRevision)
        XCTAssertFalse(
            secondRevision.hasSuffix(":unresolved"),
            "resolving the Look via a folder scan must bump the materialized revision"
        )
        XCTAssertTrue(
            viewModel.collection.items[0].thumbnail !== firstThumbnail,
            "a resolved refresh must publish a newly materialized thumbnail, not reuse the stale one"
        )
    }
}
