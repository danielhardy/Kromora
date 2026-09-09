import XCTest
@testable import LumoKit

@MainActor
final class FilmstripNavigationTests: TempDirectoryTestCase {
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

    func testEachFilmstripOpenSubmitsOneSettledPreview() async throws {
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
        XCTAssertEqual(previewCount, 2, "each navigation open must admit one settled preview")
    }
}
