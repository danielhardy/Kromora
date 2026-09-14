import AppKit
import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class ApplicationShellCoordinatorTests: TempDirectoryTestCase {
    func testMountAndUnmountNotificationsAreDebouncedIntoOneRefresh() async throws {
        let mediaCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let scheduler = ImageWorkScheduler()
        let maintenance = PortablePackageMaintenance(scheduler: scheduler)
        let coordinator = ApplicationShellCoordinator(
            mediaNotificationCenter: mediaCenter,
            applicationNotificationCenter: applicationCenter,
            scheduler: scheduler,
            maintenance: maintenance,
            packageURL: nil,
            packageLease: nil,
            idleDelay: .milliseconds(10)
        )
        var refreshCount = 0
        coordinator.onMediaChanged = { refreshCount += 1 }
        coordinator.start()

        mediaCenter.post(name: NSWorkspace.didMountNotification, object: nil)
        mediaCenter.post(name: NSWorkspace.didUnmountNotification, object: nil)
        try await waitUntil("debounced media refresh") { refreshCount == 1 }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(refreshCount, 1)
        await coordinator.shutdown()
    }

    func testActivationRefreshesAndAdmitsPortableMaintenance() async throws {
        let mediaCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let scheduler = ImageWorkScheduler()
        let maintenance = PortablePackageMaintenance(scheduler: scheduler)
        let packageURL = tempDirectory.appendingPathComponent("maintenance-package")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let coordinator = ApplicationShellCoordinator(
            mediaNotificationCenter: mediaCenter,
            applicationNotificationCenter: applicationCenter,
            scheduler: scheduler,
            maintenance: maintenance,
            packageURL: packageURL,
            packageLease: nil,
            idleDelay: .milliseconds(10)
        )
        var mediaRefreshCount = 0
        var activationCount = 0
        coordinator.onMediaChanged = { mediaRefreshCount += 1 }
        coordinator.onApplicationActivated = { activationCount += 1 }
        coordinator.start()

        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        try await waitUntil("application activation") { activationCount == 1 }
        try await waitUntil("maintenance admission") {
            scheduler.admissionLog.contains {
                $0.id == ImageWorkScheduler.JobID("portable-package-maintenance")
            }
        }
        XCTAssertEqual(mediaRefreshCount, 0, "the debounced refresh should not fire immediately")
        try await waitUntil("activation media refresh") { mediaRefreshCount == 1 }
        await coordinator.shutdown()
    }

    func testMaintenanceAdmissionGuardsMissingPackagesAndExistingJobs() async throws {
        let missingScheduler = ImageWorkScheduler()
        let missingMaintenance = PortablePackageMaintenance(scheduler: missingScheduler)
        let missingCoordinator = ApplicationShellCoordinator(
            mediaNotificationCenter: NotificationCenter(),
            applicationNotificationCenter: NotificationCenter(),
            scheduler: missingScheduler,
            maintenance: missingMaintenance,
            packageURL: tempDirectory.appendingPathComponent("missing-package"),
            packageLease: nil,
            idleDelay: .milliseconds(10)
        )
        missingCoordinator.scheduleMaintenance()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(
            missingScheduler.admissionLog.contains {
                $0.id == ImageWorkScheduler.JobID("portable-package-maintenance")
            }
        )
        await missingCoordinator.shutdown()

        let scheduler = ImageWorkScheduler()
        let maintenance = PortablePackageMaintenance(scheduler: scheduler)
        let packageURL = tempDirectory.appendingPathComponent("already-enqueued-package")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let gate = AsyncStream<Void>.makeStream()
        let jobID = ImageWorkScheduler.JobID("portable-package-maintenance")
        XCTAssertTrue(
            scheduler.enqueuePackageIO(id: jobID, lane: .maintenance) {
                for await _ in gate.stream { break }
            }
        )
        let coordinator = ApplicationShellCoordinator(
            mediaNotificationCenter: NotificationCenter(),
            applicationNotificationCenter: NotificationCenter(),
            scheduler: scheduler,
            maintenance: maintenance,
            packageURL: packageURL,
            packageLease: nil,
            idleDelay: .milliseconds(10)
        )
        coordinator.scheduleMaintenance()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(
            scheduler.admissionLog.filter { $0.id == jobID }.count, 1,
            "an already-admitted maintenance job must not be duplicated"
        )
        gate.continuation.yield(())
        gate.continuation.finish()
        await coordinator.shutdown()
    }

    func testShutdownCancelsPendingTasksAndRemovesObservers() async throws {
        let mediaCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let scheduler = ImageWorkScheduler()
        let maintenance = PortablePackageMaintenance(scheduler: scheduler)
        let coordinator = ApplicationShellCoordinator(
            mediaNotificationCenter: mediaCenter,
            applicationNotificationCenter: applicationCenter,
            scheduler: scheduler,
            maintenance: maintenance,
            packageURL: nil,
            packageLease: nil,
            idleDelay: .milliseconds(10)
        )
        var refreshCount = 0
        var activationCount = 0
        coordinator.onMediaChanged = { refreshCount += 1 }
        coordinator.onApplicationActivated = { activationCount += 1 }
        coordinator.start()
        mediaCenter.post(name: NSWorkspace.didMountNotification, object: nil)

        await coordinator.shutdown()
        try await Task.sleep(for: .milliseconds(250))
        mediaCenter.post(name: NSWorkspace.didUnmountNotification, object: nil)
        applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(activationCount, 0)
        XCTAssertTrue(scheduler.isIdle)
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
