import AppKit
import CoreGraphics
import XCTest
@testable import KromoraKit

@MainActor
final class EditedThumbnailCoordinatorTests: XCTestCase {
    func testDebounceCoalescesBurstToOneTrailingRequest() async throws {
        let fixture = makeFixture()
        for _ in 0..<5 {
            fixture.coordinator.scheduleAfterSettle(for: fixture.assetID, priority: .activeEditor)
            try await Task.sleep(for: .milliseconds(35))
        }

        try await waitUntil("the trailing thumbnail render") {
            await fixture.engine.thumbnailRequestCount == 1
        }
        let requestCount = await fixture.engine.thumbnailRequestCount
        XCTAssertEqual(requestCount, 1)
        await fixture.scheduler.cancelAllAndWait()
    }

    func testShutdownDropsLateRendererResult() async throws {
        let fixture = makeFixture(rendererWaits: true)
        fixture.coordinator.request(for: fixture.assetID, priority: .activeEditor)
        try await waitUntil("the held render") { await fixture.engine.hasThumbnailRequest }

        await fixture.coordinator.shutdown()
        await fixture.engine.releaseThumbnail()
        await fixture.scheduler.cancelAllAndWait()

        XCTAssertTrue(fixture.destination.appliedRevisions.isEmpty)
    }

    func testSourceIdentityChangeRejectsLateResult() async throws {
        let fixture = makeFixture(rendererWaits: true)
        fixture.coordinator.request(for: fixture.assetID, priority: .activeEditor)
        try await waitUntil("the held render") { await fixture.engine.hasThumbnailRequest }

        fixture.destination.item.asset = PhotoAsset(data: Data([9, 8, 7]), filename: "changed.jpg")
        await fixture.engine.releaseThumbnail()
        await fixture.scheduler.cancelAllAndWait()

        XCTAssertTrue(fixture.destination.appliedRevisions.isEmpty)
    }

