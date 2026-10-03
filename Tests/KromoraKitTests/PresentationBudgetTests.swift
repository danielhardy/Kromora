import AppKit
import XCTest

@testable import KromoraKit

@MainActor
final class PresentationBudgetTests: TempDirectoryTestCase {
    /// The exact persisted canvas raster is the one visible assignment for a warm open.
    private static let exactCanvasAssignments = 1
    /// A stale cached raster remains useful as first paint, then gets one current replacement.
    private static let staleCanvasAssignments = 2
    /// A cold open may show a thumbnail and a settled raster, with one extra source candidate.
    private static let coldCanvasAssignments = 3
    /// Crop-free edited cell replacement preserves the cell's already presented geometry.
    private static let cropFreeCellGeometryChanges = 0
    /// A Look content delta admits one replacement for each materialized photo that references it.
    private static let referencedLookRendersPerPhoto = 1

    private struct PhotoSeed {
        let name: String
        let exposure: Double
        var crop = CropAdjustments.neutral
        var lookID: LUTID?
    }

    private struct Fixture {
        let packageURL: URL
        let previewDirectory: URL
        let thumbnailDirectory: URL
        let looksDirectory: URL
        let assets: [PhotoAsset]
        let photos: [PhotoSeed]
        let documents: [String: EditDocument]

        func asset(named name: String) throws -> PhotoAsset {
            try XCTUnwrap(assets.first { $0.displayName == name })
        }

        func document(named name: String) throws -> EditDocument {
            try XCTUnwrap(documents[name])
        }
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 8,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() >= deadline {
                throw TestSynchronizationError.timedOut(description, "budget scenario did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeFixture(
        _ photos: [PhotoSeed], name: String,
        looksDirectory: URL? = nil
    ) async throws -> Fixture {
        let packageURL = tempDirectory.appendingPathComponent(
            "\(name).kromoralibrary", isDirectory: true
        )
        let previewDirectory = tempDirectory.appendingPathComponent("\(name)/Previews")
        let thumbnailDirectory = tempDirectory.appendingPathComponent("\(name)/Thumbnails")
        let effectiveLooksDirectory = looksDirectory
            ?? tempDirectory.appendingPathComponent("\(name)/Looks", isDirectory: true)
        try FileManager.default.createDirectory(
            at: effectiveLooksDirectory, withIntermediateDirectories: true
        )
        let sourceURLs = try photos.enumerated().map { index, photo in
            try Fixtures.writeGradientPNG(
                width: 64 + index, height: 48, named: photo.name, in: tempDirectory
            )
        }
        let package = try PortableLibrarySession(at: packageURL)
        _ = try package.importURLs(sourceURLs, duplicatePolicy: .importAnyway)
        let imported = try package.materializedAssets()
        let editStore = EditDocumentStore(package: package.package, lease: package.lease)
        var documents: [String: EditDocument] = [:]
        for photo in photos {
            var document = EditDocument()
            document.adjustments = [.exposure(ev: photo.exposure)]
            document.crop = photo.crop
            if let lookID = photo.lookID {
                document.lut = LUTSettings(lutID: lookID, intensity: 1)
            }
            documents[photo.name] = document
            let asset = try XCTUnwrap(imported.first { $0.displayName == photo.name })
            try await editStore.save(
                document,
                for: EditSourceReference(
                    assetID: asset.id,
                    portableIdentity: asset.source.portableIdentity,
                    url: asset.url
                )
            )
        }
        try package.refreshIndex()
        let assets = try package.materializedAssets()
        await package.shutdown()
        return Fixture(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: effectiveLooksDirectory,
            assets: assets, photos: photos, documents: documents
        )
    }

    private func makeViewModel(
        _ fixture: Fixture, engine: any RenderEngining,
        ledger: PresentationChangeLedger? = nil,
        sourceAssets: (PortableLibrarySession) throws -> [PhotoAsset] = { try $0.browsingAssets() }
    ) async throws -> (AppViewModel, PortableLibrarySession) {
        let session = try PortableLibrarySession(at: fixture.packageURL)
        let viewModel = makeAppViewModel(
            engine: engine, userLookFolderURL: fixture.looksDirectory,
            previewFrameStoreDirectory: fixture.previewDirectory,
            thumbnailFrameStoreDirectory: fixture.thumbnailDirectory,
            portablePackageURL: fixture.packageURL, portableLibrarySession: session
        )
        viewModel.previewSurface.presentationChangeLedger = ledger
        viewModel.collection.loadPortableAssets(try sourceAssets(session))
        if let ledger { viewModel.collection.installPresentationChangeLedger(ledger) }
        await viewModel.collection.scanCompletion()
        return (viewModel, session)
    }

    private func open(_ name: String, in viewModel: AppViewModel) async throws {
        let index = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.displayName == name }
        )
        let assetID = viewModel.collection.items[index].id
        viewModel.collection.setSelection(at: index)
        viewModel.openActiveCollectionImage()
        try await waitUntil("Edit open for \(name)") {
            viewModel.sourceName == name
                && viewModel.presentationSessionForDiagnostics?.assetID == assetID
                && viewModel.presentationSessionForDiagnostics?.state == .confirmed
        }
    }

