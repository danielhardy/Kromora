import Dispatch
import Synchronization
import XCTest

@testable import KromoraKit

/// KRMA-1164: the off-caller digest path must never block its caller's thread on another
/// consumer's in-flight hash, and the hash bytes stay those of `RenderCacheHash.digest`.
final class DurableEditIdentityMemoConcurrencyTests: XCTestCase {
    /// Holds every hash at the gate until `open()`, so tests control what is "in flight".
    private final class HashGate: Sendable {
        private let started = Mutex(0)
        private let release = DispatchSemaphore(value: 0)

        var hasher: @Sendable (EditDocument) -> String {
            { [self] document in
                started.withLock { $0 += 1 }
                release.wait()
                return RenderCacheHash.digest(document)
            }
        }

        var startedCount: Int { started.withLock { $0 } }

        func open(permits: Int = 1) {
            for _ in 0..<permits { release.signal() }
        }

        func waitUntilStarted(_ count: Int) async throws {
            for _ in 0..<500 where startedCount < count {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertGreaterThanOrEqual(startedCount, count, "hash never started")
        }
    }

    private func recipe(exposure: Double, samples: Int = 4_000) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = exposure
        let stroke = BrushStroke(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            samples: (0..<samples).map {
                BrushSample(point: CGPoint(x: Double($0) / Double(samples), y: 0.5), pressure: 0.5)
            },
            radius: 0.04, feather: 0.5, flow: 0.8, density: 1)
        document.localAdjustments = [
            LocalAdjustmentLayer(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Brush",
                components: [
                    MaskComponent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                        name: "Brush",
                        source: .brush(BrushMaskDefinition(strokes: [stroke])))
                ],
                adjustments: LocalAdjustments(exposure: 0.4))
        ]
        return document
    }

    @MainActor
    func testMainActorKeepsRunningWhileAnotherConsumerIsHashing() async throws {
        let gate = HashGate()
        let memo = DurableEditIdentityMemo(hasher: gate.hasher)
        let document = recipe(exposure: 0.3)
        let leader = Task.detached { await memo.digestOffCaller(for: document) }
        try await gate.waitUntilStarted(1)

        // Both would have blocked on the entry mutex before KRMA-1164.
        XCTAssertNil(memo.cachedDigest(for: document))
        let finished = Mutex(false)
        let waiter = Task { @MainActor in
            let digest = await memo.digestOffCaller(for: document)
            finished.withLock { $0 = true }
            return digest
        }
        var heartbeat = 0
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(10))
            heartbeat += 1
        }
        XCTAssertEqual(heartbeat, 10)
        XCTAssertFalse(finished.withLock { $0 }, "the waiter must still be awaiting the gated hash")

        gate.open()
        let expected = RenderCacheHash.digest(document.visibleEditValue)
        let waited = await waiter.value
        let led = await leader.value
        XCTAssertEqual(waited, expected)
        XCTAssertEqual(led, expected)
        XCTAssertEqual(memo.cachedDigest(for: document), expected)
        XCTAssertEqual(memo.computationCount, 1)
        XCTAssertEqual(gate.startedCount, 1)
    }

    func testDifferentLargeRecipesHashWithoutSerializing() async throws {
        let gate = HashGate()
        let memo = DurableEditIdentityMemo(hasher: gate.hasher)
        let first = recipe(exposure: 0.1)
        let second = recipe(exposure: 0.2)
        async let a = memo.digestOffCaller(for: first)
        async let b = memo.digestOffCaller(for: second)
        // Both hashes are in flight at once: neither waits on the other's entry or the list lock.
        try await gate.waitUntilStarted(2)
        gate.open(permits: 2)
        let (firstDigest, secondDigest) = await (a, b)
        XCTAssertNotEqual(firstDigest, secondDigest)
        XCTAssertEqual(firstDigest, RenderCacheHash.digest(first.visibleEditValue))
        XCTAssertEqual(secondDigest, RenderCacheHash.digest(second.visibleEditValue))
        XCTAssertEqual(memo.computationCount, 2)
    }

    func testCancellingOneConsumerLeavesTheSharedHashAndOthersIntact() async throws {
        let gate = HashGate()
        let memo = DurableEditIdentityMemo(hasher: gate.hasher)
        let document = recipe(exposure: 0.3)
        let leader = Task.detached { await memo.digestOffCaller(for: document) }
        try await gate.waitUntilStarted(1)
        let consumers = (0..<3).map { _ in
            Task.detached { await memo.digestOffCaller(for: document) }
        }
        try await Task.sleep(for: .milliseconds(50))
        consumers[1].cancel()
        gate.open()

        let expected = RenderCacheHash.digest(document.visibleEditValue)
        let led = await leader.value
        XCTAssertEqual(led, expected)
        for consumer in consumers {
            let digest = await consumer.value
            XCTAssertEqual(digest, expected)
        }
        XCTAssertEqual(memo.computationCount, 1)
        XCTAssertEqual(gate.startedCount, 1)
    }

    func testCancellingTheComputingConsumerStillPublishesToWaiters() async throws {
        let gate = HashGate()
        let memo = DurableEditIdentityMemo(hasher: gate.hasher)
        let document = recipe(exposure: 0.3)
        let leader = Task.detached { await memo.digestOffCaller(for: document) }
        try await gate.waitUntilStarted(1)
        let waiter = Task.detached { await memo.digestOffCaller(for: document) }
        try await Task.sleep(for: .milliseconds(50))
        leader.cancel()
        gate.open()

        let expected = RenderCacheHash.digest(document.visibleEditValue)
        let waited = await waiter.value
        XCTAssertEqual(waited, expected)
        let led = await leader.value
        XCTAssertEqual(led, expected)
        XCTAssertEqual(memo.cachedDigest(for: document), expected)
    }

    func testSynchronousCallerJoinsAnInFlightAsyncComputation() async throws {
        let gate = HashGate()
        let memo = DurableEditIdentityMemo(hasher: gate.hasher)
        let document = recipe(exposure: 0.3)
        let leader = Task.detached { await memo.digestOffCaller(for: document) }
        try await gate.waitUntilStarted(1)
        let synchronous = Task.detached { memo.digest(for: document) }
        try await Task.sleep(for: .milliseconds(50))
        gate.open()
        let expected = RenderCacheHash.digest(document.visibleEditValue)
        let joined = await synchronous.value
        let led = await leader.value
        XCTAssertEqual(joined, expected)
        XCTAssertEqual(led, expected)
        XCTAssertEqual(memo.computationCount, 1)
    }
}
