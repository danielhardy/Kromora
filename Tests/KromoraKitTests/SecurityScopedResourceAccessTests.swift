import Foundation
import XCTest
import os.lock

@testable import KromoraKit

final class SecurityScopedResourceAccessTests: XCTestCase {
    func testSuccessfulStartIsBalancedExactlyOnce() {
        let starts = OSAllocatedUnfairLock(initialState: 0)
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let url = URL(fileURLWithPath: "/tmp/security-scope-test")

        let access = SecurityScopedResourceAccess.startAccessing(
            url,
            start: { _ in starts.withLock { $0 += 1 }; return true },
            stop: { _ in stops.withLock { $0 += 1 } }
        )

        XCTAssertNotNil(access)
        XCTAssertEqual(starts.withLock { $0 }, 1)
        XCTAssertEqual(stops.withLock { $0 }, 0)
        access?.release()
        access?.release()
        XCTAssertEqual(stops.withLock { $0 }, 1)
    }

    func testFailedStartDoesNotStopAnUnownedScope() {
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let url = URL(fileURLWithPath: "/tmp/security-scope-denied")

        let access = SecurityScopedResourceAccess.startAccessing(
            url,
            start: { _ in false },
            stop: { _ in stops.withLock { $0 += 1 } }
        )

        XCTAssertNil(access)
        XCTAssertEqual(stops.withLock { $0 }, 0)
    }

    func testSystemGrantedScopeDoesNotIssueAnotherStart() {
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let url = URL(fileURLWithPath: "/tmp/security-scope-panel")
        let access = SecurityScopedResourceAccess.systemGranted(for: url) { _ in
            stops.withLock { $0 += 1 }
        }

        XCTAssertEqual(access.url, url)
        XCTAssertEqual(stops.withLock { $0 }, 0)
        access.release()
        XCTAssertEqual(stops.withLock { $0 }, 1)
    }
}