    private func seedPreviewFrames(
        _ fixture: Fixture, editHashes: [String: String] = [:]
    ) async throws {
        let store = LatestPreviewFrameStore(directory: fixture.previewDirectory)
        for photo in fixture.photos {
            let asset = try fixture.asset(named: photo.name)
            let document = try fixture.document(named: photo.name)
            let frame = try FrameFixtures.frame(
                identity: asset.source.portableIdentity,
                edit: editHashes[photo.name] ?? document.editHash,
                space: .current, width: 64, height: 48,
                red: CGFloat((fixture.photos.firstIndex { $0.name == photo.name } ?? 0) + 1) / 8
            )
            await store.enqueueWrite(frame)
        }
        await store.waitForPendingWrites()
    }

    private func seedThumbnailFrames(
        _ fixture: Fixture, editedHashes: [String: String] = [:]
    ) async throws {
        let store = ThumbnailFrameStore(directory: fixture.thumbnailDirectory)
        for photo in fixture.photos {
            let asset = try fixture.asset(named: photo.name)
            let document = try fixture.document(named: photo.name)
            let identity = asset.source.portableIdentity
            let original = PresentationFrame(
                metadata: OriginalThumbnailSignature.signature(for: identity).metadata(
                    kind: .originalThumbnail480, width: 64, height: 48
                ),
                rasterData: try FrameFixtures.jpeg(width: 64, height: 48, red: 0.2)
            )
            let edited = PresentationFrame(
                metadata: FrameFixtures.metadata(
                    identity: identity,
                    edit: editedHashes[photo.name] ?? document.editHash,
                    look: .none, space: .current, kind: .editedThumbnail480,
                    width: 64, height: 48
                ),
                rasterData: try FrameFixtures.jpeg(width: 64, height: 48, red: 0.7)
            )
            await store.enqueueWrite(original)
            await store.enqueueWrite(edited)
        }
        await store.flush()
    }

    private func assertRasterSources(
        _ expected: [PresentationRasterSource], on surface: PresentationSurface,
        in ledger: PresentationChangeLedger, file: StaticString = #filePath, line: UInt = #line
    ) {
        let sources = ledger.changes(on: surface).compactMap { change -> PresentationRasterSource? in
            guard case .rasterAssignment(let source) = change.kind else { return nil }
            return source
        }
        XCTAssertEqual(
            sources, expected,
            "\(surface.description) raster budget failed. Ordered changes:\n\(ledger.diagnostic(for: surface))",
            file: file, line: line
        )
    }

    private func assertRasterAssignmentCount(
        _ expected: Int, on surface: PresentationSurface, in ledger: PresentationChangeLedger,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let count = ledger.changes(on: surface).filter {
            if case .rasterAssignment = $0.kind { return true }
            return false
        }.count
        XCTAssertEqual(
            count, expected,
            "\(surface.description) raster assignment budget failed. Ordered changes:\n\(ledger.diagnostic(for: surface))",
            file: file, line: line
        )
    }

    private func assertGeometryChangeCount(
        _ expected: Int, on surface: PresentationSurface, in ledger: PresentationChangeLedger,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let count = ledger.changes(on: surface).filter {
            if case .geometryChange = $0.kind { return true }
            return false
        }.count
        XCTAssertEqual(
            count, expected,
            "\(surface.description) geometry budget failed. Ordered changes:\n\(ledger.diagnostic(for: surface))",
            file: file, line: line
        )
    }

