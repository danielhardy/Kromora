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
        _ = viewModel.openImages(urls: [source])
        let deadline = Date().addingTimeInterval(5)
        while viewModel.collection.items.first?.thumbnail == nil {
            if Date() > deadline { XCTFail("the visible grid thumbnail did not arrive"); break }
            try await Task.sleep(for: .milliseconds(10))
        }

        for appearance in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: LibraryGridView(
                collection: viewModel.collection, viewModel: viewModel, onOpen: {}
            ).environment(\.colorScheme, appearance))
            renderer.proposedSize = ProposedViewSize(width: 720, height: 560)
            let image = try XCTUnwrap(renderer.cgImage, "appearance \(appearance)")
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertGreaterThan(image.height, 0)
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
        XCTAssertEqual(
            collection.thumbnailEntries.first?.aspectRatio ?? 0,
            0.75,
            accuracy: 0.001,
            "the grid mosaic must see the oriented aspect as soon as metadata settles"
        )
        XCTAssertEqual(collection.thumbnailEntries.first?.aspectResolved, true)
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
            collection.thumbnailEntries.first?.aspectRatio ?? 0,
            0.75,
            accuracy: 0.001,
            "selecting the photo must not change its portrait framing geometry"
        )
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
}
