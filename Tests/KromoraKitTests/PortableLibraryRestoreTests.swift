import Foundation
import XCTest
import os.lock

@testable import KromoraKit

final class PortableLibraryRestoreTests: TempDirectoryTestCase {
    func testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation() throws {
        let sourceURL = tempDirectory.appendingPathComponent("Source.kromoralibrary")
        let source = try PortableLibraryPackage.create(at: sourceURL)
        let originalURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("restore source".utf8).write(to: originalURL)
        let lease = try PortablePackageLease.acquire(at: sourceURL)
        let imported = try source.importSources([.init(url: originalURL)], lease: lease)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        _ = try source.appendEditRevision(
            for: assetID,
            document: EditDocument(light: .init(exposure: 0.4)),
            lease: lease,
            now: Date(timeIntervalSince1970: 100)
        )
        _ = try source.appendEditRevision(
            for: assetID,
            document: EditDocument(light: .init(exposure: 0.9)),
            lease: lease,
            now: Date(timeIntervalSince1970: 200)
        )
        try lease.release()

        let backupURL = tempDirectory.appendingPathComponent("Backup.kromoralibrary")
        _ = try source.backup(to: backupURL)
        let expectedRevision1 = try source.readEditSidecar(for: assetID, revision: 1)
        let expectedRevision2 = try source.readEditSidecar(for: assetID, revision: 2)

        let activeURL = tempDirectory.appendingPathComponent("Active.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: activeURL)
        let profileURL = tempDirectory.appendingPathComponent("CleanProfile")
        let result = try PortableLibraryRestore.run(
            from: backupURL,
            replacing: activeURL,
            options: .init(copyMode: .streamed, cleanProfileURL: profileURL)
        )

        XCTAssertEqual(result.assetCount, 1)
        XCTAssertEqual(result.editRevisionCount, 2)
        XCTAssertEqual(result.indexEntryCount, 1)
        let restored = try PortableLibraryPackage.open(at: activeURL)
        XCTAssertEqual(try restored.readEditSidecar(for: assetID, revision: 1), expectedRevision1)
        XCTAssertEqual(try restored.readEditSidecar(for: assetID, revision: 2), expectedRevision2)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: profileURL.appendingPathComponent("LibraryIndex.json").path
            )
        )
    }

    func testFailedValidationLeavesActivePackageUntouchedAndReportsFailure() throws {
        let sourceURL = tempDirectory.appendingPathComponent("Source.kromoralibrary")
        let source = try PortableLibraryPackage.create(at: sourceURL)
        let originalURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("source".utf8).write(to: originalURL)
        let lease = try PortablePackageLease.acquire(at: sourceURL)
        _ = try source.importSources([.init(url: originalURL)], lease: lease)
        try lease.release()

        let backupURL = tempDirectory.appendingPathComponent("Backup.kromoralibrary")
        _ = try source.backup(to: backupURL)
        let activeURL = tempDirectory.appendingPathComponent("Active.kromoralibrary")
        let active = try PortableLibraryPackage.create(at: activeURL)
        let activeManifestBefore = try Data(contentsOf: activeURL.appendingPathComponent("manifest.json"))
        let corruptPath = backupURL.appendingPathComponent("manifest.json")
        var corrupt = try Data(contentsOf: corruptPath)
        corrupt.append(0x20)
        try corrupt.write(to: corruptPath)

        XCTAssertThrowsError(try PortableLibraryRestore.run(from: backupURL, replacing: activeURL)) { error in
            guard case .backupValidationFailed(let message) = error as? PortableLibraryRestoreError else {
                return XCTFail("expected a typed backup validation failure, got \(error)")
            }
            XCTAssertTrue(message.contains("manifest.json"), message)
        }
        XCTAssertEqual(
            try Data(contentsOf: activeURL.appendingPathComponent("manifest.json")),
            activeManifestBefore
        )
        XCTAssertEqual(try PortableLibraryPackage.open(at: activeURL).manifest.libraryID, active.manifest.libraryID)
    }

    func testCancellationDuringRestoreDoesNotReplaceActivePackage() throws {
        let sourceURL = tempDirectory.appendingPathComponent("Source.kromoralibrary")
        let source = try PortableLibraryPackage.create(at: sourceURL)
        let originalURL = tempDirectory.appendingPathComponent("large.raw")
        try Data(repeating: 0x2a, count: 128 * 1024).write(to: originalURL)
        let lease = try PortablePackageLease.acquire(at: sourceURL)
        _ = try source.importSources([.init(url: originalURL)], lease: lease)
        try lease.release()
        let backupURL = tempDirectory.appendingPathComponent("Backup.kromoralibrary")
        _ = try source.backup(to: backupURL)

        let activeURL = tempDirectory.appendingPathComponent("Active.kromoralibrary")
        let active = try PortableLibraryPackage.create(at: activeURL)
        let activeManifestBefore = try Data(contentsOf: activeURL.appendingPathComponent("manifest.json"))
        let cancelled = OSAllocatedUnfairLock(initialState: false)

        XCTAssertThrowsError(
            try PortableLibraryRestore.run(
                from: backupURL,
                replacing: activeURL,
                options: .init(chunkSize: 97, copyMode: .streamed),
                isCancelled: { cancelled.withLock { $0 } },
                progress: { update in
                    if update.phase == .staging { cancelled.withLock { $0 = true } }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError, "expected cancellation, got \(error)")
        }
        XCTAssertEqual(
            try Data(contentsOf: activeURL.appendingPathComponent("manifest.json")),
            activeManifestBefore
        )
        XCTAssertEqual(try PortableLibraryPackage.open(at: activeURL).manifest.libraryID, active.manifest.libraryID)
    }
}
