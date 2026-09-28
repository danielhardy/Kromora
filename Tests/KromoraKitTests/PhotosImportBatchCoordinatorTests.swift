import XCTest
@testable import KromoraKit

@MainActor
private final class PhotosImportBatchDestinationFake: PhotosImportBatchDestination {
    var currentOperationID = UUID()
    var results: [PortablePackageImportResult] = []
    var asyncResult: PortablePackageImportResult?
    var asyncContinuation: CheckedContinuation<PortablePackageImportResult, Never>?
    var refreshError: Error?
    var refreshCount = 0
    var openedAssets: [PortablePhotoAssetID] = []
    var inspectorPresentationCount = 0
    var errors: [String] = []
    var rebuildIndexValues: [Bool] = []

    func isCurrentPhotosImportBatch(_ operationID: UUID) -> Bool {
        operationID == currentOperationID
    }

    func writePhotosImportItem(
        _ item: ImageCollection.PhotoImportItem, rebuildIndex: Bool
    ) throws -> PortablePackageImportResult {
        rebuildIndexValues.append(rebuildIndex)
        return results.removeFirst()
    }

    func writePhotosImportItemAsync(
        _ item: ImageCollection.PhotoImportItem, rebuildIndex: Bool
    ) async throws -> PortablePackageImportResult {
        rebuildIndexValues.append(rebuildIndex)
        if let asyncResult { return asyncResult }
        return await withCheckedContinuation { asyncContinuation = $0 }
    }

    func refreshPhotosImportCollection() throws {
        refreshCount += 1
        if let refreshError { throw refreshError }
    }

    func openPhotosImportAsset(_ assetID: PortablePhotoAssetID) { openedAssets.append(assetID) }
    func presentPhotosImportInspector() { inspectorPresentationCount += 1 }
    func reportPhotosImportBatchError(_ message: String) { errors.append(message) }
}

@MainActor
final class PhotosImportBatchCoordinatorTests: XCTestCase {
    func testMapsInsertedDuplicateAndFailureResults() {
        let destination = PhotosImportBatchDestinationFake()
        let coordinator = PhotosImportBatchCoordinator(destination: destination)
        let operationID = destination.currentOperationID
        coordinator.begin(
            operationID: operationID, totalCount: 3,
            packageWasEmpty: false, packageAvailable: true
        )
        let insertedID = PortablePhotoAssetID()
        let duplicateID = PortablePhotoAssetID()
        destination.results = [
            result(imported: [importedAsset(insertedID)]),
            result(duplicates: [duplicate(duplicateID)]),
            result(failures: [failure("bad image")]),
        ]

        XCTAssertEqual(coordinator.insert(item(), ordinal: 0), .inserted("portable:\(insertedID.raw)"))
        XCTAssertEqual(coordinator.insert(item(), ordinal: 1), .duplicate("portable:\(duplicateID.raw)"))
        XCTAssertEqual(coordinator.insert(item(), ordinal: 2), .failed("bad image"))
        XCTAssertEqual(destination.rebuildIndexValues, [false, false, false])
    }

    func testBatchRefreshesOnceAndOpensFirstAssetOnlyForInitiallyEmptyPackage() {
        let destination = PhotosImportBatchDestinationFake()
        let coordinator = PhotosImportBatchCoordinator(destination: destination)
        let operationID = destination.currentOperationID
        let first = PortablePhotoAssetID()
        coordinator.begin(
            operationID: operationID, totalCount: 2,
            packageWasEmpty: true, packageAvailable: true
        )
        destination.results = [result(imported: [importedAsset(first)]), result(imported: [importedAsset(PortablePhotoAssetID())])]

        _ = coordinator.insert(item(), ordinal: 0)
        _ = coordinator.insert(item(), ordinal: 1)
        XCTAssertEqual(destination.refreshCount, 0)
        coordinator.finish()

        XCTAssertEqual(destination.refreshCount, 1)
        XCTAssertEqual(destination.openedAssets, [first])
        XCTAssertEqual(destination.inspectorPresentationCount, 1)
        XCTAssertFalse(coordinator.isBatchActive)
    }

