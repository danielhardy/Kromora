import Foundation
import XCTest
import os.lock

@testable import KromoraKit

@MainActor
final class PortableLibrarySessionTests: TempDirectoryTestCase {
    private final class TestLeaseClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date

        init(_ value: Date) { self.value = value }

        func now() -> Date {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        func advance(_ seconds: TimeInterval) {
            lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock()
        }
    }

    func testDefaultPackageLivesInPicturesWithCanonicalName() {
        let packageURL = KromoraStorage.defaultPortableLibraryPackageURL
        XCTAssertEqual(packageURL.lastPathComponent, KromoraStorage.portableLibraryPackageName)
        XCTAssertEqual(
            packageURL.deletingLastPathComponent().lastPathComponent,
            "Pictures"
        )
    }

    func testStoragePolicyKeepsProjectionAndCachesOutsidePackage() {
        let packageURL = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        let indexURL = KromoraStorage.indexURL(
            for: UUID(uuidString: "D90B0CF5-85E5-4E5E-AD66-3E3B44F9B8B0")!
        )
        XCTAssertTrue(indexURL.path.contains("Application Support/Kromora/Indexes"))
        XCTAssertFalse(indexURL.path.hasPrefix(packageURL.path))
        XCTAssertTrue(
            KromoraStorage.cacheDirectory(named: "Masks").path.contains("Caches/Kromora/Masks")
        )
        XCTAssertTrue(
            PreviewDiskCache.packageDirectory(for: packageURL).path.hasPrefix(packageURL.path)
        )
        XCTAssertEqual(
            PreviewDiskCache.packageDirectory(for: packageURL).deletingLastPathComponent(),
            packageURL.appendingPathComponent("Derived", isDirectory: true)
        )
    }

