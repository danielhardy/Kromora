import Foundation
import XCTest

@testable import KromoraKit

final class PortablePackageTransactionTests: TempDirectoryTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testCommitJournalsStagesChecksumsAndPublishesAtomically() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: lease, now: now)

        try transaction.stage(data: Data("new asset".utf8), at: "Assets/aa/asset.json")
        try transaction.stage(data: Data("new membership".utf8), at: "Catalog/Membership/aa.json")
        try transaction.commit(now: now)

        XCTAssertEqual(
            try String(contentsOf: packageURL.appendingPathComponent("Assets/aa/asset.json")),
            "new asset")
        XCTAssertEqual(
            try String(contentsOf: packageURL.appendingPathComponent("Catalog/Membership/aa.json")),
            "new membership"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("Recovery/Transactions")
                    .appendingPathComponent("\(transaction.transactionID.uuidString).json").path))
        try lease.release()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("manifest.lock").path))
    }

    func testInjectedFailureAtEveryTransactionBoundaryRecoversWithoutPartialFiles() throws {
        for boundary in [
            PortablePackageTransactionBoundary.stage,
            .flush,
            .checksum,
            .publish,
        ] {
            let packageURL = try makePackage()
            let stateURL = packageURL.appendingPathComponent("State/a.txt")
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("old".utf8).write(to: stateURL)

            let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
            let injector = PortablePackageFaultInjector(failingAt: boundary)
            var transaction = try PortablePackageTransaction.begin(
                at: packageURL, lease: lease, now: now, faultInjector: injector
            )
            if boundary == .stage {
                XCTAssertThrowsError(
                    try transaction.stage(data: Data("new".utf8), at: "State/a.txt")
                ) { error in
                    XCTAssertEqual(
                        error as? PortablePackageTransactionError,
                        .injectedFailure(.stage)
                    )
                }
            } else {
                try transaction.stage(data: Data("new".utf8), at: "State/a.txt")
                try transaction.stage(data: Data("second".utf8), at: "State/b.txt")
                XCTAssertThrowsError(try transaction.commit(now: now)) { error in
                    XCTAssertEqual(
                        error as? PortablePackageTransactionError,
                        .injectedFailure(boundary)
                    )
                }
            }
            try lease.release()
            let report = try PortablePackageTransaction.recover(at: packageURL)
            XCTAssertEqual(report.recoveredTransactionIDs.count, 1, "boundary \(boundary)")
            XCTAssertEqual(try String(contentsOf: stateURL), "old", "boundary \(boundary)")
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: packageURL.appendingPathComponent("State/b.txt").path),
                "boundary \(boundary)"
            )
        }
    }

    func testLeaseContentionRenewalExpiryAndExplicitBreaking() throws {
        let packageURL = try makePackage()
        let first = try PortablePackageLease.acquire(
            at: packageURL, ownerID: UUID(), deviceName: "first-device", now: now, duration: 10
        )
        XCTAssertThrowsError(
            try PortablePackageLease.acquire(at: packageURL, ownerID: UUID(), now: now)
        ) { error in
            guard case .contended(let info) = error as? PortablePackageLeaseError else {
                return XCTFail("expected explicit lease contention, got \(error)")
            }
            XCTAssertEqual(info.deviceName, "first-device")
        }

        let injector = PortablePackageFaultInjector(failingAt: .leaseRenewal)
        XCTAssertThrowsError(try first.renew(now: now, faultInjector: injector)) { error in
            XCTAssertEqual(
                error as? PortablePackageTransactionError, .injectedFailure(.leaseRenewal))
        }
        XCTAssertTrue(first.isExpired(at: now.addingTimeInterval(11)))
        XCTAssertThrowsError(
            try PortablePackageLease.acquire(
                at: packageURL, ownerID: UUID(), now: now.addingTimeInterval(11))
        ) { error in
            guard case .expired = error as? PortablePackageLeaseError else {
                return XCTFail("expected explicit expired lease, got \(error)")
            }
        }
        try PortablePackageLease.breakExpired(at: packageURL, now: now.addingTimeInterval(11))
        let replacement = try PortablePackageLease.acquire(
            at: packageURL, ownerID: UUID(), now: now)
        try replacement.release()
    }

    func testLeaseLossPreventsPublishAndRecoveryCanRollBack() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
        let injector = PortablePackageFaultInjector(failingAt: .leaseLoss)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: lease, now: now, faultInjector: injector
        )
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now)) { error in
            XCTAssertEqual(error as? PortablePackageTransactionError, .injectedFailure(.leaseLoss))
        }
        try lease.release()
        _ = try PortablePackageTransaction.recover(at: packageURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("State/value.txt").path))
    }

    private func makePackage() throws -> URL {
        let url = tempDirectory.appendingPathComponent(
            "Library-\(UUID().uuidString).kromoralibrary")
        _ = try PortableLibraryPackage.create(at: url)
        return url
    }
}
