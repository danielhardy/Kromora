import AppKit
import SwiftUI
import XCTest
@testable import KromoraKit

@MainActor
final class LibraryGridTests: TempDirectoryTestCase {
    func testCellsStayWithinRangeAtEveryWidthAndAcrossColumnTransitions() {
        let layout = LibraryGridLayout()

        // Sweep every width from one minimum cell up to a very wide window.
        var previousColumns = 1
        for width in stride(from: 200.0, through: 4_000.0, by: 1.0) {
            let metrics = layout.metrics(for: width)
            XCTAssertGreaterThanOrEqual(metrics.cellEdge, 200 - 0.001, "width \(width)")
            XCTAssertLessThanOrEqual(metrics.cellEdge, 300, "width \(width)")
            XCTAssertGreaterThanOrEqual(metrics.columns, previousColumns, "width \(width)")
            previousColumns = metrics.columns
            let used = metrics.cellEdge * Double(metrics.columns)
                + layout.spacing * Double(metrics.columns - 1)
            XCTAssertLessThanOrEqual(used, width + 0.001, "cells must not overflow the row")
        }

        // Both sides of the first transitions: the old rounding gave 171 pt at 354 and 192 at 600.
        XCTAssertEqual(layout.metrics(for: 354).columns, 1)
        XCTAssertEqual(layout.metrics(for: 354).cellEdge, 300)
        XCTAssertEqual(layout.metrics(for: 411).columns, 1)
        XCTAssertEqual(layout.metrics(for: 412).columns, 2)
        XCTAssertEqual(layout.metrics(for: 412).cellEdge, 200)
        XCTAssertEqual(layout.metrics(for: 600).columns, 2)
        XCTAssertEqual(layout.metrics(for: 623).columns, 2)
        XCTAssertEqual(layout.metrics(for: 624).columns, 3)
        XCTAssertEqual(layout.metrics(for: 624).cellEdge, 200)
    }

    func testNarrowAndDegenerateWidthsKeepOneColumn() {
        let layout = LibraryGridLayout()
        XCTAssertEqual(layout.metrics(for: 0).columns, 1)
        XCTAssertEqual(layout.metrics(for: 120).columns, 1)
        XCTAssertEqual(layout.metrics(for: 120).cellEdge, 120)
        XCTAssertEqual(layout.metrics(for: 900).columns, 4)
        XCTAssertLessThanOrEqual(layout.metrics(for: 100_000).cellEdge, layout.maximumCellEdge)
    }

    func testLibraryThumbnailPixelsCoverRetinaSquareFillAcrossCommonAspectRatios() {
        let layout = LibraryGridLayout()
        for ratio in [16.0 / 9.0, 2.0, 9.0 / 16.0, 0.5] {
            let shortSide = Double(PlatformThumbnailProvider.libraryMaxPixelSize)
                / max(ratio, 1.0 / ratio)
            XCTAssertGreaterThanOrEqual(
                shortSide, layout.maximumCellEdge * 2, "aspect ratio \(ratio)"
            )
        }
    }

    func testLibraryGridRendersInLightAndDarkAppearances() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 1_200, height: 600, named: "grid-render.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        await viewModel.openImagesAndWait(urls: [source])
        let deadline = Date().addingTimeInterval(5)
        while viewModel.collection.items.first?.thumbnail == nil {
            if Date() > deadline { XCTFail("the visible grid thumbnail did not arrive"); break }
            try await Task.sleep(for: .milliseconds(10))
        }

        for appearance in [ColorScheme.light, .dark] {
            let hosting = NSHostingView(rootView: LibraryGridView(
                collection: viewModel.collection, viewModel: viewModel, onOpen: { _ in }
            ).environment(\.colorScheme, appearance))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.appearance = NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
            window.contentView = hosting
            hosting.frame = window.contentView?.bounds ?? .zero
            window.layoutIfNeeded()
            window.displayIfNeeded()
            Self.pumpRunLoop()
            window.layoutIfNeeded()
            window.displayIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            // ImageRenderer only paints this ScrollView's chrome without hosting its lazy rows.
            // Check real pixels inside the tile and outside it for both appearances.
            let tile = try XCTUnwrap(bitmap.colorAt(x: 100, y: 200)?.usingColorSpace(.deviceRGB))
            let background = try XCTUnwrap(bitmap.colorAt(x: 300, y: 200)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(tile.redComponent - tile.greenComponent, 0.2)
            if appearance == .light {
                XCTAssertGreaterThan(background.redComponent, 0.7)
            } else {
                XCTAssertLessThan(background.redComponent, 0.3)
            }
        }
        await viewModel.shutdown()
    }

