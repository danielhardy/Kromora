import XCTest
@testable import KromoraKit

private actor ReadGate {
    private var continuations: [PortablePhotoAssetID: CheckedContinuation<VirtualCopyPresentation, Never>] = [:]
    private var waiters: [PortablePhotoAssetID: CheckedContinuation<Void, Never>] = [:]
    private(set) var reads: [PortablePhotoAssetID] = []

    func read(_ id: PortablePhotoAssetID) async -> VirtualCopyPresentation {
        reads.append(id)
        waiters.removeValue(forKey: id)?.resume()
        return await withCheckedContinuation { continuations[id] = $0 }
    }

    func waitUntilStarted(_ id: PortablePhotoAssetID) async {
        if reads.contains(id) { return }
        await withCheckedContinuation { waiters[id] = $0 }
    }

    func release(_ id: PortablePhotoAssetID, _ value: VirtualCopyPresentation) {
        continuations.removeValue(forKey: id)?.resume(returning: value)
    }
}

@MainActor
final class VirtualCopyMetadataCoordinatorTests: XCTestCase {
    private func make(_ gate: ReadGate) -> (VirtualCopyMetadataCoordinator, () -> Int) {
        var changes = 0
        let coordinator = VirtualCopyMetadataCoordinator(
            reader: { await gate.read($0) }, willChange: { changes += 1 }
        )
        return (coordinator, { changes })
    }

    func testGettersPerformNoReadsAndSameAssetDoesNotRefresh() async {
        let gate = ReadGate()
        let (coordinator, _) = make(gate)
        let a = PortablePhotoAssetID(), parent = PortablePhotoAssetID()
        coordinator.activeAssetChanged(to: a)
        await gate.waitUntilStarted(a)
        XCTAssertFalse(coordinator.canCreate)
        await gate.release(a, .available(copyOf: parent))
        await coordinator.settleForTest()
        for _ in 0..<5 { _ = coordinator.sourceDescription; _ = coordinator.canCreate }
        coordinator.activeAssetChanged(to: a)
        let reads = await gate.reads
        XCTAssertEqual(reads, [a])
        XCTAssertEqual(coordinator.sourceDescription, "Virtual copy of \(parent.raw.prefix(8))")
        XCTAssertTrue(coordinator.canCreate)
    }

    func testLateResultForPreviousAssetIsRejected() async {
        let gate = ReadGate()
        let (coordinator, _) = make(gate)
        let a = PortablePhotoAssetID(), b = PortablePhotoAssetID()
        coordinator.activeAssetChanged(to: a)
        await gate.waitUntilStarted(a)
        coordinator.activeAssetChanged(to: b)
        await gate.waitUntilStarted(b)
        await gate.release(a, .available(copyOf: PortablePhotoAssetID()))
        await Task.yield()
        XCTAssertEqual(coordinator.presentation, .unknown)
        await gate.release(b, .available(copyOf: nil))
        await coordinator.settleForTest()
        XCTAssertEqual(coordinator.presentation, .available(copyOf: nil))
        XCTAssertNil(coordinator.sourceDescription)
    }

    func testNoSourceClearsAndShutdownRejectsLatePublication() async {
        let gate = ReadGate()
        let (coordinator, _) = make(gate)
        let a = PortablePhotoAssetID()
        coordinator.activeAssetChanged(to: a)
        await gate.waitUntilStarted(a)
        coordinator.activeAssetChanged(to: nil)
        XCTAssertEqual(coordinator.presentation, .unknown)
        await gate.release(a, .available(copyOf: PortablePhotoAssetID()))
        await Task.yield()
        XCTAssertEqual(coordinator.presentation, .unknown, "cancelled read must not publish")
        coordinator.activeAssetChanged(to: a)
        await gate.waitUntilStarted(a)
        let shutdown = Task { await coordinator.shutdown() }
        await gate.release(a, .available(copyOf: nil))
        await shutdown.value
        XCTAssertEqual(coordinator.presentation, .unknown)
        coordinator.activeAssetChanged(to: a)
        XCTAssertEqual(coordinator.presentation, .unknown)
    }

    func testMainActorStaysResponsiveWhileReaderIsBlocked() async {
        let gate = ReadGate()
        let (coordinator, _) = make(gate)
        let a = PortablePhotoAssetID()
        coordinator.activeAssetChanged(to: a)
        await gate.waitUntilStarted(a)
        var sentinel = false
        await MainActor.run { sentinel = true }
        XCTAssertTrue(sentinel)
        await gate.release(a, .unknown)
        await coordinator.shutdown()
    }

    func testRealPackageOriginalAndCopyAndMissingRecord() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VCM-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let packageURL = dir.appendingPathComponent("L.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = dir.appendingPathComponent("p.jpg")
        try Data("portrait".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()
        let original = try XCTUnwrap(imported.imported.first).assetID
        let session = try PortableLibrarySession(at: packageURL)
        let copy = try session.createVirtualCopy(of: original).assetID

        let coordinator = VirtualCopyMetadataCoordinator(
            reader: VirtualCopyMetadataCoordinator.packageReader(package), willChange: {}
        )
        coordinator.activeAssetChanged(to: copy)
        await coordinator.settleForTest()
        XCTAssertEqual(coordinator.sourceDescription, "Virtual copy of \(original.raw.prefix(8))")
        coordinator.activeAssetChanged(to: original)
        XCTAssertNil(coordinator.sourceDescription, "previous label must not leak")
        await coordinator.settleForTest()
        XCTAssertNil(coordinator.sourceDescription)
        XCTAssertTrue(coordinator.canCreate)
        coordinator.activeAssetChanged(to: PortablePhotoAssetID())
        await coordinator.settleForTest()
        XCTAssertFalse(coordinator.canCreate)
        await coordinator.shutdown()
    }
}

@MainActor
private extension VirtualCopyMetadataCoordinator {
    /// Awaits the in-flight read without shutting the coordinator down.
    func settleForTest() async { await pendingReadForTest?.value }
}
