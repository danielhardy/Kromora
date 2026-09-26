import Foundation
import XCTest
@testable import KromoraKit

final class PortableLibraryPackageTests: TempDirectoryTestCase {

    func testCreateWritesManifestAndAll256MembershipShards() throws {
        let packageURL = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: packageURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))
        let shardDirectory = packageURL.appendingPathComponent("Catalog/Membership")
        let files = try FileManager.default.contentsOfDirectory(atPath: shardDirectory.path)
        XCTAssertEqual(files.count, 256)
        XCTAssertEqual(Set(files), Set(PortableLibraryPackage.allShards.map { "\($0).json" }))
    }

    func testUnknownTopLevelJSONMembersSurviveManifestShardAndRecordRewrite() throws {
        let packageURL = tempDirectory.appendingPathComponent("Unknown.kromoralibrary")
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "ab000000-0000-4000-8000-000000000001")!)
        let identity = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: .data(Data("source".utf8), sourceRevision: 3, decoderVersion: "decoder-1",
                                     geometry: PhotoPixelDimensions(width: 10, height: 5))
        )
        _ = try PortableLibraryPackage.create(at: packageURL)

        let manifestJSON = """
        {"formatVersion":1,"libraryID":"00000000-0000-4000-8000-000000000001","createdAt":"2026-09-13T00:00:00Z","createdBy":"test","writerVersion":"1.0","minimumReaderVersion":"1.0","membershipShardCount":256,"membershipShardPrefixLength":2,"featureFlags":{},"recoveryFormatVersion":1,"futureManifest": { "keep": [1, 2, 3] }}
        """
        try Data(manifestJSON.utf8).write(to: packageURL.appendingPathComponent("manifest.json"))

        var package = try PortableLibraryPackage.open(at: packageURL)
        let savedManifest = package.manifest
        try package.rewriteManifest(savedManifest)
        let rewrittenManifest = try String(contentsOf: packageURL.appendingPathComponent("manifest.json"))
        XCTAssertTrue(rewrittenManifest.contains("\"futureManifest\": { \"keep\": [1, 2, 3] }"))

        let summary = PortablePackageAssetSummary(
            dimensions: PhotoPixelDimensions(width: 10, height: 5), aspectRatio: 2,
            displayName: "Photo", assetRevision: 4
        )
        let entry = PortablePackageMembershipEntry(
            assetID: assetID, recordPath: "Assets/ab/\(assetID.raw)/asset.json", addedRevision: 4,
            summary: summary
        )
        let shardJSON = """
        {"shard":"ab","entries":[{"assetID":{"uuid":"ab000000-0000-4000-8000-000000000001"},"recordPath":"Assets/ab/\(assetID.raw)/asset.json","addedRevision":4,"deletedRevision":null,"isTombstone":false,"summary":{"captureDate":null,"rating":null,"flag":null,"label":null,"cameraMake":null,"cameraModel":null,"lens":null,"dimensions":{"width":10,"height":5},"aspectRatio":2,"displayName":"Photo","assetRevision":4}}],"futureShard": { "state": "preserve-me" }}
        """
        try Data(shardJSON.utf8).write(to: packageURL.appendingPathComponent("Catalog/Membership/ab.json"))
        let shard = try package.readMembershipShard("ab")
        XCTAssertEqual(shard.entries, [entry])
        try package.writeMembershipShard(shard)
        let rewrittenShard = try String(contentsOf: packageURL.appendingPathComponent("Catalog/Membership/ab.json"))
        XCTAssertTrue(rewrittenShard.contains("\"futureShard\": { \"state\": \"preserve-me\" }"))

        let record = PortablePackageAssetRecord(
            identity: identity,
            source: .embedded(relativePath: "Assets/ab/\(assetID.raw)/Original/source.jpg"),
            currentRevision: 4,
            editHistory: .init(currentRevision: 4, edits: [.init(revision: 4, relativePath: "Assets/ab/\(assetID.raw)/Edits/4.json")])
        )
        try package.writeAssetRecord(record)
        let recordURL = packageURL.appendingPathComponent("Assets/ab/\(assetID.raw)/asset.json")
        let recordData = try Data(contentsOf: recordURL)
        let recordObject = try XCTUnwrap(JSONSerialization.jsonObject(with: recordData) as? [String: Any])
        var recordWithFuture = recordObject
        recordWithFuture["futureRecord"] = ["unknown": true, "raw": "kept"]
        try JSONSerialization.data(withJSONObject: recordWithFuture, options: [.prettyPrinted, .sortedKeys]).write(to: recordURL)
        let readRecord = try package.readAssetRecord(for: assetID)
        try package.writeAssetRecord(readRecord)
        let rewrittenRecord = try String(contentsOf: recordURL)
        XCTAssertTrue(rewrittenRecord.contains("\"futureRecord\""))
        XCTAssertTrue(rewrittenRecord.contains("\"unknown\" : true"))
    }

    func testCopiedPackageOpensWithIdenticalPortableIdentityAndNoRelink() throws {
        let sourceURL = tempDirectory.appendingPathComponent("Source.kromoralibrary")
        let copiedURL = tempDirectory.appendingPathComponent("Nested/Copied.kromoralibrary")
        let sourcePackage = try PortableLibraryPackage.create(at: sourceURL)
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "cd000000-0000-4000-8000-000000000001")!)
        let fingerprint = PortablePhotoSourceFingerprint.data(
            Data("portable original".utf8), sourceRevision: 9, decoderVersion: "decoder-3",
            geometry: PhotoPixelDimensions(width: 4000, height: 3000)
        )
        let record = PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(assetID: assetID, sourceFingerprint: fingerprint),
            source: .embedded(relativePath: "Assets/cd/\(assetID.raw)/Original/source.jpg"),
            currentRevision: 9,
            editHistory: .init(currentRevision: 9, edits: [
                .init(revision: 9, relativePath: "Assets/cd/\(assetID.raw)/Edits/9.json")
            ])
        )
        try sourcePackage.writeAssetRecord(record)
        let entry = PortablePackageMembershipEntry(
            assetID: assetID, recordPath: "Assets/cd/\(assetID.raw)/asset.json",
            summary: .init(dimensions: fingerprint.geometry, displayName: "source.jpg")
        )
        var shard = try sourcePackage.readMembershipShard("cd")
        shard.entries = [entry]
        try sourcePackage.writeMembershipShard(shard)

        try FileManager.default.createDirectory(at: copiedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: copiedURL)
        let copiedPackage = try PortableLibraryPackage.open(at: copiedURL)
        let originalRecord = try sourcePackage.readAssetRecord(for: assetID)
        let copiedRecord = try copiedPackage.readAssetRecord(for: assetID)

        XCTAssertEqual(originalRecord.identity, copiedRecord.identity)
        XCTAssertEqual(originalRecord.identity.cacheKey, copiedRecord.identity.cacheKey)
        XCTAssertEqual(originalRecord.editHistory, copiedRecord.editHistory)
        XCTAssertEqual(originalRecord.source.relativePath, copiedRecord.source.relativePath)
        XCTAssertNotEqual(
            try sourcePackage.embeddedSourceURL(for: originalRecord).path,
            try copiedPackage.embeddedSourceURL(for: copiedRecord).path
        )
    }

    func testEditRevisionsRoundTripAsNativeAndXMPAndRemainImmutable() throws {
        let packageURL = tempDirectory.appendingPathComponent("Edits.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "aa000000-0000-4000-8000-000000000001")!)
        let record = PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            ),
            source: .embedded(relativePath: "Assets/aa/\(assetID.raw)/Original/source.jpg")
        )
        try package.writeAssetRecord(record)

        let lease = try PortablePackageLease.acquire(at: packageURL, deviceName: "test", processID: 1)
        let firstDocument = EditDocument(light: .init(exposure: 0.5))
        let first = try package.appendEditRevision(
            for: assetID, document: firstDocument,
            lookBytes: [Data("same look".utf8), Data("same look".utf8)], lease: lease
        )
        let secondDocument = EditDocument(light: .init(exposure: 1.0))
        let second = try package.appendEditRevision(
            for: assetID, document: secondDocument,
            lookBytes: [Data("same look".utf8)], lease: lease
        )
        let otherAssetID = PortablePhotoAssetID(uuid: UUID(uuidString: "aa000000-0000-4000-8000-000000000002")!)
        try package.writeAssetRecord(PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(
                assetID: otherAssetID,
                sourceFingerprint: .data(Data("other source".utf8), decoderVersion: "test")
            ),
            source: .embedded(relativePath: "Assets/aa/\(otherAssetID.raw)/Original/other.jpg")
        ))
        let otherAssetRevision = try package.appendEditRevision(
            for: otherAssetID, document: firstDocument,
            lookBytes: [Data("same look".utf8)], lease: lease
        )
        try lease.release()

        XCTAssertEqual(first.native.revision, 1)
        XCTAssertEqual(second.native.revision, 2)
        XCTAssertEqual(try package.readEditSidecar(for: assetID, revision: 1), first)
        XCTAssertEqual(try package.readEditSidecar(for: assetID), second)
        XCTAssertEqual(first.native.lookReferences.count, 1)
        XCTAssertEqual(second.native.lookReferences, first.native.lookReferences)
        XCTAssertEqual(otherAssetRevision.native.lookReferences, first.native.lookReferences)
        let lookFiles = try FileManager.default.contentsOfDirectory(
            at: packageURL.appendingPathComponent("Looks"), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(lookFiles.count, 1, "the same Look bytes must have one package blob")

        let firstNative = try package.readEditRevision(for: assetID, revision: 1)
        XCTAssertEqual(firstNative.document, firstDocument)
        XCTAssertEqual(firstNative.revision, 1)
        XCTAssertTrue(first.xmp.rawData.contains(Data("kromora:editDocument".utf8)))
    }

    func testPortablePackageErrorUsesLocalizedDescription() {
        XCTAssertEqual(
            PortablePackageError.malformedXMP("writer produced a mismatched packet").localizedDescription,
            "Malformed XMP edit sidecar: writer produced a mismatched packet"
        )
        XCTAssertEqual(
            PortablePackageError.immutableRevisionExists("Assets/aa/edits/2.json").localizedDescription,
            "Immutable edit revision already exists at 'Assets/aa/edits/2.json'"
        )
        XCTAssertEqual(
            PortablePackageError.invalidRelativePath("Original/Photo").localizedDescription,
            "Unsafe package-relative path 'Original/Photo'"
        )
    }

    func testAppendEditRevisionSkipsSidecarsMissingFromTheAssetRecord() throws {
        let packageURL = tempDirectory.appendingPathComponent("OccupiedRevision.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "aa000000-0000-4000-8000-00000000000a")!)
        try package.writeAssetRecord(PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            ),
            source: .embedded(relativePath: "Assets/aa/\(assetID.raw)/Original/source.jpg")
        ))
        let lease = try PortablePackageLease.acquire(at: packageURL, deviceName: "test", processID: 1)
        _ = try package.appendEditRevision(
            for: assetID, document: EditDocument(light: .init(exposure: 0.25)), lease: lease
        )
        let revisionDirectory = packageURL.appendingPathComponent("Assets/aa/\(assetID.raw)")
        try Data(contentsOf: revisionDirectory.appendingPathComponent("Edits/1.json"))
            .write(to: revisionDirectory.appendingPathComponent("Edits/2.json"))
        try Data(contentsOf: revisionDirectory.appendingPathComponent("Metadata/1.xmp"))
            .write(to: revisionDirectory.appendingPathComponent("Metadata/2.xmp"))

        let next = try package.appendEditRevision(
            for: assetID, document: EditDocument(light: .init(exposure: 0.75)), lease: lease
        )
        try lease.release()

        XCTAssertEqual(next.native.revision, 3)
        let record = try package.readAssetRecord(for: assetID)
        XCTAssertEqual(record.currentRevision, 3)
        XCTAssertEqual(record.editHistory.currentRevision, 3)
        XCTAssertEqual(try package.readEditRevision(for: assetID).document.light.exposure, 0.75)
    }

    func testMalformedXMPIsReportedAndCanBeQuarantined() throws {
        let packageURL = tempDirectory.appendingPathComponent("MalformedXMP.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID()
        try package.writeAssetRecord(PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            ),
            source: .embedded(relativePath: "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/Original/source.jpg")
        ))
        let lease = try PortablePackageLease.acquire(at: packageURL, deviceName: "test", processID: 2)
        _ = try package.appendEditRevision(for: assetID, document: EditDocument(), lease: lease)
        try lease.release()

        let record = try package.readAssetRecord(for: assetID)
        let pointer = try XCTUnwrap(record.editHistory.edits.first)
        let xmpURL = packageURL.appendingPathComponent(try XCTUnwrap(pointer.xmpRelativePath))
        try Data("<x:xmpmeta><rdf:RDF>truncated".utf8).write(to: xmpURL)

        XCTAssertThrowsError(try package.readEditSidecar(for: assetID)) { error in
            guard case PortablePackageError.malformedXMP = error else {
                return XCTFail("expected typed malformed-XMP error, got \(error)")
            }
        }
        let quarantineURL = try package.quarantineMalformedXMP(for: assetID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: xmpURL.path))
    }

    func testXMPWithDOCTYPEEntityBombIsRejectedAsMalformedRatherThanExpanded() throws {
        let bomb = """
        <?xml version="1.0"?>
        <!DOCTYPE lolz [
         <!ENTITY lol "lol">
         <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
        ]>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:kromora="https://kromora.app/ns/1.0/" kromora:assetID="&lol2;" kromora:revision="1" kromora:editDocument="x"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        XCTAssertThrowsError(try PortablePackageXMPCodec.decode(Data(bomb.utf8))) { error in
            guard case PortablePackageError.malformedXMP = error else {
                return XCTFail("expected typed malformed-XMP error, got \(error)")
            }
        }
    }

    func testReservedReferencedAssetFieldsRoundTripWithoutResolverBehavior() throws {
        let packageURL = tempDirectory.appendingPathComponent("Referenced.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID()
        let record = PortablePackageAssetRecord(
            identity: PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            ),
            source: .referenced(bookmark: Data("future-bookmark".utf8))
        )
        try package.writeAssetRecord(record)
        let reopened = try PortableLibraryPackage.open(at: packageURL)
        XCTAssertEqual(try reopened.readAssetRecord(for: assetID), record)
        XCTAssertThrowsError(try reopened.embeddedSourceURL(for: record))
    }
}