    func testAsyncInsertionUsesTheSameOutcomeMappingAndBatchState() async {
        let destination = PhotosImportBatchDestinationFake()
        let coordinator = PhotosImportBatchCoordinator(destination: destination)
        let operationID = destination.currentOperationID
        let insertedID = PortablePhotoAssetID()
        let duplicateID = PortablePhotoAssetID()
        coordinator.begin(
            operationID: operationID, totalCount: 2,
            packageWasEmpty: true, packageAvailable: true
        )
        destination.results = [result(imported: [importedAsset(insertedID)])]
        destination.asyncResult = result(duplicates: [duplicate(duplicateID)])

        XCTAssertEqual(
            coordinator.insert(item(), ordinal: 0), .inserted("portable:\(insertedID.raw)")
        )
        let asyncOutcome = await coordinator.insertAsync(item(), ordinal: 1)
        XCTAssertEqual(asyncOutcome, .duplicate("portable:\(duplicateID.raw)"))
        XCTAssertEqual(destination.rebuildIndexValues, [false, false])

        coordinator.finish()
        XCTAssertEqual(destination.refreshCount, 1)
        XCTAssertEqual(destination.openedAssets, [insertedID])
        XCTAssertEqual(destination.inspectorPresentationCount, 1)
    }

    func testDuplicateOnlyAndEmptyBatchesResetWithoutRefresh() {
        let destination = PhotosImportBatchDestinationFake()
        let coordinator = PhotosImportBatchCoordinator(destination: destination)
        coordinator.begin(
            operationID: destination.currentOperationID, totalCount: 1,
            packageWasEmpty: true, packageAvailable: true
        )
        destination.results = [result(duplicates: [duplicate(PortablePhotoAssetID())])]
        _ = coordinator.insert(item(), ordinal: 0)
        coordinator.finish()
        XCTAssertEqual(destination.refreshCount, 0)

        coordinator.begin(
            operationID: destination.currentOperationID, totalCount: 0,
            packageWasEmpty: true, packageAvailable: true
        )
        coordinator.finish()
        XCTAssertEqual(destination.refreshCount, 0)
        XCTAssertFalse(coordinator.isBatchActive)
    }

    func testSupersededAsyncInsertAndRefreshFailureCannotOpenAsset() async {
        let destination = PhotosImportBatchDestinationFake()
        let coordinator = PhotosImportBatchCoordinator(destination: destination)
        let oldOperationID = destination.currentOperationID
        coordinator.begin(
            operationID: oldOperationID, totalCount: 1,
            packageWasEmpty: true, packageAvailable: true
        )
        let insertion = Task { await coordinator.insertAsync(item(), ordinal: 0) }
        while destination.asyncContinuation == nil { await Task.yield() }
        destination.currentOperationID = UUID()
        coordinator.begin(
            operationID: destination.currentOperationID, totalCount: 1,
            packageWasEmpty: true, packageAvailable: true
        )
        destination.asyncContinuation?.resume(returning: result(imported: [importedAsset(PortablePhotoAssetID())]))
        let staleOutcome = await insertion.value
        XCTAssertEqual(staleOutcome, .failed("Photos import was superseded."))
        coordinator.finish()
        XCTAssertEqual(destination.refreshCount, 0)
        XCTAssertTrue(destination.openedAssets.isEmpty)

        destination.currentOperationID = UUID()
        destination.refreshError = NSError(domain: "refresh", code: 1)
        coordinator.begin(
            operationID: destination.currentOperationID, totalCount: 1,
            packageWasEmpty: true, packageAvailable: true
        )
        destination.results = [result(imported: [importedAsset(PortablePhotoAssetID())])]
        _ = coordinator.insert(item(), ordinal: 0)
        coordinator.finish()
        XCTAssertEqual(destination.refreshCount, 1)
        XCTAssertTrue(destination.openedAssets.isEmpty)
        XCTAssertEqual(destination.errors.count, 1)
        XCTAssertFalse(coordinator.isBatchActive)
    }

    private func item() -> ImageCollection.PhotoImportItem {
        ImageCollection.PhotoImportItem(name: "photo.jpg", data: Data([1, 2, 3]))
    }

    private func result(
        imported: [PortablePackageImportedAsset] = [],
        duplicates: [PortablePackageDuplicate] = [],
        failures: [PortablePackageImportFailure] = []
    ) -> PortablePackageImportResult {
        PortablePackageImportResult(
            imported: imported, duplicates: duplicates, failures: failures,
            cancelled: false
        )
    }

    private func importedAsset(_ id: PortablePhotoAssetID) -> PortablePackageImportedAsset {
        PortablePackageImportedAsset(
            source: PortablePackageImportSource(data: Data(), name: "photo.jpg"),
            assetID: id, contentHash: "hash", byteCount: 0, usedClonefile: false
        )
    }

    private func duplicate(_ id: PortablePhotoAssetID) -> PortablePackageDuplicate {
        PortablePackageDuplicate(
            source: PortablePackageImportSource(data: Data(), name: "photo.jpg"),
            contentHash: "hash", existingAssetID: id, importedAssetID: nil
        )
    }

    private func failure(_ reason: String) -> PortablePackageImportFailure {
        PortablePackageImportFailure(
            source: PortablePackageImportSource(data: Data(), name: "photo.jpg"),
            reason: reason
        )
    }
}