    func testPackedThumbnailKeysEmbedTheRasterSize() throws {
        let assetID = PortablePhotoAssetID()
        let size = PlatformThumbnailProvider.libraryMaxPixelSize
        XCTAssertTrue(try XCTUnwrap(ThumbnailFrameStore.key(.original, for: assetID)).hasSuffix("-o\(size)"))
        XCTAssertTrue(try XCTUnwrap(ThumbnailFrameStore.key(.edited, for: assetID)).hasSuffix("-e\(size)"))
    }

    func testRowHeightIsIndependentOfItemContent() {
        let layout = LibraryGridLayout()
        let metrics = layout.metrics(for: 1_000)
        XCTAssertEqual(layout.rowHeight(for: metrics), metrics.cellEdge + LibraryGridLayout.captionBlock)
        XCTAssertEqual(layout.rowCount(itemCount: 0, columns: metrics.columns), 0)
        XCTAssertEqual(layout.rowCount(itemCount: metrics.columns, columns: metrics.columns), 1)
        XCTAssertEqual(layout.rowCount(itemCount: metrics.columns + 1, columns: metrics.columns), 2)
    }

    func testInvalidAspectRatiosUseStablePhotographicFallback() {
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(.nan), 4.0 / 3.0)
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(.infinity), 4.0 / 3.0)
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(0), 4.0 / 3.0)
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(10), 3.0)
    }

    func testPresentedAspectRatioUsesCropPixelsAndKeepsIdentitySourceAspect() {
        let sourceAspect = 3.0 / 2.0
        let portraitCrop = CropAdjustments(
            normalizedRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1)
        )

        XCTAssertEqual(
            LibraryGridLayout.presentedAspectRatio(
                sourceAspectRatio: sourceAspect, crop: portraitCrop
            ),
            0.75,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            LibraryGridLayout.presentedAspectRatio(
                sourceAspectRatio: sourceAspect, crop: .neutral
            ),
            sourceAspect,
            accuracy: 0.000_001
        )
    }

    func testPresentedAspectRatioAppliesDocumentRotationBeforeCrop() {
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4)
        )

        XCTAssertEqual(
            LibraryGridLayout.presentedAspectRatio(
                sourceAspectRatio: 3.0 / 2.0, crop: crop, rotation: .clockwise90
            ),
            4.0 / 3.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            LibraryGridLayout.presentedAspectRatio(
                sourceAspectRatio: 3.0 / 2.0, crop: .neutral, rotation: .counterClockwise90
            ),
            2.0 / 3.0,
            accuracy: 0.000_001
        )
    }

    func testProjectedEntryResolvesByStableIDWhenItsIndexIsStale() async throws {
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }

        let collection = makeTestCollection()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        let entry = try XCTUnwrap(collection.thumbnailEntries.dropFirst().first)
        let expectedID = try XCTUnwrap(entry.itemIndex.map { collection.items[$0].id })

        // Simulate SwiftUI retaining a row while an earlier item disappears. The projected index
        // is now stale, but the entry's stable ID still identifies the correct current item.
        collection.items.removeFirst()

        let resolved = try XCTUnwrap(collection.resolvedItem(for: entry))
        XCTAssertEqual(resolved.index, 0)
        XCTAssertEqual(resolved.item.id, expectedID)
    }

    /// The package stores no pixel dimensions, so an unedited photo starts on the 4:3 presented
    /// ratio until its persisted original thumbnail supplies the oriented ratio it was made with.
    func testStoredOriginalGeometryResolvesAnUnresolvedCellWithoutOverridingKnownShapes() throws {
        let geometry = PresentedGeometry(
            crop: CropAdjustments(), rotation: .zero, orientedAspectRatio: 1.5
        )
        let item = ImageCollection.Item(
            url: tempDirectory.appendingPathComponent("unresolved.jpg"),
            displayName: "unresolved.jpg", imageData: nil
        )
        XCTAssertFalse(item.hasResolvedLibraryAspect)
        XCTAssertEqual(item.libraryAspectRatio, 4.0 / 3.0, accuracy: 1e-9)

        XCTAssertTrue(item.adoptStoredOriginalAspect(geometry))
        XCTAssertTrue(item.hasResolvedLibraryAspect)
        XCTAssertEqual(item.libraryAspectRatio, 1.5, accuracy: 1e-9)
        XCTAssertFalse(
            item.adoptStoredOriginalAspect(geometry), "a resolved cell must not be adopted twice"
        )

        // Pixel dimensions already known: the stored ratio must not replace them.
        let known = ImageCollection.Item(asset: PhotoAsset(
            source: PhotoAssetSource(data: Data([0x01]), id: PhotoAssetID(rawValue: "known")),
            filename: "known.jpg", fileType: "jpg",
            metadata: PhotoAssetMetadata(
                dimensions: PhotoPixelDimensions(width: 800, height: 1_000)
            ),
            presentedAspectRatio: nil
        ))
        XCTAssertFalse(known.adoptStoredOriginalAspect(geometry))
        XCTAssertEqual(known.libraryAspectRatio, 0.8, accuracy: 1e-9)

        // Live document geometry wins over a persisted frame.
        let live = ImageCollection.Item(
            url: tempDirectory.appendingPathComponent("live.jpg"),
            displayName: "live.jpg", imageData: nil
        )
        live.setPresentedCrop(CropAdjustments(), rotation: .zero)
        XCTAssertFalse(live.adoptStoredOriginalAspect(geometry))

        // A nonsensical stored ratio is ignored.
        let bad = ImageCollection.Item(
            url: tempDirectory.appendingPathComponent("bad.jpg"),
            displayName: "bad.jpg", imageData: nil
        )
        XCTAssertFalse(bad.adoptStoredOriginalAspect(PresentedGeometry(
            crop: CropAdjustments(), rotation: .zero, orientedAspectRatio: .nan
        )))
        XCTAssertFalse(bad.hasResolvedLibraryAspect)
    }

    func testEXIFPortraitKeepsItsFramingBeforeAndAfterSelection() async throws {
        try Fixtures.writeJPEG(
            width: 800, height: 600, orientation: 6,
            named: "initial-portrait.jpg", in: tempDirectory
        )

        let collection = makeTestCollection()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        let item = try XCTUnwrap(collection.items.first)
        XCTAssertEqual(item.libraryAspectRatio, 0.75, accuracy: 0.001)
        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [item.id])
        XCTAssertEqual(collection.thumbnailEntries.first?.itemIndex, 0)
        collection.requestThumbnail(for: item.id)
        let deadline = Date().addingTimeInterval(5)
        while item.thumbnail == nil {
            if Date() > deadline { return XCTFail("the portrait thumbnail did not arrive") }
            await Task.yield()
        }
        XCTAssertLessThan(item.thumbnail!.size.width, item.thumbnail!.size.height)

        collection.select(at: 0)

        XCTAssertEqual(collection.selection.activeID, item.id)
        XCTAssertEqual(
            collection.thumbnailEntries.map(\.id), [item.id],
            "selecting the photo must not change the square grid's entry identity"
        )
        XCTAssertEqual(item.libraryAspectRatio, 0.75, accuracy: 0.001)
        XCTAssertLessThan(item.thumbnail!.size.width, item.thumbnail!.size.height)
    }

    func testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding() async throws {
        for index in 0..<64 {
            try Fixtures.writeJPEG(
                width: 64,
                height: 48,
                orientation: 1,
                named: String(format: "photo-%03d.jpg", index),
                in: tempDirectory
            )
        }

        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 4
        ))
        let collection = makeTestCollection(scheduler: scheduler)
        collection.beginThumbnailDemand()
        // The folder compatibility fixture selects the first item after loading, which also
        // prepares adjacent filmstrip thumbnails. Keep this grid test unselected so only
        // materialized-cell demand can admit thumbnail work.
        collection.loadPortableAssets((0..<64).map { index in
            PhotoAsset(url: tempDirectory.appendingPathComponent(
                String(format: "photo-%03d.jpg", index)
            ))
        })
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.count, 64)
        XCTAssertTrue(
            collection.items.allSatisfy { $0.thumbnail == nil },
            "a virtualized grid must not decode every discovered cell before it appears"
        )

        let firstID = try XCTUnwrap(collection.items.first?.id)
        collection.requestThumbnail(for: firstID)

        let deadline = Date().addingTimeInterval(5)
        while collection.items.first?.thumbnail == nil {
            if Date() > deadline { return XCTFail("the materialized cell thumbnail did not arrive") }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(
            collection.items.dropFirst().allSatisfy { $0.thumbnail == nil },
            "requesting one materialized cell must not admit the rest of the folder"
        )
    }

    func testVisibleIndicesCoverTheViewportAndPrefetchWithoutTheWholeLibrary() {
        let layout = LibraryGridLayout(prefetchRows: 1)
        let width = 900.0
        let columns = layout.metrics(for: width).columns
        let pitch = layout.rowHeight(for: layout.metrics(for: width)) + layout.spacing

        let firstScreen = layout.visibleIndices(
            itemCount: 1_000, width: width, viewportHeight: pitch * 2, scrollOffset: 0
        )
        XCTAssertEqual(firstScreen.lowerBound, 0)
        XCTAssertEqual(
            firstScreen.upperBound, columns * 4,
            "the first screen admits the intersecting rows plus one prefetch row"
        )

        let scrolled = layout.visibleIndices(
            itemCount: 1_000, width: width, viewportHeight: pitch * 2, scrollOffset: pitch * 10
        )
        XCTAssertEqual(scrolled.lowerBound, columns * 9)
        XCTAssertLessThan(scrolled.count, 1_000 / 10)

        let tail = layout.visibleIndices(
            itemCount: 10, width: width, viewportHeight: pitch, scrollOffset: pitch * 100
        )
        XCTAssertEqual(tail.upperBound, 10, "scrolling past the end clamps to the last row")
        XCTAssertFalse(tail.isEmpty)
    }

    func testVisibleWindowLoadsEveryRequestedPhotoWithoutASelectionChange() async throws {
        for index in 0..<12 {
            try Fixtures.writeJPEG(
                width: 64, height: 48, orientation: 1,
                named: String(format: "photo-%03d.jpg", index), in: tempDirectory
            )
        }

        let collection = makeTestCollection()
        collection.beginThumbnailDemand()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()
        XCTAssertEqual(collection.items.count, 12)

        let visible = Array(collection.items.prefix(9).map(\.id))
        var demanded: [PhotoAssetID] = []
        collection.onThumbnailDemand = { id, _ in demanded.append(id) }
        collection.requestVisibleThumbnails(for: visible)

        let deadline = Date().addingTimeInterval(5)
        while Set(demanded) != Set(visible) || collection.items.prefix(9).contains(where: { $0.thumbnail == nil }) {
            if Date() > deadline {
                return XCTFail("the visible window did not admit every photo and its edited thumbnail")
            }
            await Task.yield()
        }

        XCTAssertEqual(Set(demanded), Set(visible))
        XCTAssertTrue(
            collection.items.dropFirst(9).allSatisfy {
                $0.thumbnail == nil && $0.asset.thumbnailState == .notRequested
            },
            "photos outside the visible window stay unloaded"
        )
    }

    /// KRMA-835: a cell that only ever showed an edited frame has no original raster. Reverting it
    /// to the original must load one instead of leaving the cell on a spinner.
    func testRevertingToOriginalLoadsTheOriginalRasterForACellThatNeverHadOne() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        let asset = PhotoAsset(url: tempDirectory.appendingPathComponent("edited.jpg"))
        collection.loadPortableWindow(
            assets: [asset], totalCount: 1, pageIndex: 0, pageSize: 1, query: .all
        )
        let item = try XCTUnwrap(collection.items.first)
        collection.applyEditedThumbnail(
            NSImage(cgImage: image, size: NSSize(width: 64, height: 48)),
            for: asset.id, revision: "edited")
        XCTAssertNotNil(item.thumbnail)
        XCTAssertNil(item.originalThumbnailForPresentation)

        collection.applyEditedThumbnail(nil, for: asset.id, revision: "identity")

        try await waitForThumbnails(in: collection, ids: [asset.id])
        XCTAssertNotNil(item.originalThumbnailForPresentation)
        await collection.shutdown()
    }

    func testRevertingToOriginalDoesNotReloadAnExistingOriginalRaster() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let providerCalls = LibraryGridThumbnailProviderCalls()
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in
            await providerCalls.record()
            return image
        })
        let asset = PhotoAsset(url: tempDirectory.appendingPathComponent("existing-original.jpg"))
        collection.loadPortableWindow(
            assets: [asset], totalCount: 1, pageIndex: 0, pageSize: 1, query: .all
        )
        let item = try XCTUnwrap(collection.items.first)
        try await waitForThumbnails(in: collection, ids: [asset.id])
        let original = try XCTUnwrap(item.originalThumbnailForPresentation)
        let callsBeforeRevert = await providerCalls.count

        collection.applyEditedThumbnail(
            NSImage(cgImage: image, size: NSSize(width: 64, height: 48)),
            for: asset.id, revision: "edited"
        )
        collection.applyEditedThumbnail(nil, for: asset.id, revision: "identity")
        await Task.yield()

        XCTAssertTrue(item.thumbnail === original)
        let callsAfterRevert = await providerCalls.count
        XCTAssertEqual(callsAfterRevert, callsBeforeRevert)
        await collection.shutdown()
    }

    /// KRMA-841: the id lookup used on every thumbnail arrival must stay correct across reloads
    /// and removals, because it is cached rather than recomputed.
    func testItemIndexLookupStaysCorrectAcrossReloadAndRemoval() {
        let collection = ImageCollection()
        let assets = (0..<6).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("lookup-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: assets, totalCount: 6, pageIndex: 0, pageSize: 6, query: .all)
        XCTAssertEqual(collection.itemIndex(for: assets[4].id), 4)

        collection.removeItems(with: [assets[1].id])
        XCTAssertNil(collection.itemIndex(for: assets[1].id))
        XCTAssertEqual(collection.itemIndex(for: assets[4].id), 3)

        collection.loadPortableWindow(
            assets: Array(assets.reversed()), totalCount: 6, pageIndex: 0, pageSize: 6, query: .all)
        XCTAssertEqual(collection.itemIndex(for: assets[4].id), 1)
        XCTAssertEqual(collection.itemIndex(for: assets[1].id), 4)
    }

    /// KRMA-841: a large cold library admits bounded decode work, and cells that leave the
    /// viewport drop their queued decode instead of leaving a stale queue behind.
    func testLargeColdLibraryBoundsDecodeWorkAndReleaseCancelsQueuedDecodes() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let scheduler = ImageWorkScheduler()
        let collection = ImageCollection(scheduler: scheduler, originalThumbnailProvider: { _, _, _, _, _, _, _ in
            try? await Task.sleep(for: .milliseconds(50))
            return image
        })
        let assets = (0..<400).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("cold-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: assets, totalCount: 400, pageIndex: 0, pageSize: 400, query: .all)
        collection.beginThumbnailDemand()
        let first = Array(assets[0..<60].map(\.id))
        collection.requestVisibleThumbnails(for: first)

        XCTAssertLessThanOrEqual(scheduler.runningThumbnailCount, 4)
        XCTAssertLessThanOrEqual(scheduler.pendingThumbnailCount, 24)

        for id in first { collection.releaseThumbnail(for: id) }
        XCTAssertEqual(scheduler.pendingThumbnailCount, 0, "released cells must not stay queued")
        await collection.shutdown()
    }

    func testPortableWindowReloadReRequestsPreviouslyVisibleThumbnails() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        let assets = (0..<11).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("photo-\($0).jpg"))
        }
        collection.beginThumbnailDemand()
        collection.loadPortableWindow(
            assets: Array(assets.prefix(8)), totalCount: 8, pageIndex: 0,
            pageSize: 8, query: .all
        )

        let visible = Array(assets.prefix(6).map(\.id))
        collection.requestVisibleThumbnails(for: visible)
        try await waitForThumbnails(in: collection, ids: visible)

        // Simulate import: surviving cells keep their ids and three new assets join the window.
        collection.loadPortableWindow(
            assets: assets, totalCount: assets.count, pageIndex: 0,
            pageSize: assets.count, query: .all
        )
        try await waitForThumbnails(in: collection, ids: visible)
        XCTAssertTrue(collection.items.dropFirst(6).allSatisfy { $0.thumbnail == nil })
        await collection.shutdown()
    }

    func testPortableWindowReloadPreservesFilmstripDemandIncludingPreparedAndCachedCells() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        let assets = (0..<11).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("photo-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: Array(assets.prefix(8)), totalCount: 8, pageIndex: 0,
            pageSize: 8, query: .all
        )
        collection.beginThumbnailDemand() // Prepares indices 0...2 without explicit cell demand.
        try await waitForThumbnails(in: collection, ids: Array(assets.prefix(3).map(\.id)))
        // A packed or edited frame may already have painted before a cell's onAppear.
        collection.items[5].setOriginalThumbnail(NSImage(cgImage: image, size: NSSize(width: 64, height: 48)))
        collection.items[5].asset.thumbnailState = .ready
        let visible = Array(assets.prefix(6).map(\.id))
        for id in visible { collection.requestThumbnail(for: id, priority: .adjacentFilmstrip) }
        try await waitForThumbnails(in: collection, ids: visible)

        collection.loadPortableWindow(
            assets: assets, totalCount: assets.count, pageIndex: 0,
            pageSize: assets.count, query: .all
        )
        try await waitForThumbnails(in: collection, ids: visible)
        XCTAssertTrue(collection.items.dropFirst(6).allSatisfy { $0.thumbnail == nil })
        await collection.shutdown()
    }

    func testPortableAppendRetainsDemandAndReloadDropsReleasedRemovedAndSpeculativeIDs() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        let assets = (0..<11).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("photo-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: Array(assets.prefix(8)), totalCount: 11, pageIndex: 0,
            pageSize: 8, query: .all
        )
        collection.beginThumbnailDemand()
        for index in 3...5 { collection.requestThumbnail(for: assets[index].id) }
        try await waitForThumbnails(in: collection, ids: Array(assets.prefix(6).map(\.id)))
        let retainedItem = collection.items[3]
        XCTAssertTrue(collection.appendPortableWindow(assets: Array(assets.suffix(3)), pageIndex: 1))
        XCTAssertTrue(collection.items[3] === retainedItem)
        XCTAssertNotNil(retainedItem.thumbnail)
        XCTAssertTrue(collection.items.suffix(3).allSatisfy { $0.thumbnail == nil })

        collection.releaseThumbnail(for: assets[4].id)
        let survivors = assets.filter { $0.id != assets[5].id }
        collection.loadPortableWindow(
            assets: survivors, totalCount: survivors.count, pageIndex: 0,
            pageSize: survivors.count, query: .all
        )
        try await waitForThumbnails(in: collection, ids: [assets[3].id])
        XCTAssertTrue(collection.items.filter { $0.id != assets[3].id }.allSatisfy { $0.thumbnail == nil })
        await collection.shutdown()
    }

    func testReleasingDecodedThumbnailDropsPixelsAndLaterPageKeepsNone() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        let assets = (0..<12).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("evict-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: Array(assets.prefix(8)), totalCount: 12, pageIndex: 0,
            pageSize: 8, query: .all
        )
        collection.beginThumbnailDemand()
        let far = assets[7].id
        collection.requestThumbnail(for: far)
        try await waitForThumbnails(in: collection, ids: [far])
        let item = collection.items[7]
        let edited = NSImage(cgImage: image, size: NSSize(width: 64, height: 48))
        item.applyEditedThumbnail(edited, revision: "r1")
        XCTAssertNotNil(item.originalThumbnailForPresentation)
        XCTAssertNotNil(item.editedThumbnailForPresentation)

        collection.releaseThumbnail(for: far)
        XCTAssertNil(item.thumbnail)
        XCTAssertNil(item.originalThumbnailForPresentation)
        XCTAssertNil(item.editedThumbnailForPresentation)
        XCTAssertNil(item.editedThumbnailRevision)
        XCTAssertEqual(item.id, far, "identity survives eviction")

        XCTAssertTrue(collection.appendPortableWindow(assets: Array(assets.suffix(4)), pageIndex: 1))
        XCTAssertTrue(collection.items[7] === item)
        XCTAssertTrue(collection.items.suffix(5).allSatisfy {
            $0.thumbnail == nil && $0.editedThumbnailForPresentation == nil
        })
        await collection.shutdown()
    }

    func testEvictedThumbnailRehydratesOnRevisit() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let frameStore = ThumbnailFrameStore(
            directory: tempDirectory.appendingPathComponent("revisit-frames")
        )
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        collection.thumbnailFrameStore = frameStore
        let assets = (0..<8).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("revisit-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: assets, totalCount: 8, pageIndex: 0, pageSize: 8, query: .all
        )
        collection.beginThumbnailDemand()
        let id = assets[7].id
        collection.requestThumbnail(for: id)
        try await waitForThumbnails(in: collection, ids: [id])
        let initialFrameReadCount = await frameStore.readCount
        collection.releaseThumbnail(for: id)
        XCTAssertNil(collection.items[7].thumbnail)
        collection.requestThumbnail(for: id)
        try await waitForThumbnails(in: collection, ids: [id])
        XCTAssertNotNil(collection.items[7].thumbnail)
        let revisitFrameReadCount = await frameStore.readCount
        XCTAssertGreaterThan(revisitFrameReadCount, initialFrameReadCount)
        await collection.shutdown()
        await frameStore.shutdown()
    }

    func testVisibleWindowReleaseDropsDecodedThumbnailsFromEarlierViewport() async throws {
        let image = try Fixtures.makeCGImage(width: 64, height: 48)
        let assets = (0..<40).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("window-\($0).jpg"))
        }
        let collection = ImageCollection(originalThumbnailProvider: { _, _, _, _, _, _, _ in image })
        collection.loadPortableWindow(
            assets: assets, totalCount: assets.count, pageIndex: 0,
            pageSize: assets.count, query: .all
        )
        collection.beginThumbnailDemand()
        let firstVisible = Array(assets.prefix(5).map(\.id))
        collection.requestVisibleThumbnails(for: firstVisible)
        try await waitForThumbnails(in: collection, ids: firstVisible)

        collection.focus(id: assets[32].id)
        let nextVisible = Array(assets[30..<35].map(\.id))
        collection.requestVisibleThumbnails(for: nextVisible)
        for id in firstVisible { collection.releaseThumbnail(for: id) }
        try await waitForThumbnails(in: collection, ids: nextVisible)

        for asset in assets.prefix(5) {
            XCTAssertNil(collection.items.first { $0.id == asset.id }?.thumbnail, asset.id.raw)
        }
        XCTAssertTrue(collection.items[30..<35].allSatisfy { $0.thumbnail != nil })
        await collection.shutdown()
    }

    private func waitForThumbnails(
        in collection: ImageCollection, ids: [PhotoAssetID]
    ) async throws {
        let wanted = Set(ids)
        let deadline = Date().addingTimeInterval(5)
        XCTAssertEqual(collection.items.filter { wanted.contains($0.id) }.count, wanted.count)
        while collection.items.contains(where: { wanted.contains($0.id) && $0.thumbnail == nil }) {
            if Date() > deadline {
                return XCTFail("previously visible thumbnails did not reach ready")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(collection.items.filter { wanted.contains($0.id) }.allSatisfy {
            $0.asset.thumbnailState == .ready
        })
    }

    func testScriptedScrollEvaluatesGridBodyOncePerRowCrossing() throws {
        let collection = ImageCollection()
        let assets = (0..<500).map {
            PhotoAsset(url: tempDirectory.appendingPathComponent("scroll-\($0).jpg"))
        }
        collection.loadPortableWindow(
            assets: assets, totalCount: 500, pageIndex: 0, pageSize: 500, query: .all)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let hosting = NSHostingView(rootView: LibraryGridView(
            collection: collection, viewModel: viewModel, onOpen: { _ in }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.layoutIfNeeded()
        Self.pumpRunLoop()
        let scrollView = try XCTUnwrap(Self.firstScrollView(in: hosting))
        let clip = scrollView.contentView

        RenderDiagnostics.reset()
        // The old GeometryReader preference re-ran the body every 24 pt (about 125 times for this
        // scroll); the coarse row tracking should stay near one pass per row crossing.
        let step = 4.0
        let maxOffset = 3_000.0
        var offset = 0.0
        while offset < maxOffset {
            offset += step
            clip.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(clip)
            Self.pumpRunLoop(seconds: 0.01)
        }
        Self.pumpRunLoop()
        let evaluations = RenderDiagnostics.snapshot.gridBodyEvaluations
        XCTAssertGreaterThan(clip.bounds.origin.y, maxOffset / 2, "the scripted scroll must move the content")
        XCTAssertGreaterThan(
            evaluations, 0,
            "crossing row boundaries must publish coarse scroll updates to the grid"
        )

        let layout = LibraryGridLayout()
        let metrics = layout.metrics(for: 720 - 32)
        let pitch = layout.rowHeight(for: metrics) + layout.spacing
        let rowCrossings = Int(maxOffset / pitch) + 1
        XCTAssertLessThanOrEqual(
            evaluations, rowCrossings * 4 + 10,
            "scrolling must re-run the grid body per row crossing, not per scroll tick"
        )
        window.contentView = nil
    }

    /// The grid's vertical scroller: the tallest scroll view (the culling bar hosts a small one).
    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ node: NSView) {
            if let scroll = node as? NSScrollView,
               (scroll.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) {
                best = scroll
            }
            node.subviews.forEach(visit)
        }
        visit(view)
        return best
    }

    private static func pumpRunLoop(seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

private actor LibraryGridThumbnailProviderCalls {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
final class LibraryGridRowWindowTests: XCTestCase {
    func testRowModelWorkStaysBoundedAcrossScriptedScrollOf10kItems() {
        let layout = LibraryGridLayout()
        let columns = 4
        let itemCount = 12_000
        let entries = (0..<itemCount).map {
            ImageCollection.ThumbnailEntry(
                id: PhotoAssetID(rawValue: "asset-\($0)"), itemIndex: $0)
        }
        let rowCount = layout.rowCount(itemCount: itemCount, columns: columns)
        let pitch = 250.0
        let viewport = 800.0
        var maxRows = 0
        var seen = Set<LibraryGridRowModel.ID>()
        for first in stride(from: 0, to: rowCount, by: 7) {
            let window = layout.rowWindow(
                rowCount: rowCount, firstVisibleRow: first, viewportHeight: viewport, pitch: pitch)
            let rows = LibraryGridRowModel.rows(in: window, itemCount: itemCount, columns: columns, entries: entries)
            maxRows = max(maxRows, rows.count)
            XCTAssertEqual(rows.first?.indices.lowerBound, window.lowerBound * columns)
            seen.formUnion(rows.map(\.id))
        }
        // visible (800/250 → 4, +1) plus two prefetch rows each side.
        XCTAssertLessThanOrEqual(maxRows, 5 + 2 * layout.prefetchRows + 1)
        XCTAssertLessThan(maxRows, rowCount / 100)
        // Identity is the first asset: stable regardless of which window produced the row.
        let end = layout.rowWindow(
            rowCount: rowCount, firstVisibleRow: rowCount - 1, viewportHeight: viewport, pitch: pitch)
        let tail = LibraryGridRowModel.rows(in: end, itemCount: itemCount, columns: columns, entries: entries)
        XCTAssertEqual(tail.last?.indices.upperBound, itemCount)
        XCTAssertEqual(layout.rowWindow(rowCount: 0, firstVisibleRow: 0, viewportHeight: viewport, pitch: pitch), 0..<0)
    }
}
