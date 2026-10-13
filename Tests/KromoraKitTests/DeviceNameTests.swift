import XCTest

@testable import KromoraKit

final class DeviceNameTests: TempDirectoryTestCase {
    func testCurrentReturnsNonEmptyName() {
        XCTAssertFalse(DeviceName.current().isEmpty)
    }

    func testLeaseRecordsInjectedDeviceName() throws {
        let lease = try PortablePackageLease.acquire(
            at: tempDirectory.appendingPathComponent("Pkg"), deviceName: "injected-mac")
        XCTAssertEqual(lease.info.deviceName, "injected-mac")
    }
}