    func testExactStoredEditUsesOneCanvasRasterInSessionAndAfterRelaunch() async throws {
        let fixture = try await makeFixture(
            [
                PhotoSeed(name: "exact.png", exposure: 0.4),
                PhotoSeed(name: "exact-peer.png", exposure: -0.3),
            ], name: "exact-relaunch"
        )
        try await seedPreviewFrames(fixture)
        try await seedThumbnailFrames(fixture)

        let firstLedger = PresentationChangeLedger()
        let firstEngine = FakeRenderEngine()
        let (first, _) = try await makeViewModel(fixture, engine: firstEngine, ledger: firstLedger)
        try await open("exact.png", in: first)
        let assetID = try fixture.asset(named: "exact.png").id
        let surface = PresentationSurface.editCanvas(assetID)
        firstLedger.reset()
        try await open("exact-peer.png", in: first)
        firstLedger.reset()
        try await open("exact.png", in: first)
        assertRasterSources([.stored], on: surface, in: firstLedger)
        assertRasterAssignmentCount(Self.exactCanvasAssignments, on: surface, in: firstLedger)
        let firstPreviewCount = await firstEngine.previewRequests.count
        let firstThumbnailCount = await firstEngine.thumbnailRequests.count
        XCTAssertEqual(
            firstPreviewCount, 0,
            "\(surface.description) exact-open render budget failed. Ordered changes:\n\(firstLedger.diagnostic(for: surface))"
        )
        XCTAssertEqual(
            firstThumbnailCount, 0,
            "\(surface.description) exact-open supporting-render budget failed. Ordered changes:\n\(firstLedger.diagnostic(for: surface))"
        )
        await first.shutdown()

        let secondLedger = PresentationChangeLedger()
        let secondEngine = FakeRenderEngine()
        let (second, _) = try await makeViewModel(fixture, engine: secondEngine, ledger: secondLedger)
        try await open("exact.png", in: second)
        assertRasterSources([.stored], on: surface, in: secondLedger)
        assertRasterAssignmentCount(Self.exactCanvasAssignments, on: surface, in: secondLedger)
        let secondPreviewCount = await secondEngine.previewRequests.count
        let secondThumbnailCount = await secondEngine.thumbnailRequests.count
        XCTAssertEqual(
            secondPreviewCount, 0,
            "\(surface.description) relaunch render budget failed. Ordered changes:\n\(secondLedger.diagnostic(for: surface))"
        )
        XCTAssertEqual(
            secondThumbnailCount, 0,
            "\(surface.description) relaunch supporting-render budget failed. Ordered changes:\n\(secondLedger.diagnostic(for: surface))"
        )
        XCTAssertEqual(
            second.presentationSessionForDiagnostics?.distinctFrameCount, 1,
            "\(surface.description) should confirm its stored frame once. Ordered changes:\n\(secondLedger.diagnostic(for: surface))"
        )
        assertGeometryChangeCount(0, on: surface, in: secondLedger)
        await second.shutdown()
    }