    func testPackageReopensAfterDisposableProjectionAndDerivedDataAreRemoved() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Disposable.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("Index/LibraryIndex.store")
        let sourceURL = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "source.jpg", in: tempDirectory
        )
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        let result = try session.importURLs([sourceURL])
        let assetID = try XCTUnwrap(result.imported.first?.assetID)
        let materialized = try XCTUnwrap(session.materializedAssets().first)
        let store = EditDocumentStore(package: session.package, lease: session.lease)
        try await store.save(
            EditDocument(adjustments: [.exposure(ev: 0.5)]),
            for: EditSourceReference(
                assetID: .file(try XCTUnwrap(materialized.url)),
                portableIdentity: materialized.source.portableIdentity,
                url: materialized.url
            )
        )
        try session.lease.release()

        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("Derived"))
        try FileManager.default.removeItem(at: indexURL)

        let reopened = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        let restored = try XCTUnwrap(reopened.materializedAssets().first)
        XCTAssertEqual(restored.source.portableIdentity.assetID, assetID)
        let reopenedStore = EditDocumentStore(package: reopened.package, lease: reopened.lease)
        let loaded = await reopenedStore.load(for: EditSourceReference(
            assetID: .file(try XCTUnwrap(restored.url)),
            portableIdentity: restored.source.portableIdentity,
            url: restored.url
        ))
        XCTAssertEqual(loaded.document.adjustments, [.exposure(ev: 0.5)])
        XCTAssertTrue(loaded.found)
        try reopened.lease.release()
    }

    func testFirstLaunchReopenAndPackageCopyPreserveImportedOriginals() async throws {
        let packageURL = tempDirectory.appendingPathComponent(
            KromoraStorage.portableLibraryPackageName
        )
        let sourceURL = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "imported.jpg", in: tempDirectory
        )
        let assetID: PortablePhotoAssetID

        do {
            let session = try PortableLibrarySession(at: packageURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))
            let result = try session.importURLs([sourceURL])
            assetID = try XCTUnwrap(result.imported.first?.assetID)
            XCTAssertEqual(session.assetCount, 1)
            let materialized = try XCTUnwrap(session.materializedAssets().first)
            let materializedURL = try XCTUnwrap(materialized.url)
            XCTAssertTrue(materializedURL.path.hasPrefix(packageURL.path))
            XCTAssertNotEqual(materializedURL, sourceURL)
            try session.updateLibraryState(for: assetID, rating: 4, flag: .pick)
            let store = EditDocumentStore(
                package: session.package,
                lease: session.lease,
                modelContainer: makeInMemoryEditContainer()
            )
            let reference = EditSourceReference(
                assetID: .file(materializedURL),
                portableIdentity: materialized.source.portableIdentity,
                url: materializedURL
            )
            try await store.save(
                EditDocument(adjustments: [.exposure(ev: 0.75)]),
                for: reference
            )
            try session.lease.release()
        }

        let reopened = try PortableLibrarySession(at: packageURL)
        XCTAssertEqual(reopened.assetCount, 1)
        XCTAssertEqual(reopened.page(at: 0).items.first?.assetID, assetID)
        let reopenedAssets = try reopened.materializedAssets()
        XCTAssertEqual(reopenedAssets.first?.rating, 4)
        XCTAssertEqual(reopenedAssets.first?.flag, .pick)
        let reopenedAsset = try XCTUnwrap(reopenedAssets.first)
        let reopenedURL = try XCTUnwrap(reopenedAsset.url)
        let reopenedReference = EditSourceReference(
            assetID: .file(reopenedURL),
            portableIdentity: reopenedAsset.source.portableIdentity,
            url: reopenedURL
        )
        let reopenedStore = EditDocumentStore(
            package: reopened.package,
            lease: reopened.lease,
            modelContainer: makeInMemoryEditContainer()
        )
        let loaded = await reopenedStore.load(for: reopenedReference)
        XCTAssertEqual(loaded.document.adjustments, [.exposure(ev: 0.75)])
        XCTAssertTrue(loaded.found)
        try reopened.lease.release()

        let copyURL = tempDirectory.appendingPathComponent("Copied.kromoralibrary")
        try FileManager.default.copyItem(at: packageURL, to: copyURL)
        let copied = try PortableLibrarySession(at: copyURL)
        let copiedAsset = try XCTUnwrap(copied.materializedAssets().first)
        let copiedURL = try XCTUnwrap(copiedAsset.url)
        XCTAssertTrue(copiedURL.path.hasPrefix(copyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
        try copied.lease.release()
    }

    func testExistingInvalidPackageFailsClosedWithoutReplacement() throws {
        let packageURL = tempDirectory.appendingPathComponent("Broken.kromoralibrary")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let sentinelURL = packageURL.appendingPathComponent("do-not-replace")
        try Data("preserve me".utf8).write(to: sentinelURL)

        XCTAssertThrowsError(try PortableLibrarySession(at: packageURL))
        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("preserve me".utf8))
    }

    func testExpiredWriterLeaseStaysClosedUntilRecoveryIsRequested() throws {
        let packageURL = tempDirectory.appendingPathComponent("Expired.kromoralibrary")
        let sourceURL = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "keep.jpg", in: tempDirectory
        )
        let indexURL = tempDirectory.appendingPathComponent("ExpiredIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        _ = try session.importURLs([sourceURL])
        try session.lease.release()

        let stale = try PortablePackageLease.acquire(
            at: packageURL, deviceName: "killed-swift-run", duration: -1
        )
        XCTAssertThrowsError(
            try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        ) { error in
            guard case .expired(let info) = error as? PortablePackageLeaseError else {
                return XCTFail("expected expired lease, got \(error)")
            }
            XCTAssertEqual(info.deviceName, "killed-swift-run")
            XCTAssertEqual(
                (error as Error).localizedDescription,
                "The previous session on killed-swift-run (pid \(info.processID)) did not close cleanly, so the package writer lease has expired"
            )
        }

        let recovered = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, recoverExpiredLease: true
        )
        XCTAssertEqual(recovered.assetCount, 1)
        try recovered.lease.release()
        _ = stale
    }

    func testShortLeaseHeartbeatKeepsImportsWritablePastTwoDurations() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Heartbeat.kromoralibrary")
        let clock = TestLeaseClock(Date(timeIntervalSince1970: 10_000))
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(
            at: packageURL,
            leaseDuration: 3,
            clock: .init(
                now: { clock.now() },
                // Keep the production heartbeat suspended; renewAfterWake drives the same
                // package-I/O operation deterministically in this test.
                sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
            ),
            scheduler: scheduler
        )
        let heartbeatID = ImageWorkScheduler.JobID(
            "portable-package-lease-heartbeat-\(session.lease.ownerID.uuidString)"
        )
        for _ in 0..<7 {
            clock.advance(1)
            session.renewAfterWake()
            for _ in 0..<5_000 {
                if !scheduler.contains(heartbeatID) { break }
                await Task.yield()
            }
            XCTAssertGreaterThanOrEqual(session.lease.info.heartbeatAt, clock.now())
        }
        XCTAssertGreaterThan(
            clock.now().timeIntervalSince1970,
            session.lease.info.acquiredAt.timeIntervalSince1970 + 6
        )

        let source = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "long-session.jpg", in: tempDirectory
        )
        let result = try session.importURLs([source])
        XCTAssertEqual(result.imported.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
        await session.shutdown()
    }

    func testLeaseLossDuringSessionStopsWritesWithDistinctError() async throws {
        let packageURL = tempDirectory.appendingPathComponent("LostHeartbeat.kromoralibrary")
        let clock = TestLeaseClock(Date(timeIntervalSince1970: 20_000))
        let session = try PortableLibrarySession(
            at: packageURL,
            leaseDuration: 2,
            clock: .init(now: { clock.now() }),
            scheduler: nil
        )
        clock.advance(3)
        try FileManager.default.removeItem(at: packageURL.appendingPathComponent("manifest.lock"))

        XCTAssertThrowsError(try session.importData(Data("dirty snapshot".utf8), name: "lost.jpg")) {
            XCTAssertEqual($0 as? PortablePackageLeaseError, .lostDuringSession)
        }
        await session.shutdown()
    }

    func testShutdownWaitsForHeartbeatBeforeReleasingLease() async throws {
        let packageURL = tempDirectory.appendingPathComponent("ShutdownHeartbeat.kromoralibrary")
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(
            at: packageURL,
            leaseDuration: 3,
            scheduler: scheduler
        )

        await session.shutdown()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("manifest.lock").path
            )
        )
        session.renewAfterWake()
        XCTAssertFalse(scheduler.contains(.init("portable-package-lease-heartbeat-\(session.lease.ownerID.uuidString)")))
    }

    func testAsyncImportPublishesProgressAndAppliesMembershipDelta() async throws {
        let packageURL = tempDirectory.appendingPathComponent("AsyncImport.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("AsyncImport.index")
        let sourceURL = try Fixtures.writeJPEG(
            width: 24, height: 16, orientation: 1, named: "async.jpg", in: tempDirectory
        )
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, scheduler: scheduler
        )

        let handle = try session.startImportURLs([sourceURL])
        var progress: [PortablePackageImportProgress] = []
        for await value in handle.progress { progress.append(value) }
        let result = try await handle.value()

        XCTAssertEqual(result.imported.count, 1)
        XCTAssertEqual(result.indexDelta.upserts.count, 1)
        XCTAssertEqual(progress.first?.phase, .preparing)
        XCTAssertEqual(progress.last?.phase, .finished)
        XCTAssertEqual(session.assetCount, 1)
        for _ in 0..<5_000 {
            if !scheduler.contains(.init("portable-package-index-write-\(session.lease.ownerID.uuidString)")) {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(try LibraryIndexProjection.load(from: indexURL).count, 1)
        await session.shutdown()
    }

    func testAsyncImportCancellationLeavesNoPublishedAsset() async throws {
        let packageURL = tempDirectory.appendingPathComponent("AsyncCancelled.kromoralibrary")
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(at: packageURL, scheduler: scheduler)
        let handle = try session.startImportData(
            Data(repeating: 0x5a, count: 8 * 1024 * 1024), name: "cancelled.raw"
        )

        let cancellation = Task { @MainActor in
            for await value in handle.progress where value.phase != .preparing {
                if value.phase == .staging {
                    handle.cancel()
                    return
                }
            }
        }
        do {
            _ = try await handle.value()
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        await cancellation.value
        await scheduler.cancelAllAndWait()
        XCTAssertEqual(session.assetCount, 0)
        for shard in PortableLibraryPackage.allShards {
            XCTAssertTrue(try session.package.readMembershipShard(shard).entries.isEmpty)
        }
        await session.shutdown()
    }

    func testCancellingQueuedImportTerminatesProgressStream() async throws {
        // A job cancelled while still queued never runs its operation body, so the progress
        // sink must be finished from the terminal callback. Otherwise a `for await` consumer
        // (including LibraryImportCoordinator.shutdown) would wait on the stream forever.
        let packageURL = tempDirectory.appendingPathComponent("QueuedCancel.kromoralibrary")
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(at: packageURL, scheduler: scheduler)

        // Occupy the single package-I/O slot so the import below stays queued.
        let blockerStarted = OSAllocatedUnfairLock(initialState: false)
        let blockerRelease = OSAllocatedUnfairLock(initialState: false)
        XCTAssertTrue(scheduler.enqueuePackageIO(id: .init("verification-blocker"), lane: .maintenance) {
            blockerStarted.withLock { $0 = true }
            while !blockerRelease.withLock({ $0 }) { await Task.yield() }
        })
        for _ in 0..<1_000 {
            if blockerStarted.withLock({ $0 }) { break }
            await Task.yield()
        }
        XCTAssertTrue(blockerStarted.withLock { $0 })
        XCTAssertEqual(scheduler.runningPackageIOCount, 1)

        let handle = try session.startImportData(
            Data(repeating: 0xA5, count: 1024), name: "queued.raw"
        )
        for _ in 0..<1_000 {
            if scheduler.pendingPackageIOCount > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(scheduler.runningPackageIOCount, 1)
        XCTAssertGreaterThanOrEqual(scheduler.pendingPackageIOCount, 1)

        handle.cancel()

        var progressCount = 0
        for await _ in handle.progress { progressCount += 1 }
        // The queued operation never ran, so no phase was ever yielded; the stream still
        // has to terminate instead of suspending the loop above forever.
        XCTAssertEqual(progressCount, 0)
        do {
            _ = try await handle.value()
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(session.assetCount, 0)

        blockerRelease.withLock { $0 = true }
        await scheduler.cancelAllAndWait()
        await session.shutdown()
    }
}
