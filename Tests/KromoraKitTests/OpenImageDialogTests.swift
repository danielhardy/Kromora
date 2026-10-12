import XCTest
import os
@testable import KromoraKit

private extension URL {
    /// The compatibility `libraryFolderURL` fixture is keyed by object identity and can go stale
    /// when addresses are reused across tests, so assert the package-embedded location directly.
    var isEmbeddedInPackage: Bool {
        pathComponents.contains { $0.hasSuffix(".kromoralibrary") }
    }
}

extension AppViewModel {
    /// Starts an Open Image import and suspends until its terminal summary is published.
    @discardableResult
    func openImagesAndWait(urls: [URL]) async -> ImportOutcomeSummary? {
        await withCheckedContinuation { continuation in
            openImages(urls: urls) { continuation.resume(returning: $0) }
        }
    }
}

@MainActor
final class OpenImageDialogTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                return XCTFail("timed out waiting for \(description)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst() async throws {
        let later = try Fixtures.writeGradientPNG(
            width: 24, height: 16, named: "later.png", in: tempDirectory
        )
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 24, named: "first.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        await viewModel.openImagesAndWait(urls: [later, first])

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["first", "later"])
        XCTAssertTrue(viewModel.collection.items.allSatisfy {
            $0.url?.isEmbeddedInPackage == true
        })
        XCTAssertTrue(viewModel.collection.items.allSatisfy { $0.imageData == nil })
        XCTAssertTrue(viewModel.navigation.isEdit)
        try await waitUntil("the first selected image") {
            viewModel.sourceName == first.lastPathComponent && viewModel.sourceImage != nil
        }
    }

    func testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "single.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        await viewModel.openImagesAndWait(urls: [image, image])

        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertTrue(viewModel.collection.items.first?.url?.isEmbeddedInPackage == true)
        XCTAssertTrue(viewModel.navigation.isEdit)
        try await waitUntil("the single image") {
            viewModel.sourceName == image.lastPathComponent && viewModel.sourceImage != nil
        }
    }

    func testEmptyOpenResultLeavesCurrentCollectionAndEditUntouched() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "existing.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        await viewModel.openImagesAndWait(urls: [image])
        try await waitUntil("the existing image") { viewModel.sourceImage != nil }

        let existingIDs = viewModel.collection.items.map(\.id)
        let existingSource = viewModel.sourceName
        await viewModel.openImagesAndWait(urls: [])

        XCTAssertEqual(viewModel.collection.items.map(\.id), existingIDs)
        XCTAssertEqual(viewModel.sourceName, existingSource)
        XCTAssertTrue(viewModel.navigation.isEdit)
    }

    func testOpenImagesReturnsBeforePublishingAndReportsOneTerminalSummary() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "async.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var completions: [ImportOutcomeSummary?] = []

        viewModel.openImages(urls: [image]) { completions.append($0) }

        // Publication needs a main-actor turn, so nothing can have been admitted yet.
        XCTAssertTrue(viewModel.collection.items.isEmpty)
        XCTAssertTrue(completions.isEmpty)
        try await waitUntil("the terminal summary") { !completions.isEmpty }
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first??.imported, 1)
        XCTAssertEqual(viewModel.collection.items.count, 1)
    }

    func testOpenImagesReturnsWhilePackageWorkerIsGated() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "gated.png", in: tempDirectory
        )
        let scheduler = ImageWorkScheduler()
        let blockerStarted = OSAllocatedUnfairLock(initialState: false)
        let releaseBlocker = OSAllocatedUnfairLock(initialState: false)
        defer { releaseBlocker.withLock { $0 = true } }
        XCTAssertTrue(scheduler.enqueuePackageIO(
            id: .init("open-image-dialog-worker-gate"), lane: .maintenance
        ) {
            blockerStarted.withLock { $0 = true }
            while !releaseBlocker.withLock({ $0 }) { await Task.yield() }
        })
        for _ in 0..<10_000 where !blockerStarted.withLock({ $0 }) { await Task.yield() }
        XCTAssertTrue(blockerStarted.withLock { $0 })

        let packageURL = tempDirectory.appendingPathComponent(
            "Gated Library.kromoralibrary", isDirectory: true
        )
        let session = try PortableLibrarySession(at: packageURL, scheduler: scheduler)
        let viewModel = makeAppViewModel(
            portablePackageURL: packageURL, portableLibrarySession: session
        )
        var completed = false
        viewModel.openImages(urls: [image]) { _ in completed = true }

        var sentinelRan = false
        await Task { @MainActor in sentinelRan = true }.value
        XCTAssertTrue(sentinelRan)
        XCTAssertFalse(completed)
        XCTAssertTrue(viewModel.collection.items.isEmpty)

        releaseBlocker.withLock { $0 = true }
        try await waitUntil("the gated import completion") { completed }
        XCTAssertEqual(viewModel.collection.items.count, 1)
    }

    func testSupersededOpenImagesDoesNotPublishOrComplete() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "first-superseded.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second-winner.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var supersededCompleted = false

        viewModel.openImages(urls: [first]) { _ in supersededCompleted = true }
        let summary = await viewModel.openImagesAndWait(urls: [second])

        XCTAssertEqual(summary?.imported, 1)
        XCTAssertFalse(supersededCompleted)
    }

    func testOpenImagesCompletesNilForEmptyInput() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let summary = await viewModel.openImagesAndWait(urls: [])
        XCTAssertNil(summary)
    }
}