    func testStaleStoredEditGetsOneRefinementAndAtMostOneCrossfade() async throws {
        let fixture = try await makeFixture(
            [PhotoSeed(name: "stale.png", exposure: 0.8)], name: "stale-preview"
        )
        try await seedPreviewFrames(fixture, editHashes: ["stale.png": "previous-edit"])
        let ledger = PresentationChangeLedger()
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        try await open("stale.png", in: viewModel)
        let surface = PresentationSurface.editCanvas(try fixture.asset(named: "stale.png").id)
        assertRasterSources([.stored, .refinement], on: surface, in: ledger)
        assertRasterAssignmentCount(Self.staleCanvasAssignments, on: surface, in: ledger)
        let previewCount = await engine.previewRequests.count
        XCTAssertEqual(
            previewCount, 1,
            "\(surface.description) stale-refinement render budget failed. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        XCTAssertLessThanOrEqual(
            ledger.changes(on: surface).filter { $0.kind == .crossfade }.count, 1,
            "\(surface.description) crossfade budget exceeded. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        assertGeometryChangeCount(0, on: surface, in: ledger)
        await viewModel.shutdown()
    }

    func testColdEditOpenHasBoundedAssignmentsAndWritesCanonicalFrame() async throws {
        let fixture = try await makeFixture(
            [PhotoSeed(name: "cold.png", exposure: 0.3)], name: "cold-preview"
        )
        let ledger = PresentationChangeLedger()
        let engine = RenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        try await open("cold.png", in: viewModel)
        let surface = PresentationSurface.editCanvas(try fixture.asset(named: "cold.png").id)
        let sources = ledger.changes(on: surface).compactMap { change -> PresentationRasterSource? in
            guard case .rasterAssignment(let source) = change.kind else { return nil }
            return source
        }
        XCTAssertLessThanOrEqual(
            sources.count, Self.coldCanvasAssignments,
            "\(surface.description) cold-open raster budget exceeded. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        XCTAssertTrue(
            sources.allSatisfy { [.thumbnail, .embedded, .settled, .refinement].contains($0) },
            "\(surface.description) cold-open source was unexpected. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        try await waitUntil("cold canonical frame admission") {
            viewModel.canonicalWriteAdmissionCountForDiagnostics > 0
        }
        XCTAssertEqual(
            viewModel.canonicalWriteAdmissionCountForDiagnostics, 1,
            "\(surface.description) cold open must admit one canonical write. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        let identity = fixture.assets[0].source.portableIdentity
        await viewModel.waitForCanonicalWriteForDiagnostics(for: identity)
        let store = LatestPreviewFrameStore(directory: fixture.previewDirectory)
        let metadata = await store.metadata(for: fixture.assets[0].source.portableIdentity)
        XCTAssertNotNil(
            metadata,
            "\(surface.description) cold-open budget requires a canonical write. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        await viewModel.shutdown()
    }

    func testPhotoSwitchNeverAssignsAnotherAssetsPixelsToTheCanvas() async throws {
        let fixture = try await makeFixture([
            PhotoSeed(name: "switch-a.png", exposure: 0.2),
            PhotoSeed(name: "switch-b.png", exposure: -0.2),
        ], name: "switch-canvas")
        let ledger = PresentationChangeLedger()
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        for name in ["switch-a.png", "switch-b.png", "switch-a.png"] {
            let before = ledger.changes.count
            try await open(name, in: viewModel)
            let expectedID = try fixture.asset(named: name).id
            let changes = Array(ledger.changes.dropFirst(before)).filter {
                if case .editCanvas = $0.surface { return true }
                return false
            }
            XCTAssertTrue(
                changes.allSatisfy { $0.surface == .editCanvas(expectedID) },
                "Edit canvas showed a different asset during switch to \(name). Ordered changes:\n\(changes.map(\.diagnostic).joined(separator: "\n"))"
            )
            let surface = PresentationSurface.editCanvas(expectedID)
            let rasterCount = ledger.changes(on: surface).filter {
                if case .rasterAssignment = $0.kind { return true }
                return false
            }.count
            XCTAssertLessThanOrEqual(
                rasterCount, Self.coldCanvasAssignments,
                "\(surface.description) switch-open raster budget exceeded. Ordered changes:\n\(ledger.diagnostic(for: surface))"
            )
        }
        await viewModel.shutdown()
    }

    func testExactStoredGridCellHasOneAssignmentAndStableGeometryAfterRelaunch() async throws {
        let fixture = try await makeFixture(
            [PhotoSeed(name: "grid-exact.png", exposure: 0.45)], name: "grid-exact"
        )
        try await seedThumbnailFrames(fixture)
        let firstLedger = PresentationChangeLedger()
        let firstEngine = FakeRenderEngine()
        let (first, _) = try await makeViewModel(fixture, engine: firstEngine, ledger: firstLedger)
        let firstItem = try XCTUnwrap(first.collection.items.first)
        firstItem.markLibraryLayoutPresented()
        first.collection.beginThumbnailDemand()
        first.collection.requestVisibleThumbnails(for: [firstItem.id])
        try await waitUntil("exact edited grid thumbnail confirmation") {
            firstItem.editedThumbnailRevision != nil
        }
        for surface in [PresentationSurface.gridCell(firstItem.id), .filmstripCell(firstItem.id)] {
            assertRasterSources([.stored], on: surface, in: firstLedger)
            assertRasterAssignmentCount(Self.exactCanvasAssignments, on: surface, in: firstLedger)
            assertGeometryChangeCount(0, on: surface, in: firstLedger)
        }
        let firstThumbnailCount = await firstEngine.thumbnailRequests.count
        XCTAssertEqual(
            firstThumbnailCount, 0,
            "gridCell(\(firstItem.id)) exact first-session budget failed. Ordered changes:\n\(firstLedger.diagnostic(for: .gridCell(firstItem.id)))"
        )
        await first.shutdown()

        let ledger = PresentationChangeLedger()
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        let item = try XCTUnwrap(viewModel.collection.items.first)
        item.markLibraryLayoutPresented()
        let ratio = item.libraryAspectRatio
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: [item.id])
        try await waitUntil("exact relaunch grid thumbnail confirmation") {
            item.editedThumbnailRevision != nil
        }
        for surface in [PresentationSurface.gridCell(item.id), .filmstripCell(item.id)] {
            assertRasterSources([.stored], on: surface, in: ledger)
            assertRasterAssignmentCount(Self.exactCanvasAssignments, on: surface, in: ledger)
            assertGeometryChangeCount(0, on: surface, in: ledger)
        }
        XCTAssertEqual(item.libraryAspectRatio, ratio, accuracy: 1e-9)
        let thumbnailCount = await engine.thumbnailRequests.count
        let surface = PresentationSurface.gridCell(item.id)
        XCTAssertEqual(
            thumbnailCount, 0,
            "\(surface.description) exact stored-cell render budget failed. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        await viewModel.shutdown()
    }

    func testChangedGridEditReplacesStoredPixelsOnceWithoutCropReflow() async throws {
        let fixture = try await makeFixture(
            [PhotoSeed(name: "grid-stale.png", exposure: 0.9)], name: "grid-stale"
        )
        try await seedThumbnailFrames(fixture, editedHashes: ["grid-stale.png": "old-grid-edit"])
        let ledger = PresentationChangeLedger()
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        let item = try XCTUnwrap(viewModel.collection.items.first)
        item.markLibraryLayoutPresented()
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: [item.id])
        try await waitUntil("changed edited grid thumbnail replacement") {
            let requests = await engine.thumbnailRequests
            return item.editedThumbnailRevision != nil
                && requests.contains { $0.assetID == item.id }
        }
        for surface in [PresentationSurface.gridCell(item.id), .filmstripCell(item.id)] {
            assertRasterSources([.stored, .refinement], on: surface, in: ledger)
            assertGeometryChangeCount(Self.cropFreeCellGeometryChanges, on: surface, in: ledger)
        }
        let thumbnailCount = await engine.thumbnailRequests.filter { $0.assetID == item.id }.count
        let surface = PresentationSurface.gridCell(item.id)
        XCTAssertEqual(
            thumbnailCount, 1,
            "\(surface.description) changed-edit render budget failed. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        await viewModel.shutdown()
    }

    func testIdenticalLookRescanDoesNotInvalidateOrRepaintMaterializedSurfaces() async throws {
        let looks = tempDirectory.appendingPathComponent("look-identical", isDirectory: true)
        try FileManager.default.createDirectory(at: looks, withIntermediateDirectories: true)
        let cube = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Shared.cube", in: looks
        )
        let lookID = try CubeLUT(url: cube).lutID
        let fixture = try await makeFixture([
            PhotoSeed(name: "look-identical.png", exposure: 0.1, lookID: lookID)
        ], name: "look-identical-package", looksDirectory: looks)
        let ledger = PresentationChangeLedger()
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        viewModel.library.setFolder(looks)
        try await waitUntil("initial Look scan") {
            !viewModel.library.isScanning && viewModel.library.allLUTs.contains { $0.lutID == lookID }
        }
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: viewModel.collection.items.map(\.id))
        try await waitUntil("Look-referencing thumbnail materialized") {
            viewModel.collection.items.first?.editedThumbnailRevision != nil
        }
        try await open("look-identical.png", in: viewModel)
        ledger.reset()
        let priorRequests = await engine.renderRequests.count
        viewModel.library.scan(looks)
        try await waitUntil("identical Look rescan") { !viewModel.library.isScanning }
        try await Task.sleep(for: .milliseconds(60))
        let finalRequests = await engine.renderRequests.count
        XCTAssertEqual(
            finalRequests, priorRequests,
            "identical Look content must not admit render work. Ordered changes:\n\(ledger.changes.map(\.diagnostic).joined(separator: "\n"))"
        )
        XCTAssertTrue(
            ledger.changes.isEmpty,
            "identical Look rescan changed presentation or collection projection:\n\(ledger.changes.map(\.diagnostic).joined(separator: "\n"))"
        )
        await viewModel.shutdown()
    }

    func testChangedLookRendersOnlyMaterializedPhotosThatReferenceItOnce() async throws {
        let looks = tempDirectory.appendingPathComponent("look-changed", isDirectory: true)
        try FileManager.default.createDirectory(at: looks, withIntermediateDirectories: true)
        let cube = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Shared.cube", in: looks
        )
        let lookID = try CubeLUT(url: cube).lutID
        let fixture = try await makeFixture([
            PhotoSeed(name: "look-a.png", exposure: 0.1, lookID: lookID),
            PhotoSeed(name: "look-b.png", exposure: -0.1, lookID: lookID),
            PhotoSeed(name: "look-c.png", exposure: 0.3),
        ], name: "look-changed-package", looksDirectory: looks)
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine)
        viewModel.library.setFolder(looks)
        try await waitUntil("initial changed-Look scan") {
            !viewModel.library.isScanning && viewModel.library.allLUTs.contains { $0.lutID == lookID }
        }
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: viewModel.collection.items.map(\.id))
        try await waitUntil("all Looks materialized") {
            viewModel.collection.items.allSatisfy { $0.editedThumbnailRevision != nil }
        }
        try await open("look-a.png", in: viewModel)
        let a = try fixture.asset(named: "look-a.png").id
        let b = try fixture.asset(named: "look-b.png").id
        let c = try fixture.asset(named: "look-c.png").id
        let baseCanvas = await engine.previewRequests.filter { $0.assetID == a }.count
        let baseA = await engine.thumbnailRequests.filter { $0.assetID == a }.count
        let baseB = await engine.thumbnailRequests.filter { $0.assetID == b }.count
        let baseC = await engine.thumbnailRequests.filter { $0.assetID == c }.count
        let ledger = PresentationChangeLedger()
        viewModel.previewSurface.presentationChangeLedger = ledger
        viewModel.collection.installPresentationChangeLedger(ledger)

        _ = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 3), named: "Shared.cube", in: looks
        )
        viewModel.library.scan(looks)
        try await waitUntil("referenced Look replacements") {
            let previews = await engine.previewRequests.filter { $0.assetID == a }.count
            let thumbnails = await engine.thumbnailRequests
            return previews >= baseCanvas + Self.referencedLookRendersPerPhoto
                && thumbnails.filter { $0.assetID == a }.count >= baseA + Self.referencedLookRendersPerPhoto
                && thumbnails.filter { $0.assetID == b }.count >= baseB + Self.referencedLookRendersPerPhoto
        }
        try await Task.sleep(for: .milliseconds(60))
        let canvasA = await engine.previewRequests.filter { $0.assetID == a }.count - baseCanvas
        let thumbnails = await engine.thumbnailRequests
        XCTAssertEqual(
            canvasA, Self.referencedLookRendersPerPhoto,
            "\(PresentationSurface.editCanvas(a).description) changed-Look render budget failed. Ordered changes:\n\(ledger.diagnostic(for: .editCanvas(a)))"
        )
        XCTAssertEqual(
            thumbnails.filter { $0.assetID == a }.count - baseA,
            Self.referencedLookRendersPerPhoto,
            "look-a.png references the changed Look. Ordered changes:\n\(ledger.diagnostic(for: .gridCell(a)))"
        )
        XCTAssertEqual(
            thumbnails.filter { $0.assetID == b }.count - baseB,
            Self.referencedLookRendersPerPhoto,
            "look-b.png references the changed Look. Ordered changes:\n\(ledger.diagnostic(for: .gridCell(b)))"
        )
        XCTAssertEqual(
            thumbnails.filter { $0.assetID == c }.count, baseC,
            "\(PresentationSurface.gridCell(c).description) is unrelated to the changed Look. Ordered changes:\n\(ledger.diagnostic(for: .gridCell(c)))"
        )
        XCTAssertFalse(
            ledger.changes.contains { $0.surface == .editCanvas(b) || $0.surface == .editCanvas(c) },
            "only the active photo may repaint the Edit canvas:\n\(ledger.changes.map(\.diagnostic).joined(separator: "\n"))"
        )
        await viewModel.shutdown()
    }

    func testSliderInteractionFramesAreNotWrittenAndSettleWritesOnce() async throws {
        let fixture = try await makeFixture(
            [PhotoSeed(name: "slider.png", exposure: 0)], name: "slider-settle"
        )
        try await seedPreviewFrames(fixture)
        let ledger = PresentationChangeLedger()
        let engine = FakeRenderEngine()
        let (viewModel, _) = try await makeViewModel(fixture, engine: engine, ledger: ledger)
        try await open("slider.png", in: viewModel)
        let asset = try fixture.asset(named: "slider.png")
        let surface = PresentationSurface.editCanvas(asset.id)
        XCTAssertEqual(
            viewModel.canonicalWriteAdmissionCountForDiagnostics, 0,
            "\(surface.description) exact open should not rewrite its canonical frame. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        let store = LatestPreviewFrameStore(directory: fixture.previewDirectory)
        let initialMetadata = await store.metadata(for: asset.source.portableIdentity)
        let originalEditHash = try fixture.document(named: "slider.png").editHash
        XCTAssertEqual(initialMetadata?.signature.editHash, originalEditHash)

        viewModel.beginCanvasInteraction()
        for exposure in [0.1, 0.25, 0.4] {
            viewModel.updateDocument(debounced: true) {
                $0.adjustments = [.exposure(ev: exposure)]
            }
        }
        try await waitUntil("interactive slider frames") {
            await engine.renderRequests.contains { $0.quality == .interactive }
        }
        try await Task.sleep(for: .milliseconds(80))
        let beforeSettle = await store.metadata(for: asset.source.portableIdentity)
        XCTAssertEqual(
            beforeSettle?.signature.editHash, originalEditHash,
            "\(surface.description) interactive slider frames must not replace the canonical stored frame. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        XCTAssertEqual(
            viewModel.canonicalWriteAdmissionCountForDiagnostics, 0,
            "\(surface.description) interactive frames must not enter the canonical writer. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )

        viewModel.endCanvasInteraction()
        viewModel.scheduleCanvasWorkflowPreview()
        let settledHash = viewModel.document.editHash
        try await waitUntil("one settled slider render and canonical frame write") {
            let requests = await engine.renderRequests
            let metadata = await store.metadata(for: asset.source.portableIdentity)
            return requests.last?.quality == .preview
                && requests.last?.document.editHash == settledHash
                && metadata?.signature.editHash == settledHash
                && viewModel.canonicalWriteAdmissionCountForDiagnostics > 0
        }
        let interactiveAssignments = ledger.changes(on: surface).filter {
            $0.kind == .rasterAssignment(.refinement)
        }.count
        XCTAssertGreaterThan(
            interactiveAssignments, 0,
            "\(surface.description) should publish interactive refinements before it settles. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        XCTAssertEqual(
            viewModel.canonicalWriteAdmissionCountForDiagnostics, 1,
            "\(surface.description) slider settle must admit exactly one canonical write. Ordered changes:\n\(ledger.diagnostic(for: surface))"
        )
        await viewModel.shutdown()
    }

    func testRasterMutationHooksStayAtTheSurfaceAssignmentPoints() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/KromoraKit/Views/PreviewSurface.swift"),
            encoding: .utf8
        )
        let collectionSource = try String(
            contentsOf: root.appendingPathComponent("Sources/KromoraKit/Models/ImageCollection.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(previewSource.components(separatedBy: "self.image = image").count - 1, 1)
        XCTAssertEqual(collectionSource.components(separatedBy: "displayedThumbnail = newValue").count - 1, 1)
        XCTAssertTrue(
            previewSource.contains("guard let ledger = presentationChangeLedger else { return }"),
            "PreviewSurface assignment must retain the inline no-recorder guard"
        )
        XCTAssertTrue(
            collectionSource.contains("guard let ledger = presentationChangeLedger else { return }"),
            "ImageCollection.Item assignment must retain the inline no-recorder guard"
        )
    }
}

private extension FrameSignature {
    func metadata(kind: PresentationFrameKind, width: Int, height: Int) -> PresentationFrameMetadata {
        PresentationFrameMetadata(
            identity: source, kind: kind, signature: self,
            geometry: PresentedGeometry(
                crop: .neutral, rotation: .zero,
                orientedAspectRatio: Double(width) / Double(height)
            ),
            rasterColorSpace: .sRGB,
            perceptualDigest: FrameFixtures.digest(),
            presentedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pixelWidth: width, pixelHeight: height
        )
    }
}
