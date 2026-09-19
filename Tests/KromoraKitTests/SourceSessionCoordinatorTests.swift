import AppKit
import XCTest

@testable import KromoraKit

@MainActor
final class SourceSessionCoordinatorTests: XCTestCase {
    private func waitUntil(
        _ description: String,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "source session did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testNavigationDropsStalePreparationPublication() async throws {
        let fake = FakeRenderEngine()
        await fake.gateSourcePreparation()
        let coordinator = SourceSessionCoordinator(
            engine: fake,
            editStore: EditDocumentStore.makeInMemoryProjectionStore(),
            embeddedFirstFrameProvider: { _ in nil }
        )
        var prepared: [SourceSessionCoordinator.PreparationPublication] = []
        coordinator.onPreparation = { prepared.append($0) }

        let first = SourceImportPlan(
            name: "first.ARW", url: URL(fileURLWithPath: "/tmp/first.ARW"), data: nil
        )
        let second = SourceImportPlan(
            name: "second.ARW", url: URL(fileURLWithPath: "/tmp/second.ARW"), data: nil
        )
        coordinator.begin(plan: first, editSessionRevision: 0, hadInMemorySession: false)
        try await waitUntil("first preparation") { await fake.sourcePreparationCount == 1 }
        coordinator.begin(plan: second, editSessionRevision: 0, hadInMemorySession: false)

        await fake.releaseSourcePreparation()
        try await waitUntil("second preparation") { prepared.count == 1 }
        XCTAssertEqual(prepared.first?.request.plan.name, "second.ARW")
        XCTAssertEqual(coordinator.sourceRevision, 2)

        await coordinator.shutdown()
    }

    func testFailedOpenKeepsPublishedSourceProbesAlive() async throws {
        let fake = FakeRenderEngine()
        await fake.gateProbe()
        let coordinator = SourceSessionCoordinator(
            engine: fake,
            editStore: EditDocumentStore.makeInMemoryProjectionStore(),
            embeddedFirstFrameProvider: { _ in nil }
        )
        var capabilities: [SourceSessionCoordinator.CapabilitiesPublication] = []
        var failures: [String] = []
        coordinator.onCapabilities = { capabilities.append($0) }
        coordinator.onFailure = { _, message in failures.append(message) }

        let good = SourceImportPlan(
            name: "displayed.ARW", url: URL(fileURLWithPath: "/tmp/displayed.ARW"), data: nil
        )
        let failing = SourceImportPlan(
            name: "unreadable.bin", url: nil, data: Data("not an image".utf8)
        )
        coordinator.begin(plan: good, editSessionRevision: 0, hadInMemorySession: false)
        try await waitUntil("the displayed source probe") { await fake.capabilityProbeCount == 1 }

        coordinator.begin(plan: failing, editSessionRevision: 0, hadInMemorySession: false)
        try await waitUntil("the failed open") { failures.count == 1 }

        await fake.releaseProbe()
        try await waitUntil("the displayed source probe to publish") { capabilities.count == 1 }
        XCTAssertEqual(capabilities.first?.request.plan.name, "displayed.ARW")

        await coordinator.shutdown()
    }

    func testSuccessfulOpenSupersedesThePreviousProbe() async throws {
        let fake = FakeRenderEngine()
        await fake.gateProbe()
        let coordinator = SourceSessionCoordinator(
            engine: fake,
            editStore: EditDocumentStore.makeInMemoryProjectionStore(),
            embeddedFirstFrameProvider: { _ in nil }
        )
        var prepared: [SourceSessionCoordinator.PreparationPublication] = []
        var capabilities: [SourceSessionCoordinator.CapabilitiesPublication] = []
        coordinator.onPreparation = { prepared.append($0) }
        coordinator.onCapabilities = { capabilities.append($0) }

        let first = SourceImportPlan(
            name: "first.ARW", url: URL(fileURLWithPath: "/tmp/first.ARW"), data: nil
        )
        let second = SourceImportPlan(
            name: "second.ARW", url: URL(fileURLWithPath: "/tmp/second.ARW"), data: nil
        )
        coordinator.begin(plan: first, editSessionRevision: 0, hadInMemorySession: false)
        try await waitUntil("the first source probe") { await fake.capabilityProbeCount == 1 }

        coordinator.begin(plan: second, editSessionRevision: 0, hadInMemorySession: false)
        try await waitUntil("the second source preparation") { prepared.count == 2 }
        try await waitUntil("both probes to be admitted") { await fake.capabilityProbeCount == 2 }

        await fake.releaseProbe()
        try await waitUntil("the replacement probe to publish") { capabilities.count == 1 }
        XCTAssertEqual(capabilities.first?.request.plan.name, "second.ARW")

        await coordinator.shutdown()
    }

    func testPreviewPresentationOwnsGenerationsAndCacheIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraPreviewPresentation-\(UUID().uuidString)")
        let cache = PreviewDiskCache(directory: directory, capBytes: 1_000_000)
        let coordinator = PreviewPresentationCoordinator(cache: cache)
        XCTAssertEqual(coordinator.displayRevision, 0)
        XCTAssertEqual(coordinator.comparisonRevision, 0)

        coordinator.resetForSource()
        XCTAssertEqual(coordinator.displayRevision, 1)
        XCTAssertEqual(coordinator.comparisonRevision, 1)
        coordinator.advanceDisplayRevision()
        coordinator.advanceComparisonRevision()
        XCTAssertEqual(coordinator.displayRevision, 2)
        XCTAssertEqual(coordinator.comparisonRevision, 2)

        let source = ImageSource(
            backing: .data(Data("preview".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 100, height: 80)
        )
        let request = RenderRequest(
            source: source, document: EditDocument(), targetSize: CGSize(width: 100, height: 80),
            quality: .preview
        )
        XCTAssertEqual(
            coordinator.cacheKey(for: request).identity,
            source.cacheIdentity
        )
        try? FileManager.default.removeItem(at: directory)
    }
}