    func testRevisionIncludesEditHashAndResolvedLUTFingerprint() async throws {
        let lut = CubeLUT(
            cube: (0..<8).map { index in
                let value = Float(index) / 7
                return SIMD3(value, value, value)
            }, size: 2, name: "Test"
        )
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.25)], lut: LUTSettings(lutID: lut.lutID)
        )
        let fixture = makeFixture(document: document, lut: lut)
        fixture.coordinator.request(for: fixture.assetID, priority: .activeEditor)
        try await waitUntil("the thumbnail revision") {
            !fixture.destination.appliedRevisions.isEmpty
        }

        XCTAssertEqual(
            fixture.destination.appliedRevisions.last,
            document.editHash + ":" + lut.cacheFingerprint
        )
        await fixture.scheduler.cancelAllAndWait()
    }

    func testVisibleDemandReplacesAnOlderMaterializedRevisionWithoutInteraction() async throws {
        let currentDocument = EditDocument(adjustments: [.exposure(ev: 0.65)])
        let fixture = makeFixture(document: currentDocument, active: false)
        fixture.item.applyEditedThumbnail(nil, revision: "older-saved-edit")

        fixture.coordinator.request(for: fixture.assetID, priority: .visibleGrid)
        try await waitUntil("the current saved edit thumbnail") {
            fixture.item.editedThumbnailRevision
                == currentDocument.editHash + ":unresolved"
        }

        let renderedEditHashes = await fixture.engine.renderedEditHashes
        XCTAssertEqual(renderedEditHashes, [currentDocument.editHash])
        XCTAssertFalse(fixture.destination.appliedWasNil)
        await fixture.scheduler.cancelAllAndWait()
    }

    func testIdentityDocumentPublishesNilWithoutRendering() async throws {
        let fixture = makeFixture(document: EditDocument())
        fixture.coordinator.request(for: fixture.assetID, priority: .activeEditor)

        XCTAssertEqual(fixture.destination.appliedRevisions, [EditDocument().editHash + ":unresolved"])
        XCTAssertTrue(fixture.destination.appliedWasNil)
        let requestCount = await fixture.engine.thumbnailRequestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testVisibleDemandSurvivesPreviewInteractionUntilSettled() async throws {
        let fixture = makeFixture(active: false)
        fixture.destination.isEditedThumbnailInteractionActive = true
        fixture.coordinator.request(for: fixture.assetID, priority: .visibleGrid)

        XCTAssertTrue(fixture.destination.appliedRevisions.isEmpty)
        let initialRequestCount = await fixture.engine.thumbnailRequestCount
        XCTAssertEqual(initialRequestCount, 0)

        fixture.destination.isEditedThumbnailInteractionActive = false
        fixture.coordinator.admitDeferredDemands()
        try await waitUntil("the deferred visible thumbnail") {
            !fixture.destination.appliedRevisions.isEmpty
        }

        let renderedEditHashes = await fixture.engine.renderedEditHashes
        XCTAssertEqual(renderedEditHashes, [fixture.destination.document.editHash])
        XCTAssertFalse(fixture.destination.appliedWasNil)
        await fixture.scheduler.cancelAllAndWait()
    }

    func testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen() async throws {
        let root = try Fixtures.makeTempDirectory("EditedThumbnailRelaunch")
        defer { try? FileManager.default.removeItem(at: root) }
        let packageURL = root.appendingPathComponent("Library.kromoralibrary")
        let indexURL = root.appendingPathComponent("LibraryIndex.store")
        let sourceURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "edited.jpg", in: root
        )
        let firstSession = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        _ = try firstSession.importURLs([sourceURL])
        let firstAsset = try XCTUnwrap(firstSession.materializedAssets().first)
        let savedDocument = EditDocument(
            crop: CropAdjustments(normalizedRect: CGRect(
                x: 0.18, y: 0.12, width: 0.54, height: 0.72
            )),
            adjustments: [.exposure(ev: 0.6)]
        )
        let firstStore = EditDocumentStore(package: firstSession.package, lease: firstSession.lease)
        try await firstStore.save(savedDocument, for: EditSourceReference(
            assetID: firstAsset.id,
            portableIdentity: firstAsset.source.portableIdentity,
            url: firstAsset.url
        ))
        await firstSession.shutdown()

        let reopenedSession = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        let reopenedAsset = try XCTUnwrap(reopenedSession.materializedAssets().first)
        let collection = ImageCollection()
        collection.loadPortableAssets([reopenedAsset])
        await collection.scanCompletion()
        collection.beginThumbnailDemand()
        let item = try XCTUnwrap(collection.items.first)
        XCTAssertNotNil(item.url, "the reopened package asset must expose its source")
        let reopenedStore = EditDocumentStore(
            package: reopenedSession.package, lease: reopenedSession.lease
        )

        let assetID = reopenedAsset.id
        let destination = FakeDestination(
            assetID: assetID, item: item, document: nil, lut: nil, active: false
        )
        destination.onApply = { image, revision in
            collection.applyEditedThumbnail(image, for: assetID, revision: revision)
        }
        let scheduler = ImageWorkScheduler()
        let engine = FakeEditedThumbnailRenderer(waits: false)
        let coordinator = EditedThumbnailCoordinator(
            workScheduler: scheduler,
            engine: engine,
            editStore: reopenedStore,
            destination: destination
        )
        collection.onThumbnailDemand = { demandedID, priority in
            coordinator.request(for: demandedID, priority: priority)
        }
        collection.requestVisibleThumbnails(for: [assetID])

        try await waitUntil("the persisted edited thumbnail") {
            item.editedThumbnailRevision != nil
        }

        XCTAssertNil(collection.selection.activeID, "visible demand must not require selection")
        let renderedEditHashes = await engine.renderedEditHashes
        XCTAssertEqual(renderedEditHashes, [savedDocument.editHash])
        let renderedCrops = await engine.renderedCrops
        XCTAssertEqual(renderedCrops, [savedDocument.crop])
        XCTAssertEqual(
            destination.presentedCrop,
            savedDocument.crop,
            "reopening must adopt the saved crop for Library cell geometry"
        )
        XCTAssertFalse(destination.appliedWasNil)
        XCTAssertNotNil(item.thumbnail, "the edited raster must be published to the library item")
        await scheduler.cancelAllAndWait()
        await reopenedSession.shutdown()
    }

    private func makeFixture(
        document: EditDocument = EditDocument(adjustments: [.exposure(ev: 0.2)]),
        lut: CubeLUT? = nil,
        rendererWaits: Bool = false,
        active: Bool = true
    ) -> Fixture {
        let assetID = PhotoAssetID.imported(UUID())
        let item = ImageCollection.Item(
            asset: PhotoAsset(data: Data([1, 2, 3]), filename: "sample.jpg")
        )
        let destination = FakeDestination(
            assetID: assetID, item: item, document: document, lut: lut, active: active
        )
        let scheduler = ImageWorkScheduler()
        let engine = FakeEditedThumbnailRenderer(waits: rendererWaits)
        let coordinator = EditedThumbnailCoordinator(
            workScheduler: scheduler, engine: engine,
            editStore: EditDocumentStore.makeInMemoryProjectionStore(), destination: destination
        )
        return Fixture(
            assetID: assetID, item: item, destination: destination,
            scheduler: scheduler, engine: engine, coordinator: coordinator
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private struct Fixture {
    let assetID: PhotoAssetID
    let item: ImageCollection.Item
    let destination: FakeDestination
    let scheduler: ImageWorkScheduler
    let engine: FakeEditedThumbnailRenderer
    let coordinator: EditedThumbnailCoordinator
}

@MainActor
private final class FakeDestination: EditedThumbnailDestination {
    let activeEditedThumbnailAssetID: PhotoAssetID?
    var editedThumbnailSourceRevision: UInt64 = 1
    var editedThumbnailDocumentRevision: UInt64 = 1
    var isEditedThumbnailShuttingDown = false
    var isEditedThumbnailInteractionActive = false
    var isEditedThumbnailPreviewDebouncing = false
    let item: ImageCollection.Item
    let document: EditDocument
    private let lut: CubeLUT?
    private(set) var appliedRevisions: [String] = []
    private(set) var appliedWasNil = false
    private(set) var presentedCrop = CropAdjustments.neutral
    var onApply: ((NSImage?, String) -> Void)?

    init(
        assetID: PhotoAssetID, item: ImageCollection.Item, document: EditDocument?,
        lut: CubeLUT?, active: Bool = true
    ) {
        self.activeEditedThumbnailAssetID = active ? assetID : nil
        self.item = item
        self.document = document ?? EditDocument()
        self.lut = lut
        storedDocument = document
    }

    var editedThumbnailItems: [ImageCollection.Item] { [item] }
    func editedThumbnailItem(for assetID: PhotoAssetID) -> ImageCollection.Item? { item }
    func editedThumbnailDocument(for assetID: PhotoAssetID) -> EditDocument? {
        // A nil document models a cold item whose current document must come from the package.
        storedDocument
    }
    func editedThumbnailDocumentRevision(for assetID: PhotoAssetID) -> UInt64 { 1 }
    func resolvedEditedThumbnailLUT(_ id: LUTID?) -> CubeLUT? { lut }
    func invalidateEditedThumbnail(for assetID: PhotoAssetID) {
        item.invalidateEditedThumbnail()
    }
    func applyEditedThumbnail(_ image: NSImage?, for assetID: PhotoAssetID, revision: String) {
        appliedWasNil = image == nil
        appliedRevisions.append(revision)
        item.applyEditedThumbnail(image, revision: revision)
        onApply?(image, revision)
    }
    func setEditedThumbnailPresentedCrop(_ crop: CropAdjustments, for assetID: PhotoAssetID) {
        presentedCrop = crop
    }

    private var storedDocument: EditDocument?
}

private actor FakeEditedThumbnailRenderer: EditedThumbnailRendering {
    private let waits: Bool
    private(set) var thumbnailRequestCount = 0
    private(set) var renderedEditHashes: [String] = []
    private(set) var renderedCrops: [CropAdjustments] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(waits: Bool) { self.waits = waits }

    var hasThumbnailRequest: Bool { thumbnailRequestCount > 0 }

    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? { nil }

    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage? {
        thumbnailRequestCount += 1
        renderedEditHashes.append(request.document.editHash)
        renderedCrops.append(request.document.crop)
        if waits {
            await withCheckedContinuation { continuation = $0 }
        }
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context?.makeImage()
    }

    func releaseThumbnail() {
        continuation?.resume()
        continuation = nil
    }
}
