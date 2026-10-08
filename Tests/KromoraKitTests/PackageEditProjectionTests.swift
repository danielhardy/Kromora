import Foundation
import XCTest
import os.lock

@testable import KromoraKit

final class PackageEditProjectionTests: TempDirectoryTestCase {
    private struct LegacyGeometryAsset: Sendable {
        let assetID: PortablePhotoAssetID
        let shardName: String
        let document: EditDocument
        let expectedRatio: Double
    }

    private func makeLegacyGeometryPackage(
        name: String, assetCount: Int
    ) throws -> (PortableLibraryPackage, PortablePackageLease, [LegacyGeometryAsset]) {
        let packageURL = tempDirectory.appendingPathComponent("\(name).kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let crops = [
            CropAdjustments(normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            CropAdjustments(normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.5)),
            CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0, width: 0.75, height: 0.5))
        ]
        let rotations: [ImageRotation] = [.zero, .clockwise90, .counterClockwise90]
        var assets: [LegacyGeometryAsset] = []
        var selectedShards = Set<String>()
        var ordinal = 0
        while assets.count < assetCount {
            let sourceURL = try Fixtures.writeJPEG(
                width: 24 + ordinal * 2, height: 12, orientation: 1,
                named: "\(name)-\(ordinal).jpg", in: tempDirectory
            )
            let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
            let assetID = try XCTUnwrap(imported.imported.first?.assetID)
            let shardName = PortableLibraryPackage.shard(for: assetID)
            ordinal += 1
            guard selectedShards.insert(shardName).inserted else { continue }

            let width = 24 + (ordinal - 1) * 2
            var shard = try package.readMembershipShard(shardName)
            if let index = shard.entries.firstIndex(where: { $0.assetID == assetID }) {
                shard.entries[index].summary.dimensions = PhotoPixelDimensions(width: width, height: 12)
                shard.entries[index].summary.aspectRatio = Double(width) / 12
                try package.writeMembershipShard(shard)
            }

            let document = EditDocument(
                crop: crops[assets.count % crops.count],
                rotation: rotations[assets.count % rotations.count]
            )
            let commit = try package.commitEditRevision(
                for: assetID, document: document, lease: lease
            )
            let expectedRatio = try XCTUnwrap(commit.membership?.summary.presentedAspectRatio)
            assets.append(LegacyGeometryAsset(
                assetID: assetID, shardName: shardName,
                document: document, expectedRatio: expectedRatio
            ))
        }

        for shardName in Set(assets.map(\.shardName)) {
            var shard = try package.readMembershipShard(shardName)
            let assetIDs = Set(assets.filter { $0.shardName == shardName }.map(\.assetID))
            for index in shard.entries.indices where assetIDs.contains(shard.entries[index].assetID) {
                shard.entries[index].summary.presentedAspectRatio = nil
            }
            try package.writeMembershipShard(shard)
        }
        return (package, lease, assets)
    }

    func testPackageIsCanonicalAndProjectionRebuildPreservesExactDocument() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Canonical.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("package source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID,
            sourceFingerprint: .data(Data("package source".utf8), decoderVersion: "test")
        )
        let reference = EditSourceReference(
            assetID: .file(sourceURL), portableIdentity: identity, url: sourceURL
        )
        var document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.73),
            adjustments: [.exposure(ev: 0.41)],
            lut: LUTSettings(lutID: LUTID(raw: "look.cube"), intensity: 0.37)
        )
        document.crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.12, y: 0.08, width: 0.7, height: 0.81),
            aspectRatio: .freeform
        )

        let store = EditDocumentStore(package: package, lease: lease)
        try await store.save(document, for: reference)

        let sidecar = try package.readEditSidecar(for: asset.assetID)
        XCTAssertEqual(sidecar.native.document, document)
        XCTAssertEqual(sidecar.xmp.document, document)

        // Evicting the bounded cache does not affect the canonical package.
        try await store.delete(for: reference)
        let fromPackage = await store.load(for: reference)
        XCTAssertEqual(fromPackage.document, document)
        XCTAssertTrue(fromPackage.found)
        let cacheCount = await store.cacheCount
        XCTAssertEqual(cacheCount, 1)
    }

    func testNamedSnapshotAndDurableHistorySurviveStoreReload() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Snapshots.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("snapshot.jpg")
        try Data("snapshot source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID,
            sourceFingerprint: .data(Data("snapshot source".utf8), decoderVersion: "test")
        )
        let reference = EditSourceReference(assetID: .file(sourceURL), portableIdentity: identity)
        let store = EditDocumentStore(package: package, lease: lease)
        let document = EditDocument(light: .init(exposure: 0.8))
        try await store.saveSnapshot(document, named: "Warm sunset", for: reference)

        let history = try await store.history(for: reference)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].snapshotName, "Warm sunset")
        XCTAssertEqual(history[0].document, document)

        let reopened = try PortableLibraryPackage.open(at: packageURL)
        let reopenedHistory = try reopened.readEditHistory(for: asset.assetID)
        XCTAssertEqual(reopenedHistory, history)
    }

    func testPresentedAspectRatioRepairResumesAtCommittedShardBoundaries() async throws {
        let (package, lease, assets) = try makeLegacyGeometryPackage(
            name: "LegacyGeometryResume", assetCount: 3
        )
        defer { try? lease.release() }
        let shardNames = assets.map(\.shardName)

        for cancellationPoint in 1..<assets.count {
            let committedBatches = OSAllocatedUnfairLock(initialState: 0)
            let shouldCancel = OSAllocatedUnfairLock(initialState: false)
            do {
                _ = try await package.repairPresentedAspectRatios(
                    lease: lease,
                    shardNames: shardNames,
                    isCancelled: { shouldCancel.withLock { $0 } },
                    onBatch: { _ in
                        committedBatches.withLock { $0 += 1 }
                        shouldCancel.withLock { $0 = true }
                    }
                )
                XCTFail("repair should stop after one committed shard")
            } catch is CancellationError {
                XCTAssertEqual(committedBatches.withLock { $0 }, 1)
            }

            XCTAssertNoThrow(try PortableLibraryPackage.open(at: package.rootURL))
            let repairedCount = try assets.filter { asset in
                try package.readMembershipShard(asset.shardName).entries
                    .first { $0.assetID == asset.assetID }?.summary.presentedAspectRatio
                    == asset.expectedRatio
            }.count
            XCTAssertEqual(repairedCount, cancellationPoint)
        }

        _ = try await package.repairPresentedAspectRatios(
            lease: lease, shardNames: shardNames
        )
        XCTAssertNoThrow(try PortableLibraryPackage.open(at: package.rootURL))
        for asset in assets {
            let summary = try XCTUnwrap(
                package.readMembershipShard(asset.shardName).entries
                    .first { $0.assetID == asset.assetID }?.summary
            )
            let ratio = try XCTUnwrap(summary.presentedAspectRatio)
            XCTAssertEqual(ratio, asset.expectedRatio, accuracy: 1e-9)
        }
    }

    func testPresentedAspectRatioRepairHandlesDenseShardWithoutRecords() async throws {
        let (package, lease, assets) = try makeLegacyGeometryPackage(
            name: "LegacyGeometryDense", assetCount: 1
        )
        defer { try? lease.release() }
        let asset = try XCTUnwrap(assets.first)
        var shard = try package.readMembershipShard(asset.shardName)
        let template = try XCTUnwrap(shard.entries.first)
        let denseCount = 4_000
        for ordinal in 0..<denseCount {
            let uuidString = asset.shardName.uppercased()
                + String(format: "%06X-0000-4000-8000-%012X", ordinal, ordinal)
            let id = PortablePhotoAssetID(uuid: try XCTUnwrap(UUID(uuidString: uuidString)))
            XCTAssertEqual(PortableLibraryPackage.shard(for: id), asset.shardName)
            var summary = template.summary
            summary.presentedAspectRatio = nil
            shard.entries.append(PortablePackageMembershipEntry(
                assetID: id,
                recordPath: "Assets/\(asset.shardName)/\(id.raw)/asset.json", summary: summary
            ))
        }
        try package.writeMembershipShard(shard)

        let repaired = try package.repairPresentedAspectRatioShard(
            asset.shardName, lease: lease
        )
        XCTAssertEqual(repaired.count, denseCount + 1)
        let reread = try package.readMembershipShard(asset.shardName)
        XCTAssertTrue(reread.entries.allSatisfy { $0.summary.presentedAspectRatio != nil })
        XCTAssertEqual(
            reread.entries.first { $0.assetID == asset.assetID }?.summary.presentedAspectRatio
                ?? 0,
            asset.expectedRatio, accuracy: 1e-9
        )
    }

    func testEditCommitDuringPresentedAspectRatioRepairWins() async throws {
        let (package, lease, assets) = try makeLegacyGeometryPackage(
            name: "LegacyGeometryEditRace", assetCount: 1
        )
        defer { try? lease.release() }
        let asset = try XCTUnwrap(assets.first)
        let userDocument = EditDocument(
            crop: CropAdjustments(normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            rotation: .clockwise90
        )
        let expectedRatio = try XCTUnwrap(
            package.readMembershipShard(asset.shardName).entries
                .first { $0.assetID == asset.assetID }?.summary
                .presentedAspectRatio(for: userDocument)
        )
        let bothStarted = OSAllocatedUnfairLock(initialState: 0)
        let tasks = OSAllocatedUnfairLock(initialState: (
            repair: Optional<Task<[LibraryIndexEntry], Error>>.none,
            edit: Optional<Task<PortablePackageEditCommit, Error>>.none
        ))

        // Hold the shared writer mutation gate until both package operations have started. Once
        // released, either ordering is safe: edit follows repair, or repair reads the new edit.
        lease.withWriterMutationLock {
            let repairTask = Task.detached {
                bothStarted.withLock { $0 += 1 }
                return try package.repairPresentedAspectRatioShard(
                    asset.shardName, lease: lease
                )
            }
            let editTask = Task.detached {
                bothStarted.withLock { $0 += 1 }
                return try package.commitEditRevision(
                    for: asset.assetID, document: userDocument, lease: lease
                )
            }
            tasks.withLock { $0 = (repairTask, editTask) }
            while bothStarted.withLock({ $0 < 2 }) {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }

        let startedTasks = tasks.withLock { $0 }
        let repairTask = try XCTUnwrap(startedTasks.repair)
        let editTask = try XCTUnwrap(startedTasks.edit)
        _ = try await repairTask.value
        let editCommit = try await editTask.value
        XCTAssertEqual(editCommit.membership?.summary.presentedAspectRatio, expectedRatio)
        XCTAssertEqual(
            try package.readEditRevision(for: asset.assetID).document, userDocument
        )
        XCTAssertEqual(
            try package.readMembershipShard(asset.shardName).entries
                .first { $0.assetID == asset.assetID }?.summary.presentedAspectRatio,
            expectedRatio
        )
        XCTAssertNoThrow(try PortableLibraryPackage.open(at: package.rootURL))
    }

    func testHistoryNavigationBranchesWithoutWritingAndPreservesNamedSnapshots() async throws {
        let packageURL = tempDirectory.appendingPathComponent("HistoryTimeline.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("timeline.jpg")
        try Data("timeline source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID,
            sourceFingerprint: .data(Data("timeline source".utf8), decoderVersion: "test")
        )
        let reference = EditSourceReference(assetID: .file(sourceURL), portableIdentity: identity)
        let store = EditDocumentStore(package: package, lease: lease)
        let first = EditDocument(light: .init(exposure: 0.1))
        // Equal values still occupy distinct history positions with distinct revision identities.
        let second = first
        let snapshot = EditDocument(light: .init(exposure: 0.3))
        let fourth = EditDocument(light: .init(exposure: 0.4))
        let branch = EditDocument(light: .init(exposure: 0.5))

        try await store.save(first, for: reference)
        try await store.save(second, for: reference)
        try await store.saveSnapshot(snapshot, named: "Saved look", for: reference)
        try await store.save(fourth, for: reference)
        let beforeNavigation = try await store.history(for: reference)
        XCTAssertEqual(beforeNavigation.map(\.document), [first, second, snapshot, fourth])

        try await store.selectRevision(beforeNavigation[0].revision, for: reference)
        let selectedRevision = try await store.currentRevision(for: reference)
        XCTAssertEqual(selectedRevision, beforeNavigation[0].revision)
        let unchangedHistory = try await store.history(for: reference)
        XCTAssertEqual(unchangedHistory.count, beforeNavigation.count)

        try await store.save(branch, for: reference)
        let branchedHistory = try await store.history(for: reference)
        XCTAssertEqual(branchedHistory.map(\.document), [first, snapshot, branch])
        XCTAssertEqual(branchedHistory.compactMap(\.snapshotName), ["Saved look"])

        let reopened = try PortableLibraryPackage.open(at: packageURL)
        XCTAssertEqual(
            try reopened.readAssetRecord(for: asset.assetID).editHistory.currentRevision,
            branchedHistory.last?.revision
        )
        XCTAssertEqual(try reopened.readEditRevision(for: asset.assetID).document, branch)

        try reopened.selectEditRevision(
            for: asset.assetID, revision: branchedHistory[1].revision, lease: lease
        )
        let reopenedAgain = try PortableLibraryPackage.open(at: packageURL)
        XCTAssertEqual(
            try reopenedAgain.readEditRevision(for: asset.assetID).document, snapshot,
            "a named snapshot remains independently restorable after branching"
        )
    }

    @MainActor
    func testVirtualCopyHasIndependentIdentityAndEditHistory() async throws {
        let packageURL = tempDirectory.appendingPathComponent("VirtualCopies.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("portrait.jpg")
        try Data("portable portrait".utf8).write(to: sourceURL)
        let importLease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: importLease)
        try importLease.release()
        let original = try XCTUnwrap(imported.imported.first)

        let session = try PortableLibrarySession(at: packageURL)
        let copy = try session.createVirtualCopy(of: original.assetID)
        XCTAssertNotEqual(copy.assetID, original.assetID)
        XCTAssertEqual(copy.displayName, "portrait — Copy.jpg")
        XCTAssertEqual(
            try package.readAssetRecord(for: copy.assetID).copyOfAssetID, original.assetID
        )
        let embeddedURL = try package.embeddedSourceURL(
            for: package.readAssetRecord(for: copy.assetID)
        )
        XCTAssertEqual(embeddedURL.lastPathComponent, "portrait — Copy.jpg")
        XCTAssertEqual(embeddedURL.pathExtension, "jpg")
        XCTAssertEqual(
            try Data(contentsOf: embeddedURL),
            Data("portable portrait".utf8)
        )
        let browsed = try session.browsingAssets().first {
            $0.source.portableIdentity.assetID == copy.assetID
        }
        XCTAssertEqual(browsed?.url?.lastPathComponent, "portrait — Copy.jpg")
        XCTAssertEqual(browsed?.url?.pathExtension, "jpg")

        let store = EditDocumentStore(package: package, lease: session.lease)
        let originalDocument = EditDocument(light: .init(exposure: -0.4))
        let copiedDocument = EditDocument(light: .init(exposure: 0.9))
        try await store.save(originalDocument, for: EditSourceReference(
            portableIdentity: try package.readAssetRecord(for: original.assetID).identity
        ))
        try await store.save(copiedDocument, for: EditSourceReference(portableIdentity: copy.identity))

        XCTAssertEqual(try package.readEditHistory(for: original.assetID).map(\.document), [originalDocument])
        XCTAssertEqual(try package.readEditHistory(for: copy.assetID).map(\.document), [copiedDocument])
        let membership = try package.readMembershipShard(PortableLibraryPackage.shard(for: copy.assetID))
        XCTAssertEqual(
            membership.entries.first(where: { $0.assetID == copy.assetID })?.summary.displayName,
            copy.displayName
        )
        await session.shutdown()
    }

    @MainActor
    func testLegacyVirtualCopyNameResolvesToEmbeddedFile() async throws {
        let packageURL = tempDirectory.appendingPathComponent("LegacyVirtualCopy.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("IMG_1370.DNG")
        try Data("raw stand-in".utf8).write(to: sourceURL)
        let importLease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: importLease)
        try importLease.release()
        let original = try XCTUnwrap(imported.imported.first)

        let session = try PortableLibrarySession(at: packageURL)
        let copy = try session.createVirtualCopy(of: original.assetID)
        let legacyName = "IMG_1370.DNG — Copy"
        try package.markVirtualCopy(
            copy.assetID, of: original.assetID, displayName: legacyName, lease: session.lease
        )
        _ = try session.refreshIndex()

        let browsed = try XCTUnwrap(session.browsingAssets().first {
            $0.source.portableIdentity.assetID == copy.assetID
        })
        XCTAssertEqual(browsed.displayName, legacyName)
        XCTAssertEqual(browsed.url?.lastPathComponent, "IMG_1370 — Copy.DNG")
        XCTAssertEqual(browsed.url?.pathExtension, "DNG")
        XCTAssertTrue(FileManager.default.fileExists(atPath: browsed.url?.path ?? ""))
        await session.shutdown()
    }

    func testPackagePersistenceCoordinatorStillCoalescesToOneRevision() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Coalesced.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("coalesced.jpg")
        try Data("source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let reference = EditSourceReference(
            assetID: .file(sourceURL),
            portableIdentity: PortablePhotoIdentity(
                assetID: asset.assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            ),
            url: sourceURL
        )
        let store = EditDocumentStore(package: package, lease: lease)
        let coordinator = await MainActor.run { EditPersistenceCoordinator(store: store) }
        let first = EditDocument(adjustments: [.exposure(ev: 0.1)])
        let latest = EditDocument(adjustments: [.exposure(ev: 0.9)])
        await MainActor.run {
            coordinator.enqueue(first, for: reference, reportsStatus: false)
            coordinator.enqueue(latest, for: reference, reportsStatus: false)
        }
        let flushResult = await coordinator.flush()
        XCTAssertEqual(flushResult, .success)

        let record = try package.readAssetRecord(for: asset.assetID)
        XCTAssertEqual(record.editHistory.edits.count, 1)
        XCTAssertEqual(try package.readEditRevision(for: asset.assetID).document, latest)
    }
}
