import Foundation
import XCTest
import os.lock

@testable import KromoraKit

/// Phase 2's integration gate. The lower-level package tests prove individual contracts; these
/// tests keep the import, edit, identity, recovery, and current-library boundaries connected.
final class PortablePackageEndToEndRegressionTests: TempDirectoryTestCase {

    func testSyntheticLibraryImportEditLookAndRelocationPreserveIdentityWithoutRelink()
        async throws
    {
        let generated = try await SyntheticLibraryGenerator.generate(
            scale: .oneThousand, seed: SyntheticLibraryGenerator.defaultSeed, in: tempDirectory
        )
        defer { try? generated.cleanup() }

        let sourcePackageURL = tempDirectory.appendingPathComponent("EndToEnd.kromoralibrary")
        let sourcePackage = try PortableLibraryPackage.create(at: sourcePackageURL)
        let lease = try PortablePackageLease.acquire(at: sourcePackageURL, deviceName: "phase-2.5")
        // Keep this gate fast enough for every normal test run while still deriving inputs from the
        // 1,000-asset KRMA-389 generator and retaining repeated payloads for dedupe coverage.
        let importedSources = Array(generated.assets.prefix(64))
        let result = try sourcePackage.importSources(
            importedSources.map { .init(url: $0.url, name: $0.relativePath) },
            lease: lease,
            options: .init(
                duplicatePolicy: .importAnyway, chunkSize: 97, copyMode: .streamed
            )
        )
        XCTAssertFalse(result.cancelled)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.imported.count, importedSources.count)
        XCTAssertGreaterThan(result.duplicates.count, 0)

        let lookBytes = Data("# synthetic look\nLUT_3D_SIZE 2\n".utf8)
        var editedSidecars: [PortablePhotoAssetID: PortablePackageEditSidecar] = [:]
        for imported in result.imported.prefix(3) {
            editedSidecars[imported.assetID] = try sourcePackage.appendEditRevision(
                for: imported.assetID,
                document: EditDocument(light: .init(exposure: 0.75)),
                lookBytes: [lookBytes],
                lease: lease
            )
        }
        try lease.release()

        let copiedPackageURL = tempDirectory.appendingPathComponent(
            "relocated/Nested/EndToEnd.kromoralibrary"
        )
        try FileManager.default.createDirectory(
            at: copiedPackageURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourcePackageURL, to: copiedPackageURL)
        let copiedPackage = try PortableLibraryPackage.open(at: copiedPackageURL)

        for imported in result.imported {
            let originalRecord = try sourcePackage.readAssetRecord(for: imported.assetID)
            let copiedRecord = try copiedPackage.readAssetRecord(for: imported.assetID)
            XCTAssertEqual(copiedRecord.identity, originalRecord.identity)
            XCTAssertEqual(copiedRecord.identity.cacheKey, originalRecord.identity.cacheKey)
            XCTAssertEqual(copiedRecord.editHistory, originalRecord.editHistory)

            let originalURL = try sourcePackage.embeddedSourceURL(for: originalRecord)
            let copiedURL = try copiedPackage.embeddedSourceURL(for: copiedRecord)
            XCTAssertNotEqual(originalURL.path, copiedURL.path)
            XCTAssertEqual(try Data(contentsOf: originalURL), try Data(contentsOf: copiedURL))

            if let expectedSidecar = editedSidecars[imported.assetID] {
                let actualSidecar = try copiedPackage.readEditSidecar(for: imported.assetID)
                XCTAssertEqual(actualSidecar, expectedSidecar)
                XCTAssertEqual(
                    try copiedPackage.readEmbeddedLook(
                        try XCTUnwrap(actualSidecar.native.lookReferences.first)
                    ),
                    lookBytes
                )
            }
        }

        let lookFiles = try FileManager.default.contentsOfDirectory(
            at: copiedPackageURL.appendingPathComponent("Looks"), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(lookFiles.count, 1, "the relocated package keeps one embedded Look blob")
    }

