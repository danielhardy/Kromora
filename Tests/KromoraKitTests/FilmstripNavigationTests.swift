import XCTest
import SwiftUI
@testable import KromoraKit

@MainActor
final class FilmstripNavigationTests: TempDirectoryTestCase {
    func testFocusedArrowPressConsumesDownRepeatAndUp() {
        XCTAssertEqual(
            FilmstripNavigation.keyPressResult(for: .down), .handled
        )
        XCTAssertEqual(
            FilmstripNavigation.keyPressResult(for: .repeat), .handled
        )
        XCTAssertEqual(
            FilmstripNavigation.keyPressResult(for: .up), .handled
        )
        XCTAssertEqual(
            FilmstripNavigation.keyPressResult(for: []), .ignored
        )
    }

    func testAdjacentIndexFollowsFilteredDisplayOrder() {
        let visibleIndices = [1, 4, 7]

        XCTAssertEqual(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 4, direction: .previous
            ),
            1
        )
        XCTAssertEqual(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 4, direction: .next
            ),
            7
        )
    }

    func testAdjacentIndexStopsAtFilmstripEnds() {
        let visibleIndices = [1, 4, 7]

        XCTAssertNil(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 1, direction: .previous
            )
        )
        XCTAssertNil(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 7, direction: .next
            )
        )
    }

    func testRapidNavigationKeepsOnlyTheNewestPendingSource() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let third = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "third.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        await engine.gateSourcePreparation()
        let viewModel = makeAppViewModel(engine: engine)

        viewModel.openImage(url: first)
        _ = try await TestSynchronization.nextEvent(from: reader, "first source preparation start") {
            if case .sourcePreparationStarted = $0 { return true }
            return false
        } diagnostics: {
            "source preparations=\(await engine.sourcePreparationCount)"
        }
        viewModel.openImage(url: second)
        viewModel.openImage(url: third)
        let managedThirdURL = try XCTUnwrap(
            viewModel.collection.items.first(where: { $0.displayName == "third" })?.url
        )

        await engine.releaseSourcePreparation()
        _ = try await TestSynchronization.nextEvent(from: reader, "the newest source preparation") {
            if case .sourcePreparationCompleted(let source, _) = $0 {
                return source.backing == .url(managedThirdURL)
            }
            return false
        } diagnostics: {
            "source preparations=\(await engine.sourcePreparationCount)"
        }
        _ = try await TestSynchronization.nextEvent(from: reader, "the newest source preview") {
            if case .previewRequested(let request) = $0 {
                return request.source?.backing == .url(managedThirdURL)
            }
            return false
        } diagnostics: {
            "source preparations=\(await engine.sourcePreparationCount), previews=\(await engine.previewRequests.count)"
        }

        let preparationCount = await engine.sourcePreparationCount
        XCTAssertEqual(preparationCount, 2,
                       "one active preparation plus the newest pending source is the bound")
        XCTAssertEqual(viewModel.sourceSize, CGSize(width: 16, height: 12))
    }

    /// A pristine open admits one settled preview; an open with stored edits speculates with the
    /// identity document and then corrects with the stored one (LUMO-308, LUMO-317), so the
    /// second navigation here admits two. The corrective must still carry the stored document
    /// and reach the engine after the speculation.
    func testEachFilmstripOpenAdmitsItsSettledPreview() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "single-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "single-second.png", in: tempDirectory
        )
        let storedDocument = EditDocument(adjustments: [.exposure(ev: 0.6)])
        let store = makeInMemoryEditStore()
        try await store.save(
            storedDocument,
            for: EditSourceReference(assetID: .file(second), url: second)
        )

        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        let viewModel = makeAppViewModel(engine: engine, editStore: store)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let firstIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == first })
        let secondIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == second })

        viewModel.selectCollectionImage(at: firstIndex)
        _ = try await TestSynchronization.nextEvent(from: reader, "the first settled preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(first)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count)"
        }
        let firstPreviewCount = await engine.previewRequests.count
        XCTAssertEqual(firstPreviewCount, 1)

        viewModel.selectCollectionImage(at: secondIndex)
        let secondPreview = try await TestSynchronization.nextEvent(from: reader, "the edited settled preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(second)
                    && request.document == storedDocument
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count)"
        }
        guard case .previewCompleted(let request) = secondPreview else {
            return XCTFail("expected the edited photo preview to complete")
        }
        XCTAssertEqual(request.document, storedDocument)
        let previewCount = await engine.previewRequests.count
        XCTAssertEqual(
            previewCount, 3,
            "the stored-edit open corrects its speculative preview instead of replacing it silently"
        )
    }

    func testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "prefetch-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "prefetch-second.png", in: tempDirectory
        )
        let storedDocument = EditDocument(adjustments: [.exposure(ev: 0.8)])
        let store = makeInMemoryEditStore()
        try await store.save(
            storedDocument,
            for: EditSourceReference(assetID: .file(second), url: second)
        )

        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        let viewModel = makeAppViewModel(engine: engine, editStore: store)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let firstIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == first })

        viewModel.selectCollectionImage(at: firstIndex)
        _ = try await TestSynchronization.nextEvent(from: reader, "the first settled preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(first)
            }
            return false
        } diagnostics: {
            "previews=\(await engine.previewRequests.count)"
        }

        let prefetched = try await TestSynchronization.nextEvent(
            from: reader, "the stored-edit neighbor prefetch"
        ) {
            if case .textureRequested(let request) = $0 {
                return request.source?.backing == .url(second)
            }
            return false
        } diagnostics: {
            "textures=\(await engine.textureRequests.count)"
        }
        guard case .textureRequested(let request) = prefetched else {
            return XCTFail("expected the adjacent neighbor prefetch")
        }
        XCTAssertEqual(request.document, storedDocument)
        let encodeCount = await engine.encodeRequests.count
        let renderedNeighbor = await engine.renderRequests.contains { $0.source.backing == .url(second) }
        XCTAssertEqual(encodeCount, 0)
        XCTAssertFalse(
            renderedNeighbor,
            "adjacent warming must not use the PNG-producing render path"
        )
    }

    func testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "scale-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "scale-second.png", in: tempDirectory
        )

        let engine = FakeRenderEngine()
        let reader = FakeRenderEventReader(await engine.eventStream())
        let viewModel = makeAppViewModel(engine: engine)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let firstIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == first })
        let secondIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == second })

        viewModel.selectCollectionImage(at: firstIndex)
        _ = try await TestSynchronization.nextEvent(from: reader, "the first settled preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(first)
            }
            return false
        } diagnostics: { "previews=\(await engine.previewRequests.count)" }

        let prefetch = try await TestSynchronization.nextEvent(from: reader, "the scale-matched prefetch") {
            if case .textureRequested(let request) = $0 {
                return request.source?.backing == .url(second)
            }
            return false
        } diagnostics: { "textures=\(await engine.textureRequests.count)" }
        guard case .textureRequested(let prefetchRequest) = prefetch,
              let prefetchSource = prefetchRequest.source else {
            return XCTFail("expected a texture prefetch request")
        }

        viewModel.selectCollectionImage(at: secondIndex)
        let selected = try await TestSynchronization.nextEvent(from: reader, "the selected neighbor preview") {
            if case .previewCompleted(let request) = $0 {
                return request.source?.backing == .url(second)
            }
            return false
        } diagnostics: { "previews=\(await engine.previewRequests.count)" }
        guard case .previewCompleted(let selectedRequest) = selected else {
            return XCTFail("expected the selected neighbor preview")
        }

        XCTAssertEqual(
            RenderScaleKey(prefetchRequest.scale, nativeExtent: prefetchSource.nativeExtent),
            RenderScaleKey(selectedRequest.scale, nativeExtent: prefetchSource.nativeExtent)
        )
    }
}
