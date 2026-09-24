import AppKit
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

    func testIdentityDocumentPublishesNilWithoutRendering() async throws {
        let fixture = makeFixture(document: EditDocument())
        fixture.coordinator.request(for: fixture.assetID, priority: .activeEditor)

        XCTAssertEqual(fixture.destination.appliedRevisions, [EditDocument().editHash + ":unresolved"])
        XCTAssertTrue(fixture.destination.appliedWasNil)
        let requestCount = await fixture.engine.thumbnailRequestCount
        XCTAssertEqual(requestCount, 0)
    }

    private func makeFixture(
        document: EditDocument = EditDocument(adjustments: [.exposure(ev: 0.2)]),
        lut: CubeLUT? = nil,
        rendererWaits: Bool = false
    ) -> Fixture {
        let assetID = PhotoAssetID.imported(UUID())
        let item = ImageCollection.Item(
            asset: PhotoAsset(data: Data([1, 2, 3]), filename: "sample.jpg")
        )
        let destination = FakeDestination(
            assetID: assetID, item: item, document: document, lut: lut
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
    private let document: EditDocument
    private let lut: CubeLUT?
    private(set) var appliedRevisions: [String] = []
    private(set) var appliedWasNil = false

    init(assetID: PhotoAssetID, item: ImageCollection.Item, document: EditDocument, lut: CubeLUT?) {
        self.activeEditedThumbnailAssetID = assetID
        self.item = item
        self.document = document
        self.lut = lut
    }

    var editedThumbnailItems: [ImageCollection.Item] { [item] }
    func editedThumbnailItem(for assetID: PhotoAssetID) -> ImageCollection.Item? { item }
    func editedThumbnailDocument(for assetID: PhotoAssetID) -> EditDocument? { document }
    func editedThumbnailDocumentRevision(for assetID: PhotoAssetID) -> UInt64 { 1 }
    func resolvedEditedThumbnailLUT(_ id: LUTID?) -> CubeLUT? { lut }
    func invalidateEditedThumbnail(for assetID: PhotoAssetID) {}
    func applyEditedThumbnail(_ image: NSImage?, for assetID: PhotoAssetID, revision: String) {
        appliedWasNil = image == nil
        appliedRevisions.append(revision)
    }
    func setEditedThumbnailPresentedCrop(_ crop: CropAdjustments, for assetID: PhotoAssetID) {}
}

private actor FakeEditedThumbnailRenderer: EditedThumbnailRendering {
    private let waits: Bool
    private(set) var thumbnailRequestCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(waits: Bool) { self.waits = waits }

    var hasThumbnailRequest: Bool { thumbnailRequestCount > 0 }

    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? { nil }

    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage? {
        thumbnailRequestCount += 1
        if waits {
            await withCheckedContinuation { continuation = $0 }
        }
        return nil
    }

    func releaseThumbnail() {
        continuation?.resume()
        continuation = nil
    }
}