    func testDiskFullDuringImportRollsBackTheAssetAndLeavesTheSourceUntouched() throws {
        let packageURL = tempDirectory.appendingPathComponent("DiskFull.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("disk-full.raw")
        let original = Data(repeating: 0x4d, count: 8 * 1024)
        try original.write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let result = try package.importSources(
            [.init(url: sourceURL)],
            lease: lease,
            options: .init(copyMode: .streamed),
            faultInjector: PortablePackageFaultInjector(failingAt: .diskFull)
        )

        XCTAssertFalse(result.cancelled)
        XCTAssertTrue(result.imported.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        XCTAssertEqual(try liveAssetCount(in: package), 0)
        XCTAssertTrue(
            try PortablePackageTransaction.recover(at: packageURL).recoveredTransactionIDs.isEmpty
        )
        XCTAssertNoThrow(try PortableLibraryPackage.open(at: packageURL))
    }

    func testCancellationDuringEditSidecarStagingRollsBackAllRevisionFiles() throws {
        let packageURL = tempDirectory.appendingPathComponent("EditCancelled.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = try importOneAsset(into: package, packageURL: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let checks = OSAllocatedUnfairLock(initialState: 0)

        XCTAssertThrowsError(
            try package.appendEditRevision(
                for: assetID,
                document: EditDocument(light: .init(exposure: 0.5)),
                lookBytes: [Data("cancelled look".utf8)],
                lease: lease,
                isCancelled: {
                    checks.withLock { value in
                        value += 1
                        return value > 1
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError, "expected cancellation, got \(error)")
        }
        try lease.release()

        let record = try package.readAssetRecord(for: assetID)
        XCTAssertEqual(record.currentRevision, 0)
        XCTAssertTrue(record.editHistory.edits.isEmpty)
        let assetRoot = packageURL.appendingPathComponent(
            "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: assetRoot.appendingPathComponent("Edits").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: assetRoot.appendingPathComponent("Metadata").path
            )
        )
        XCTAssertTrue(
            try PortablePackageTransaction.recover(at: packageURL).recoveredTransactionIDs.isEmpty
        )
    }

    func testCorruptShardIsDiscoveredOnOpenAndCorruptRecordOnRead() throws {
        let shardPackageURL = tempDirectory.appendingPathComponent("CorruptShard.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: shardPackageURL)
        let shard = "00"
        try Data("{ not json".utf8).write(
            to: shardPackageURL.appendingPathComponent("Catalog/Membership/\(shard).json")
        )
        XCTAssertThrowsError(try PortableLibraryPackage.open(at: shardPackageURL))

        let recordPackageURL = tempDirectory.appendingPathComponent("CorruptRecord.kromoralibrary")
        let recordPackage = try PortableLibraryPackage.create(at: recordPackageURL)
        let assetID = try importOneAsset(into: recordPackage, packageURL: recordPackageURL)
        let recordURL = recordPackageURL.appendingPathComponent(
            "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/asset.json"
        )
        try Data("{\"identity\": null}".utf8).write(to: recordURL)
        let reopened = try PortableLibraryPackage.open(at: recordPackageURL)
        XCTAssertThrowsError(try reopened.readAssetRecord(for: assetID))
    }

    func testConcurrentImportAttemptIsRejectedByThePackageLeaseThenSucceedsAfterRelease() throws {
        let packageURL = tempDirectory.appendingPathComponent("LeaseContention.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("contended.jpg")
        try Data("contention source".utf8).write(to: sourceURL)
        let firstLease = try PortablePackageLease.acquire(
            at: packageURL, ownerID: UUID(), deviceName: "first-importer"
        )

        XCTAssertThrowsError(
            try PortablePackageLease.acquire(
                at: packageURL, ownerID: UUID(), deviceName: "concurrent-importer"
            )
        ) { error in
            guard case .contended(let info) = error as? PortablePackageLeaseError else {
                return XCTFail("expected explicit lease contention, got \(error)")
            }
            XCTAssertEqual(info.deviceName, "first-importer")
        }
        try firstLease.release()

        let secondLease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? secondLease.release() }
        let result = try package.importSources([.init(url: sourceURL)], lease: secondLease)
        XCTAssertEqual(result.imported.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(try liveAssetCount(in: package), 1)
    }

    @MainActor
    func testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched()
        async throws
    {
        let sourceFolder = tempDirectory.appendingPathComponent("current-library")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let currentSource = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "current.jpg", in: sourceFolder
        )
        let unrelatedDataURL = sourceFolder.appendingPathComponent("user-not-package-data.txt")
        let unrelatedData = Data("leave this user data alone".utf8)
        try unrelatedData.write(to: unrelatedDataURL)

        let defaults = makeTestUserDefaults()
        let editPackage = makeEditPackageFixture()
        let editStore = editPackage.store()
        let viewModel = makeAppViewModel(
            editStore: editStore,
            preferences: defaults,
            libraryFolderURL: tempDirectory.appendingPathComponent("managed")
        )
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()
        let currentItem = try XCTUnwrap(viewModel.collection.items.first)
        try editPackage.register(currentItem)
        try await editStore.save(
            EditDocument(adjustments: [.exposure(ev: 0.2)]),
            for: EditSourceReference(assetID: currentItem.id, url: currentSource)
        )
        let currentSourceBeforePackageWork = try Data(contentsOf: currentSource)

        let packageURL = tempDirectory.appendingPathComponent("Separate.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let packageSource = tempDirectory.appendingPathComponent("package-source.jpg")
        try Data("package only".utf8).write(to: packageSource)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let importResult = try package.importSources([.init(url: packageSource)], lease: lease)
        _ = try package.appendEditRevision(
            for: try XCTUnwrap(importResult.imported.first).assetID,
            document: EditDocument(light: .init(exposure: 0.4)),
            lease: lease
        )
        try lease.release()
        _ = try PortableLibraryPackage.open(at: packageURL)

        XCTAssertEqual(try Data(contentsOf: currentSource), currentSourceBeforePackageWork)
        XCTAssertEqual(try Data(contentsOf: unrelatedDataURL), unrelatedData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedDataURL.path))

        let deletion = await viewModel.deleteSelectedLibraryItems()
        XCTAssertEqual(deletion.deletedIDs, [currentItem.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentSource.path))
        XCTAssertEqual(try Data(contentsOf: unrelatedDataURL), unrelatedData)
        let storedAfterDelete = await editStore.load(
            for: EditSourceReference(assetID: currentItem.id, url: currentSource)
        )
        XCTAssertTrue(storedAfterDelete.found)
        XCTAssertEqual(storedAfterDelete.document.adjustments, [.exposure(ev: 0.2)])
    }

    func testOlderReaderDecodesCurrentPackageRecordAndIgnoresNewerFields() throws {
        struct OlderAssetRecord: Decodable {
            let identity: PortablePhotoIdentity
            let source: PortablePackageSourceReference
        }

        let packageURL = tempDirectory.appendingPathComponent("OlderReader.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = try importOneAsset(into: package, packageURL: packageURL)
        let recordURL = packageURL.appendingPathComponent(
            "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/asset.json"
        )
        let currentData = try Data(contentsOf: recordURL)
        let older = try JSONDecoder().decode(OlderAssetRecord.self, from: currentData)
        XCTAssertEqual(older.identity.assetID, assetID)
        XCTAssertEqual(older.source.storage, .embedded)
    }

    private func importOneAsset(
        into package: PortableLibraryPackage, packageURL: URL
    ) throws -> PortablePhotoAssetID {
        let sourceURL = tempDirectory.appendingPathComponent("source-\(UUID().uuidString).jpg")
        try Data("one package source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let result = try package.importSources([.init(url: sourceURL)], lease: lease)
        return try XCTUnwrap(result.imported.first).assetID
    }

    private func liveAssetCount(in package: PortableLibraryPackage) throws -> Int {
        try PortableLibraryPackage.allShards.reduce(into: 0) { count, shardName in
            count += try package.readMembershipShard(shardName).entries
                .filter { !$0.isTombstone }.count
        }
    }
}
