import AppKit
import XCTest
@testable import KromoraKit

final class PhotosThumbnailLoaderTests: XCTestCase {
    private struct Provider: PhotosThumbnailProviding {
        let result: @Sendable (String) throws -> NSImage
        func thumbnail(for localIdentifier: String) async throws -> NSImage { try result(localIdentifier) }
    }

    func testLoadedWhenProviderReturnsImage() async {
        let loader = PhotosThumbnailLoader(provider: Provider { _ in NSImage(size: NSSize(width: 4, height: 4)) })
        guard case .loaded = await loader.load("a") else { return XCTFail("expected loaded") }
    }

    func testMissingIdentifierFailsWithoutCallingProvider() async {
        let loader = PhotosThumbnailLoader(provider: Provider { _ in XCTFail("unexpected call"); throw CancellationError() })
        guard case .failed(.missingIdentifier) = await loader.load(nil) else { return XCTFail("expected failure") }
    }

    func testProviderErrorsMapToFailed() async {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        let loader = PhotosThumbnailLoader(provider: Provider { _ in throw Boom() })
        guard case .failed(.failed("boom")) = await loader.load("a") else { return XCTFail("expected failed") }
        let unavailable = PhotosThumbnailLoader(provider: Provider { _ in throw PhotosThumbnailFailure.assetUnavailable })
        guard case .failed(.assetUnavailable) = await unavailable.load("a") else { return XCTFail("expected unavailable") }
    }

    @MainActor
    func testModelExposesLoadingLoadedAndFailedStates() async {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let loaded = PhotosThumbnailModel(
            loader: PhotosThumbnailLoader(provider: Provider { _ in image })
        )
        guard case .loading = loaded.state else { return XCTFail("expected loading") }
        await loaded.load("a")
        guard case .loaded(let loadedImage) = loaded.state else { return XCTFail("expected loaded") }
        XCTAssertEqual(loadedImage.size, image.size)

        let failed = PhotosThumbnailModel(
            loader: PhotosThumbnailLoader(provider: Provider { _ in throw PhotosThumbnailFailure.assetUnavailable })
        )
        guard case .loading = failed.state else { return XCTFail("expected loading") }
        await failed.load("a")
        guard case .failed(.assetUnavailable) = failed.state else { return XCTFail("expected failed") }
    }
}
