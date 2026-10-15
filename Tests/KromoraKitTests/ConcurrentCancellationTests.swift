import XCTest

/// Pins the property the ViewModels rely on after replacing `Task.detached { … }.value` with
/// `@concurrent` helpers: cancelling the awaiting task cancels the helper.
final class ConcurrentCancellationTests: XCTestCase {
    private actor Probe {
        private(set) var started = false
        private(set) var sawCancellation = false
        func markStarted() { started = true }
        func markCancelled() { sawCancellation = true }
    }

    @concurrent private static func pollUntilCancelled(_ probe: Probe) async {
        await probe.markStarted()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if Task.isCancelled {
                await probe.markCancelled()
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func testCancellingCallerCancelsConcurrentHelper() async {
        let probe = Probe()
        let caller = Task { await Self.pollUntilCancelled(probe) }
        while !(await probe.started) { try? await Task.sleep(for: .milliseconds(2)) }
        caller.cancel()
        await caller.value
        let sawCancellation = await probe.sawCancellation
        XCTAssertTrue(sawCancellation)
    }
}
