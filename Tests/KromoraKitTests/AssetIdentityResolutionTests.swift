import XCTest

@testable import KromoraKit

final class AssetIdentityResolutionTests: XCTestCase {
    private let missing = URL(fileURLWithPath: "/nonexistent/kromora-\(UUID().uuidString)/a.dng")

    func testDraftConstructionDoesNotResolveFileIdentity() {
        let draft = SourceImportDraft(name: "a", url: missing, data: nil)
        XCTAssertNil(draft.assetID)
    }

    func testDraftKeepsSuppliedAndDataIdentity() {
        let supplied = PhotoAssetID.photos(localIdentifier: "x")
        XCTAssertEqual(
            SourceImportDraft(name: "a", url: missing, data: nil, assetID: supplied).assetID,
            supplied)
        let bytes = Data([1, 2, 3])
        XCTAssertEqual(
            SourceImportDraft(name: "a", url: nil, data: bytes).assetID, .data(bytes))
    }

    func testResolvedDraftUsesPathFallbackForUnreadableFile() async {
        let plan = await SourceImportDraft(name: "a", url: missing, data: nil).resolved()
        XCTAssertEqual(plan.assetID, PhotoAssetID.file(missing))
        XCTAssertEqual(
            plan.assetID,
            PhotoAssetID(rawValue: "file-path:\(missing.standardizedFileURL.resolvingSymlinksInPath().path)"))
    }

    func testResolvedDraftUsesResourceIdentifierForRealFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-\(UUID().uuidString).bin")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = await SourceImportDraft(name: "a", url: url, data: nil).resolved()
        XCTAssertEqual(plan.assetID, PhotoAssetID.file(url))
        if PhotoSourceFingerprint.file(at: url).resourceIdentifier != nil {
            XCTAssertTrue(plan.assetID.raw.hasPrefix("file-resource:"))
        }
    }

    func testBatchItemConstructionDoesNotResolveFileIdentity() async {
        let item = ExportCoordinator.BatchItem(url: missing, data: nil, name: "a")
        XCTAssertNil(item.assetID)
        let resolved = await item.resolvedAssetID()
        XCTAssertEqual(resolved, PhotoAssetID.file(missing))
    }

    func testBatchItemKeepsSuppliedIdentity() async {
        let supplied = PhotoAssetID.photos(localIdentifier: "x")
        let item = ExportCoordinator.BatchItem(url: missing, data: nil, name: "a", assetID: supplied)
        let resolved = await item.resolvedAssetID()
        XCTAssertEqual(resolved, supplied)
    }
}
