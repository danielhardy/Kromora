import CoreGraphics
import ImageIO
import XCTest
@testable import KromoraKit

/// KRMA-1156: a package edit reproduces its Look from the package alone. The embedded, content-
/// addressed bytes are what a revision renders with; the external Look file is only an import
/// source, so moving, deleting or replacing it must not change or invalidate a saved edit.
@MainActor
final class EmbeddedLookResolutionTests: TempDirectoryTestCase {
    private struct Harness {
        let fixture: EditPackageFixture
        let reference: EditSourceReference
        let sourceURL: URL
        let looksDirectory: URL
        let lookID: LUTID
        let lookBytes: Data
        let look: CubeLUT
    }

    /// A non-identity table so a wrong or missing Look changes pixels.
    private func cubeText(red: Float, blue: Float) -> String {
        var lines = ["TITLE \"graded\"", "LUT_3D_SIZE 4"]
        for b in 0..<4 {
            for g in 0..<4 {
                for r in 0..<4 {
                    lines.append(String(
                        format: "%.6f %.6f %.6f",
                        min(1, Float(r) / 3 * red), Float(g) / 3, min(1, Float(b) / 3 * blue)))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func makeHarness(name: String = "Warm.cube") throws -> Harness {
        let directory = tempDirectory.appendingPathComponent("looks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lookURL = try Fixtures.writeCube(cubeText(red: 1.3, blue: 0.7), named: name, in: directory)
        let look = try CubeLUT(url: lookURL)
        let sourceURL = try Fixtures.writeGradientPNG(
            width: 24, height: 16, named: "photo-\(UUID().uuidString).png", in: tempDirectory)
        let fixture = makeEditPackageFixture()
        try fixture.register(sourceURL)
        return Harness(
            fixture: fixture, reference: EditSourceReference(assetID: .file(sourceURL), url: sourceURL),
            sourceURL: sourceURL, looksDirectory: directory, lookID: look.lutID,
            lookBytes: try Data(contentsOf: lookURL), look: look)
    }

    private func lookedDocument(_ harness: Harness, exposure: Double? = nil) -> EditDocument {
        var document = EditDocument(
            adjustments: exposure.map { [.exposure(ev: $0)] } ?? [],
            lut: LUTSettings(lutID: harness.lookID, intensity: 1))
        document.lut.intensity = 1
        return document
    }

    /// A store as a fresh launch of a profile without the external Look folder would have: it never
    /// saw the Look browser's bytes.
    private func freshStore(_ harness: Harness) -> EditDocumentStore { harness.fixture.store() }

    private func currentReferences(_ harness: Harness) throws -> [PortablePackageLookReference] {
        try harness.fixture.package.readEditRevision(for: harness.reference.portableAssetID).lookReferences
    }

    private func coordinator(
        _ looks: [CubeLUT] = [], store: EditDocumentStore? = nil
    ) -> LookSelectionCoordinator {
        let library = makeLUTLibrary()
        library.allLUTs = looks
        return LookSelectionCoordinator(library: library, store: store)
    }

    // MARK: Reopen

    func testFreshStoreResolvesTheLookFromThePackageWithoutTheExternalFile() async throws {
        let h = try makeHarness()
        let writer = h.fixture.store()
        await writer.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await writer.save(lookedDocument(h), for: h.reference)
        try FileManager.default.removeItem(at: h.looksDirectory)

        let reopened = freshStore(h)
        let loaded = await reopened.load(for: h.reference)
        XCTAssertTrue(loaded.found)
        XCTAssertEqual(loaded.document.lut.lutID, h.lookID)
        let stored = try XCTUnwrap(reopened.storedLooks.storedLook(for: h.reference.portableAssetID))
        guard case .embedded(let embedded) = stored else { return XCTFail("expected embedded Look") }
        XCTAssertEqual(embedded.contentHash, h.look.contentHash)
        XCTAssertEqual(embedded.lutID, h.lookID)

        let resolver = coordinator(store: reopened)
        XCTAssertNil(resolver.resolve(h.lookID), "the library alone cannot resolve it: the file is gone")
        let resolved = try XCTUnwrap(resolver.resolve(h.lookID, for: h.reference))
        XCTAssertEqual(resolved.cacheFingerprint, h.look.cacheFingerprint)
        XCTAssertEqual(resolver.refreshStatus(for: h.lookID, reference: h.reference), .cleared)

        let input = try TestImages.gradient(width: 16, height: 8)
        let original = try Pixels.bytes(of: XCTUnwrap(h.look.apply(to: input, intensity: 1)))
        let reproduced = try Pixels.bytes(of: XCTUnwrap(resolved.apply(to: input, intensity: 1)))
        XCTAssertEqual(reproduced, original)
        let ungraded = try Pixels.bytes(of: input)
        XCTAssertNotEqual(ungraded, original, "the fixture Look must visibly grade the image")
    }

    func testOrdinaryEditAfterReopenKeepsTheEmbeddedReferenceWithoutTheExternalFile() async throws {
        let h = try makeHarness()
        let writer = h.fixture.store()
        await writer.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await writer.save(lookedDocument(h), for: h.reference)
        let original = try currentReferences(h)
        XCTAssertEqual(original.count, 1)
        try FileManager.default.removeItem(at: h.looksDirectory)

        let reopened = freshStore(h)
        _ = await reopened.load(for: h.reference)
        try await reopened.save(lookedDocument(h, exposure: 0.4), for: h.reference)

        XCTAssertEqual(try currentReferences(h), original, "the existing verified reference is carried forward")
        let revision = try h.fixture.package.readEditRevision(for: h.reference.portableAssetID)
        XCTAssertEqual(revision.revision, 2)
        XCTAssertEqual(try h.fixture.package.readEmbeddedLook(original[0]), h.lookBytes)
        XCTAssertEqual(revision.document.lut.lutID, h.lookID)
    }

    // MARK: Replacement and re-selection

    func testReplacedExternalFileDoesNotChangeASavedRevisionUntilTheUserReselects() async throws {
        let h = try makeHarness()
        let store = h.fixture.store()
        await store.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await store.save(lookedDocument(h), for: h.reference)
        let original = try currentReferences(h)

        // The file at the same path is replaced with a different grade and the browser rescans.
        let replacedURL = try Fixtures.writeCube(
            cubeText(red: 0.6, blue: 1.4), named: h.look.url.lastPathComponent, in: h.looksDirectory)
        let replaced = try CubeLUT(url: replacedURL)
        XCTAssertEqual(replaced.lutID, h.lookID)
        XCTAssertNotEqual(replaced.contentHash, h.look.contentHash)
        await store.setEmbeddedLookBytes([h.lookID.raw: try Data(contentsOf: replacedURL)])

        try await store.save(lookedDocument(h, exposure: 0.2), for: h.reference)
        XCTAssertEqual(try currentReferences(h), original, "an ordinary save must not adopt the replacement")
        let reopened = freshStore(h)
        _ = await reopened.load(for: h.reference)
        let stillOriginal = try XCTUnwrap(reopened.storedLooks.storedLook(for: h.reference.portableAssetID))
        XCTAssertEqual(stillOriginal.contentHash, h.look.contentHash)

        // Choosing the Look again in the browser is the deliberate act that adopts the new bytes.
        let selection = coordinator([replaced], store: store)
        XCTAssertTrue(selection.replacesStoredBytes(with: replaced, for: h.reference))
        XCTAssertFalse(selection.replacesStoredBytes(with: h.look, for: h.reference),
                       "re-selecting the bytes the revision already embeds is not a change")
        await selection.adopt(replaced, for: h.reference)
        try await store.save(lookedDocument(h, exposure: 0.2), for: h.reference)
        XCTAssertEqual(
            try currentReferences(h), [PortablePackageLookReference(data: try Data(contentsOf: replacedURL))])
        XCTAssertEqual(store.storedLooks.storedLook(for: h.reference.portableAssetID)?.contentHash,
                       replaced.contentHash)

        // The adoption is one-shot: the next ordinary save keeps the adopted bytes.
        await store.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await store.save(lookedDocument(h, exposure: 0.3), for: h.reference)
        XCTAssertEqual(
            try currentReferences(h), [PortablePackageLookReference(data: try Data(contentsOf: replacedURL))])
    }

    func testChoosingADifferentLookEmbedsTheNewLookNotTheOldReference() async throws {
        let h = try makeHarness()
        let store = h.fixture.store()
        await store.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await store.save(lookedDocument(h), for: h.reference)

        let otherURL = try Fixtures.writeCube(
            cubeText(red: 0.5, blue: 1.0), named: "Other.cube", in: h.looksDirectory)
        let other = try CubeLUT(url: otherURL)
        await store.setEmbeddedLookBytes([
            h.lookID.raw: h.lookBytes, other.lutID.raw: try Data(contentsOf: otherURL),
        ])
        var document = lookedDocument(h)
        document.lut.lutID = other.lutID
        try await store.save(document, for: h.reference)

        XCTAssertEqual(try currentReferences(h).map(\.contentHash), [other.contentHash])
    }

    // MARK: Snapshots and history

    func testSnapshotAndRestoreReproduceTheirOwnLook() async throws {
        let h = try makeHarness()
        let store = h.fixture.store()
        await store.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await store.save(lookedDocument(h), for: h.reference)
        let original = try currentReferences(h)
        try FileManager.default.removeItem(at: h.looksDirectory)

        let reopened = freshStore(h)
        _ = await reopened.load(for: h.reference)
        try await reopened.saveSnapshot(lookedDocument(h, exposure: 0.1), named: "Keep", for: h.reference)
        try await reopened.save(EditDocument(adjustments: [.exposure(ev: 0.5)]), for: h.reference)
        XCTAssertNil(reopened.storedLooks.storedLook(for: h.reference.portableAssetID),
                     "a revision with no Look pins nothing")

        let history = try await reopened.history(for: h.reference)
        let snapshot = try XCTUnwrap(history.first { $0.snapshotName == "Keep" })
        XCTAssertEqual(snapshot.lookReferences, original, "the snapshot embeds the carried-forward Look")

        try await reopened.selectRevision(snapshot.revision, for: h.reference)
        let restored = try XCTUnwrap(reopened.storedLooks.storedLook(for: h.reference.portableAssetID))
        XCTAssertEqual(restored.contentHash, h.look.contentHash)
        let resolved = try XCTUnwrap(coordinator().resolve(h.lookID, stored: restored))
        XCTAssertEqual(resolved.cacheFingerprint, h.look.cacheFingerprint)

        try await reopened.selectRevision(1, for: h.reference)
        XCTAssertEqual(reopened.storedLooks.storedLook(for: h.reference.portableAssetID)?.contentHash,
                       h.look.contentHash)
    }

    // MARK: Retired and unresolvable Looks

    func testRetiredStarterIDKeepsReproducingItsSavedBytes() async throws {
        let h = try makeHarness()
        let retired = LUTID(raw: "kromora.starter.silver-noir")
        let replacementURL = try Fixtures.writeCube(
            cubeText(red: 0.4, blue: 1.0), named: "fine-mono.cube", in: h.looksDirectory)
        let replacement = try CubeLUT(
            url: replacementURL, source: .bundled, stableID: "kromora.starter.fine-mono")
        var document = lookedDocument(h)
        document.lut.lutID = retired
        let store = h.fixture.store()
        await store.setEmbeddedLookBytes([retired.raw: h.lookBytes])
        try await store.save(document, for: h.reference)

        let reopened = freshStore(h)
        _ = await reopened.load(for: h.reference)
        let stored = try XCTUnwrap(reopened.storedLooks.storedLook(for: h.reference.portableAssetID))
        let resolver = coordinator([replacement])

        XCTAssertEqual(resolver.resolve(retired)?.contentHash, replacement.contentHash,
                       "browsing still maps a retired ID to its successor")
        let reproduced = try XCTUnwrap(resolver.resolve(retired, stored: stored))
        XCTAssertEqual(reproduced.contentHash, h.look.contentHash, "a saved revision is not re-pointed")
        XCTAssertEqual(reproduced.lutID, retired)
    }

    func testUnloadableEmbeddedLookStaysUnresolvedAndNeverSubstitutesAnotherLook() async throws {
        let h = try makeHarness()
        let store = h.fixture.store()
        await store.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        try await store.save(lookedDocument(h), for: h.reference)
        let reference = try XCTUnwrap(currentReferences(h).first)
        let blob = try h.fixture.package.packageURL(for: reference.relativePath)
        try Data("corrupt".utf8).write(to: blob)
        try FileManager.default.removeItem(at: h.looksDirectory)

        let reopened = freshStore(h)
        let loaded = await reopened.load(for: h.reference)
        XCTAssertEqual(loaded.document.lut.lutID, h.lookID, "the stored reference is kept")
        let stored = try XCTUnwrap(reopened.storedLooks.storedLook(for: h.reference.portableAssetID))
        XCTAssertEqual(stored, .unavailable(id: h.lookID, contentHash: reference.contentHash))

        // Neither an absent file nor a different file at the same path may stand in for it.
        let different = try CubeLUT(
            url: Fixtures.writeCube(
                cubeText(red: 0.5, blue: 0.5), named: h.look.url.lastPathComponent,
                in: tempDirectory))
        XCTAssertEqual(different.lutID.raw.hasSuffix(h.look.url.lastPathComponent), true)
        let resolver = coordinator([different])
        XCTAssertNil(resolver.resolve(different.lutID, stored: .unavailable(
            id: different.lutID, contentHash: reference.contentHash)))
        XCTAssertNil(coordinator().resolve(h.lookID, stored: stored))

        // A library file with exactly the saved bytes is an exact stand-in.
        let sameURL = try Fixtures.writeCube(
            cubeText(red: 1.3, blue: 0.7), named: "Same.cube", in: tempDirectory)
        let same = try CubeLUT(url: sameURL)
        XCTAssertEqual(
            coordinator([same]).resolve(
                same.lutID, stored: .unavailable(id: same.lutID, contentHash: same.contentHash))?.contentHash,
            same.contentHash)
    }

    // MARK: Export

    func testExportFromAPackageWithoutTheExternalLookMatchesTheOriginalRender() async throws {
        let h = try makeHarness()
        let writer = h.fixture.store()
        await writer.setEmbeddedLookBytes([h.lookID.raw: h.lookBytes])
        let document = lookedDocument(h)
        try await writer.save(document, for: h.reference)
        let expectedFolder = tempDirectory.appendingPathComponent("expected", isDirectory: true)
        let actualFolder = tempDirectory.appendingPathComponent("actual", isDirectory: true)
        let missingFolder = tempDirectory.appendingPathComponent("missing", isDirectory: true)
        for folder in [expectedFolder, actualFolder, missingFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        // The session that authored the edit, with the Look in hand.
        let original = ExportCoordinator(exportEngine: RenderEngine(), photosDelivery: nil)
        let expected = await original.performBatchExport(
            [ExportCoordinator.BatchItem(
                url: h.sourceURL, data: nil, name: "photo", document: document, lut: h.look)],
            document: EditDocument(), lut: nil, format: .png, to: expectedFolder)
        XCTAssertEqual(expected.exported, 1)

        // The package opened in a profile with no Look folder: resolve through the stored Look only.
        try FileManager.default.removeItem(at: h.looksDirectory)
        let reopened = freshStore(h)
        let resolver = coordinator()
        let coordinatorUnderTest = ExportCoordinator(
            exportEngine: RenderEngine(), editStore: reopened,
            lutResolver: { id, reference in
                resolver.resolve(
                    id, stored: reference.flatMap { reopened.storedLooks.storedLook(for: $0.portableAssetID) })
            }, photosDelivery: nil)
        let item = ExportCoordinator.BatchItem(url: h.sourceURL, data: nil, name: "photo")
        let actual = await coordinatorUnderTest.performBatchExport(
            [item], document: EditDocument(), lut: nil, format: .png, to: actualFolder)
        XCTAssertEqual(actual.exported, 1)
        XCTAssertEqual(actual.failed, 0)

        let expectedPixels = try pixels(inOnlyFileOf: expectedFolder)
        let actualPixels = try pixels(inOnlyFileOf: actualFolder)
        XCTAssertEqual(actualPixels, expectedPixels, "the exported pixels must carry the saved grade")

        let neutralFolder = tempDirectory.appendingPathComponent("neutral", isDirectory: true)
        try FileManager.default.createDirectory(at: neutralFolder, withIntermediateDirectories: true)
        _ = await original.performBatchExport(
            [ExportCoordinator.BatchItem(
                url: h.sourceURL, data: nil, name: "photo", document: EditDocument())],
            document: EditDocument(), lut: nil, format: .png, to: neutralFolder)
        XCTAssertNotEqual(
            try pixels(inOnlyFileOf: neutralFolder), expectedPixels,
            "the fixture Look must change exported pixels, or the comparison proves nothing")

        // A resolver with no stored Look is the pre-fix behaviour: the item fails visibly.
        let bare = ExportCoordinator(
            exportEngine: RenderEngine(), editStore: reopened,
            lutResolver: { id, _ in resolver.resolve(id) }, photosDelivery: nil)
        let failed = await bare.performBatchExport(
            [item], document: EditDocument(), lut: nil, format: .png, to: missingFolder)
        XCTAssertEqual(failed.exported, 0)
        XCTAssertEqual(failed.failed, 1)
    }

    /// The export names its file after the source and Look, so find it rather than predict it.
    private func pixels(inOnlyFileOf folder: URL) throws -> [UInt8] {
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(files.count, 1, "exported files: \(files)")
        return try pixels(at: folder.appendingPathComponent(try XCTUnwrap(files.first)))
    }

    private func pixels(at url: URL) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try Pixels.bytes(of: XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
    }
}
