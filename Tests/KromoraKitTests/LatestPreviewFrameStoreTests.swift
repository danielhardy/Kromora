import XCTest
import CoreGraphics
import CoreImage
import ImageIO
@testable import KromoraKit

private actor PlaceholderSweepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        let parked = waiters
        waiters.removeAll()
        for waiter in parked { waiter.resume() }
    }
}

/// `XCTUnwrap` takes an autoclosure, which cannot await. Unwrap an already-awaited value.
func unwrapAwaited<T>(
    _ value: T?, file: StaticString = #filePath, line: UInt = #line
) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}

@MainActor
final class LatestPreviewFrameStoreTests: TempDirectoryTestCase {
    private func cacheDirectory(_ name: String = "frames") -> URL {
        tempDirectory.appendingPathComponent(name)
    }

    private func frameFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kframe" }
    }

    private func fileURL(for identity: PortablePhotoIdentity, in directory: URL) throws -> URL {
        let hash = try XCTUnwrap(LatestPreviewFrameStore.assetHash(identity.assetID))
        return directory.appendingPathComponent("\(hash).kframe")
    }

    func testRoundTripUsesARealCanonicalRasterAcrossInstances() async throws {
        let directory = cacheDirectory()
        let source = CIImage(cgImage: try Fixtures.makeCGImage(width: 320, height: 240))
        let canonical = try XCTUnwrap(
            RenderEngineResources.canonicalPreviewFrame(from: source, space: .sRGB, longEdge: 2048)
        )
        XCTAssertEqual(canonical.pixelWidth, 2048)
        XCTAssertEqual(canonical.pixelHeight, 1536)
        let identity = FrameFixtures.identity()
        let frame = PresentationFrame(
            metadata: FrameFixtures.metadata(
                identity: identity, width: canonical.pixelWidth, height: canonical.pixelHeight,
                digest: canonical.perceptualDigest
            ),
            rasterData: canonical.jpegData
        )
        let store = LatestPreviewFrameStore(directory: directory)
        await store.enqueueWrite(frame)
        await store.waitForPendingWrites()

        let relaunched = LatestPreviewFrameStore(directory: directory)
        let hit = try unwrapAwaited(await relaunched.read(for: identity))
        XCTAssertEqual(hit.image.width, 2048)
        XCTAssertEqual(hit.image.height, 1536)
        XCTAssertEqual(hit.frame.metadata, frame.metadata)
        XCTAssertEqual(hit.frame.perceptualDigest, canonical.perceptualDigest)
        let expected = try Pixels.bytes(of: try XCTUnwrap(
            RenderEngineResources.canonicalPreviewRaster(from: source, space: .sRGB, longEdge: 2048)
        ))
        let actual = try Pixels.bytes(of: hit.image)
        let total = zip(expected, actual).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) / 255.0 }
        XCTAssertLessThan(total / Double(expected.count), 3.0 / 255.0)
    }

    func testEachAssetHasExactlyOneReplaceableFile() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let identity = FrameFixtures.identity()
        let other = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: identity, edit: "first"))
        await store.enqueueWrite(try FrameFixtures.frame(identity: other, edit: "other"))
        await store.waitForPendingWrites()
        await store.enqueueWrite(try FrameFixtures.frame(identity: identity, edit: "second"))
        await store.waitForPendingWrites()

        XCTAssertEqual(try frameFiles(in: directory).count, 2)
        let hit = try unwrapAwaited(await store.read(for: identity))
        XCTAssertEqual(hit.frame.signature.editHash, "second")
        let awaited1 = await store.read(for: other)?.frame.signature.editHash
        XCTAssertEqual(awaited1, "other")
    }

    func testPlaceholderFramesAreSkippedAndRemovedByBoundedSweep() async throws {
        let directory = cacheDirectory("placeholder-sweep")
        let store = LatestPreviewFrameStore(directory: directory)
        let assetID = PortablePhotoAssetID()
        let placeholder = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "browsing:\(assetID.raw)", decoderVersion: "browsing-v1"
            )
        )
        await store.enqueueWrite(try FrameFixtures.frame(identity: placeholder))
        await store.waitForPendingWrites()
        let skippedWrites = await store.placeholderWritesSkipped
        XCTAssertEqual(skippedWrites, 1)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(try frameFiles(in: directory).isEmpty)

        let identities = (0..<10).map { _ in FrameFixtures.identity() }
        for identity in identities {
            let frame = try FrameFixtures.frame(identity: identity)
            let data = try PresentationFrameEnvelope.encode(frame)
            let url = try fileURL(for: identity, in: directory)
            try data.write(to: url)
        }
        let legacyFrame = try FrameFixtures.frame(identity: placeholder)
        let legacyData = try PresentationFrameEnvelope.encode(legacyFrame)
        let legacyURL = try fileURL(for: placeholder, in: directory)
        try legacyData.write(to: legacyURL)

        for _ in 0..<3 { await store.sweepPlaceholderFrames(maxFiles: 8) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try frameFiles(in: directory).count, identities.count)
        for identity in identities {
            let expected = try PresentationFrameEnvelope.encode(FrameFixtures.frame(identity: identity))
            XCTAssertEqual(try Data(contentsOf: fileURL(for: identity, in: directory)), expected)
        }

        let realIdentity = identities[0]
        await store.enqueueWrite(try FrameFixtures.frame(identity: realIdentity, edit: "real"))
        await store.waitForPendingWrites()
        let persisted = await store.read(for: realIdentity)?.frame.signature.editHash
        XCTAssertEqual(persisted, "real")
    }

    func testScheduledPlaceholderSweepYieldsCancelsResumesAndKeepsRealFrames() async throws {
        let directory = cacheDirectory("scheduled-placeholder-sweep")
        let scheduler = ImageWorkScheduler()
        let gate = PlaceholderSweepGate()
        scheduler.enqueue(id: .init("visible-editor-work"), lane: .editor, priority: .activeEditor) {
            await gate.wait()
        }
        try await waitUntil("visible editor work to start") { scheduler.runningEditorCount == 1 }

        let placeholderIdentities = (0..<19).map { _ -> PortablePhotoIdentity in
            let assetID = PortablePhotoAssetID()
            return PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: PortablePhotoSourceFingerprint(
                    contentHash: "browsing:\(assetID.raw)", decoderVersion: "browsing-v1"
                )
            )
        }
        let realIdentity = FrameFixtures.identity()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for identity in placeholderIdentities + [realIdentity] {
            let data = try PresentationFrameEnvelope.encode(FrameFixtures.frame(identity: identity))
            try data.write(to: fileURL(for: identity, in: directory))
        }

        let store = LatestPreviewFrameStore(directory: directory, workScheduler: scheduler)
        let containsReal = await store.contains(realIdentity)
        XCTAssertTrue(containsReal)
        try await waitUntil("placeholder maintenance to wait behind the editor") {
            scheduler.pendingPackageIOCount == 1
        }
        let sweepID = try XCTUnwrap(scheduler.admissionLog.last?.id)
        XCTAssertEqual(scheduler.admissionLog.last?.priority, .background)

        scheduler.cancel(id: sweepID)
        try await waitUntilAsync("the cancelled sweep to clear its scheduled state") {
            !(await store.placeholderSweepIsScheduled)
        }
        let realDuringSweep = await store.read(for: realIdentity)
        XCTAssertNotNil(realDuringSweep)
        try await waitUntil("the resumed maintenance job to queue") {
            scheduler.pendingPackageIOCount == 1
        }
        XCTAssertGreaterThanOrEqual(scheduler.admissionLog.filter { $0.id == sweepID }.count, 2)

        await gate.release()
        try await waitUntilAsync("all legacy placeholders to be swept") {
            let remainingFrames = try self.frameFiles(in: directory).count
            let scheduled = await store.placeholderSweepIsScheduled
            return remainingFrames == 1 && !scheduled
                && scheduler.pendingPackageIOCount == 0 && scheduler.runningPackageIOCount == 0
        }
        let largestBatch = await store.placeholderSweepLargestBatch
        let filesExamined = await store.placeholderSweepFilesExamined
        XCTAssertLessThanOrEqual(largestBatch, 8)
        XCTAssertGreaterThan(filesExamined, 8)
        let realAfterSweep = await store.read(for: realIdentity)
        XCTAssertNotNil(realAfterSweep)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: fileURL(for: realIdentity, in: directory).path))
        await scheduler.cancelAllAndWait()
    }

    func testThumbnailSweepResumesAcrossScheduledTicksAndPreservesRealRecord() async throws {
        let directory = cacheDirectory("scheduled-thumbnail-sweep")
        let scheduler = ImageWorkScheduler()
        let gate = PlaceholderSweepGate()
        scheduler.enqueue(id: .init("visible-thumbnail-work"), lane: .editor, priority: .activeEditor) {
            await gate.wait()
        }
        try await waitUntil("visible thumbnail work to start") { scheduler.runningEditorCount == 1 }

        let identities = (0..<18).map { _ -> PortablePhotoIdentity in
            let assetID = PortablePhotoAssetID()
            return PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: PortablePhotoSourceFingerprint(
                    contentHash: "browsing:\(assetID.raw)", decoderVersion: "browsing-v1"
                )
            )
        }
        let realIdentity = FrameFixtures.identity()
        let packed = try PortablePackagePackedThumbnailStore(at: directory)
        let records = try identities.map { identity -> PortablePackagePackedThumbnailStore.Record in
            let key = try XCTUnwrap(ThumbnailFrameStore.key(.original, for: identity.assetID))
            return .init(
                key: key,
                data: try PresentationFrameEnvelope.encode(FrameFixtures.frame(identity: identity))
            )
        } + [
            .init(
                key: try XCTUnwrap(ThumbnailFrameStore.key(.original, for: realIdentity.assetID)),
                data: try PresentationFrameEnvelope.encode(FrameFixtures.frame(identity: realIdentity))
            )
        ]
        let realRecord = try XCTUnwrap(records.last?.data)
        try packed.append(records: records)

        let store = ThumbnailFrameStore(directory: directory, workScheduler: scheduler)
        let initialCount = await store.liveEntryCount
        XCTAssertEqual(initialCount, records.count)
        try await waitUntil("thumbnail maintenance to wait behind the editor") {
            scheduler.pendingPackageIOCount == 1
        }
        let sweepID = try XCTUnwrap(scheduler.admissionLog.last?.id)
        scheduler.cancel(id: sweepID)
        try await waitUntilAsync("the thumbnail sweep cancellation to settle") {
            !(await store.placeholderSweepIsScheduled)
        }
        let resumedCount = await store.liveEntryCount
        XCTAssertEqual(resumedCount, records.count)
        try await waitUntil("the thumbnail maintenance job to resume") {
            scheduler.pendingPackageIOCount == 1
        }

        await gate.release()
        try await waitUntilAsync("thumbnail placeholders to be removed") {
            let count = await store.liveEntryCount
            let scheduled = await store.placeholderSweepIsScheduled
            return count == 1 && !scheduled && scheduler.pendingPackageIOCount == 0
                && scheduler.runningPackageIOCount == 0
        }
        let largestBatch = await store.placeholderSweepLargestBatch
        let recordsExamined = await store.placeholderSweepRecordsExamined
        XCTAssertLessThanOrEqual(largestBatch, 8)
        XCTAssertGreaterThan(recordsExamined, 8)
        let verify = try PortablePackagePackedThumbnailStore(at: directory)
        let realKey = try XCTUnwrap(ThumbnailFrameStore.key(.original, for: realIdentity.assetID))
        XCTAssertEqual(try verify.lookup(realKey), .found(realRecord))
        await scheduler.cancelAllAndWait()
    }

    func testReadingLegacyPlaceholderRemovesOnlyItsFileAndCorrectsSizeIndex() async throws {
        let directory = cacheDirectory("placeholder-read")
        let assetID = PortablePhotoAssetID()
        let placeholder = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "browsing:\(assetID.raw)", decoderVersion: "browsing-v1"
            )
        )
        let real = FrameFixtures.identity()
        let placeholderData = try PresentationFrameEnvelope.encode(
            FrameFixtures.frame(identity: placeholder)
        )
        let realData = try PresentationFrameEnvelope.encode(FrameFixtures.frame(identity: real))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try placeholderData.write(to: fileURL(for: placeholder, in: directory))
        try realData.write(to: fileURL(for: real, in: directory))

        let store = LatestPreviewFrameStore(directory: directory)
        let outcome = await store.readWithOutcome(for: placeholder)
        XCTAssertNil(outcome.hit)
        XCTAssertFalse(outcome.corrupt)
        let placeholderURL = try fileURL(for: placeholder, in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: placeholderURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL(for: real, in: directory)), realData)
        let indexedSize = await store.currentSizeBytes
        XCTAssertEqual(indexedSize, Int64(realData.count))
    }

    func testFileNamesNeverDerivePathsOrFingerprints() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let identity = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await store.waitForPendingWrites()
        let replaced = FrameFixtures.identity(asset: identity.assetID, content: "replaced-bytes")
        await store.enqueueWrite(try FrameFixtures.frame(identity: replaced))
        await store.waitForPendingWrites()
        XCTAssertEqual(
            try frameFiles(in: directory).map(\.lastPathComponent),
            [try fileURL(for: identity, in: directory).lastPathComponent],
            "a source replacement must overwrite its predecessor, not accumulate beside it"
        )
    }

    func testBurstOfWritesCoalescesToTheNewestFrame() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let identity = FrameFixtures.identity()
        for index in 0..<8 {
            await store.enqueueWrite(try FrameFixtures.frame(identity: identity, edit: "edit-\(index)"))
        }
        await store.waitForPendingWrites()
        XCTAssertEqual(try frameFiles(in: directory).count, 1)
        let awaited2 = await store.read(for: identity)?.frame.signature.editHash
        XCTAssertEqual(awaited2, "edit-7")
    }

    func testPixelEpochMismatchSurvivesAndClassifiesStaleCompatible() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let identity = FrameFixtures.identity()
        let unrelated = FrameFixtures.identity()
        await store.enqueueWrite(
            try FrameFixtures.frame(identity: identity, epoch: RenderPipeline.pixelEpoch - 1)
        )
        await store.enqueueWrite(try FrameFixtures.frame(identity: unrelated))
        await store.waitForPendingWrites()

        // A "new build": a fresh store over the same directory must not wipe anything.
        let relaunched = LatestPreviewFrameStore(directory: directory)
        let hit = try unwrapAwaited(await relaunched.read(for: identity))
        XCTAssertEqual(
            FrameClassifier.classify(
                hit.frame.metadata,
                against: FrameCurrentInputs(source: identity, editHash: "edit", look: LookSignature.none)
            ),
            .staleCompatible
        )
        let awaited3 = await relaunched.read(for: unrelated)
        XCTAssertNotNil(awaited3)
        XCTAssertEqual(try frameFiles(in: directory).count, 2)
    }

    func testUnsupportedStorageVersionIsAPerEntryMissThatNextWriteRepairs() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let future = FrameFixtures.identity()
        let healthy = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: future))
        await store.enqueueWrite(try FrameFixtures.frame(identity: healthy))
        await store.waitForPendingWrites()
        let url = try fileURL(for: future, in: directory)
        var bytes = try Data(contentsOf: url)
        bytes.replaceSubrange(4..<8, with: [0, 0, 0, 77])
        try bytes.write(to: url)

        let relaunched = LatestPreviewFrameStore(directory: directory)
        let awaited4 = await relaunched.read(for: future)
        XCTAssertNil(awaited4)
        let awaited5 = await relaunched.read(for: healthy)
        XCTAssertNotNil(awaited5, "other entries are unaffected")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "ignored, not deleted")

        await relaunched.enqueueWrite(try FrameFixtures.frame(identity: future, edit: "repaired"))
        await relaunched.waitForPendingWrites()
        let awaited6 = await relaunched.read(for: future)?.frame.signature.editHash
        XCTAssertEqual(awaited6, "repaired")
    }

    func testCorruptEntriesAreRemovedIndividually() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let corrupt = FrameFixtures.identity()
        let truncated = FrameFixtures.identity()
        let healthy = FrameFixtures.identity()
        for identity in [corrupt, truncated, healthy] {
            await store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        }
        await store.waitForPendingWrites()
        let corruptURL = try fileURL(for: corrupt, in: directory)
        var bytes = try Data(contentsOf: corruptURL)
        bytes[0] = 0
        try bytes.write(to: corruptURL)
        let truncatedURL = try fileURL(for: truncated, in: directory)
        try Data(contentsOf: truncatedURL).prefix(40).write(to: truncatedURL)

        let relaunched = LatestPreviewFrameStore(directory: directory)
        let awaited7 = await relaunched.read(for: corrupt)
        XCTAssertNil(awaited7)
        let awaited8 = await relaunched.read(for: truncated)
        XCTAssertNil(awaited8)
        let awaited9 = await relaunched.read(for: healthy)
        XCTAssertNotNil(awaited9)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: truncatedURL.path))
        XCTAssertEqual(try frameFiles(in: directory).count, 1)
    }

    func testEnvelopeRejectsNonJPEGPayloadEvenWhenImageIOCanDecodeIt() throws {
        let identity = FrameFixtures.identity()
        let frame = try FrameFixtures.frame(identity: identity)
        let pngURL = try Fixtures.writeGradientPNG(
            width: frame.metadata.pixelWidth, height: frame.metadata.pixelHeight,
            named: "wrong-frame-format.png", in: tempDirectory
        )
        let pngFrame = PresentationFrame(
            metadata: frame.metadata, rasterData: try Data(contentsOf: pngURL)
        )

        XCTAssertThrowsError(try PresentationFrameEnvelope.decodeRaster(of: pngFrame)) { error in
            XCTAssertEqual(error as? PresentationFrameEnvelope.DecodeError, .corruptRaster)
        }
    }

    func testAFileSittingUnderAnotherAssetsNameIsAMiss() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let owner = FrameFixtures.identity()
        let impostor = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: owner))
        await store.waitForPendingWrites()
        try FileManager.default.copyItem(
            at: try fileURL(for: owner, in: directory),
            to: try fileURL(for: impostor, in: directory)
        )
        let relaunched = LatestPreviewFrameStore(directory: directory)
        let awaited10 = await relaunched.read(for: impostor)
        XCTAssertNil(awaited10)
        let awaited11 = await relaunched.read(for: owner)
        XCTAssertNotNil(awaited11)
    }

    func testIdentityInvalidationPreservesOtherAssets() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let removed = FrameFixtures.identity()
        let kept = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: removed))
        await store.enqueueWrite(try FrameFixtures.frame(identity: kept))
        await store.waitForPendingWrites()

        let replacement = FrameFixtures.identity(asset: removed.assetID, content: "replacement")
        await store.invalidate(identities: [replacement])

        let contains = await store.contains(removed)
        XCTAssertFalse(contains)
        let awaited12 = await store.read(for: removed)
        XCTAssertNil(awaited12)
        let awaited13 = await store.read(for: kept)
        XCTAssertNotNil(awaited13)
    }

    func testInvalidationCancelsAPendingWrite() async throws {
        let directory = cacheDirectory()
        let store = LatestPreviewFrameStore(directory: directory)
        let identity = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await store.invalidate(identities: [identity])
        await store.waitForPendingWrites()
        let contains = await store.contains(identity)
        XCTAssertFalse(contains)
        XCTAssertEqual(try frameFiles(in: directory).count, 0)
    }

    func testCapEvictsLeastRecentlyUsedAndKeepsNewest() async throws {
        let directory = cacheDirectory()
        let first = FrameFixtures.identity()
        let second = FrameFixtures.identity()
        let uncapped = LatestPreviewFrameStore(directory: directory)
        await uncapped.enqueueWrite(try FrameFixtures.frame(identity: first, width: 256, height: 192))
        await uncapped.waitForPendingWrites()
        let firstURL = try fileURL(for: first, in: directory)
        let firstSize = try XCTUnwrap(firstURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: firstURL.path
        )

        let capped = LatestPreviewFrameStore(directory: directory, capBytes: Int64(firstSize) + 1)
        await capped.enqueueWrite(try FrameFixtures.frame(identity: second, width: 256, height: 192))
        await capped.waitForPendingWrites()
        let awaited14 = await capped.read(for: first)
        XCTAssertNil(awaited14)
        let awaited15 = await capped.read(for: second)
        XCTAssertNotNil(awaited15)
        XCTAssertEqual(try frameFiles(in: directory).count, 1)
    }

    func testPinnedAssetsSurviveEviction() async throws {
        let directory = cacheDirectory()
        let pinned = FrameFixtures.identity()
        let loose = FrameFixtures.identity()
        let newest = FrameFixtures.identity()
        let probe = LatestPreviewFrameStore(directory: directory)
        await probe.enqueueWrite(try FrameFixtures.frame(identity: pinned, width: 256, height: 192))
        await probe.enqueueWrite(try FrameFixtures.frame(identity: loose, width: 256, height: 192))
        await probe.waitForPendingWrites()
        let size = try XCTUnwrap(
            try fileURL(for: pinned, in: directory).resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        // The pinned file is the oldest; without pinning it would be evicted first.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: try fileURL(for: pinned, in: directory).path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)],
            ofItemAtPath: try fileURL(for: loose, in: directory).path
        )

        let store = LatestPreviewFrameStore(directory: directory, capBytes: Int64(size) * 2 + 1)
        await store.setPinned([pinned.assetID])
        await store.enqueueWrite(try FrameFixtures.frame(identity: newest, width: 256, height: 192))
        await store.waitForPendingWrites()

        let awaited16 = await store.read(for: pinned)
        XCTAssertNotNil(awaited16)
        let awaited17 = await store.read(for: loose)
        XCTAssertNil(awaited17)
        let awaited18 = await store.read(for: newest)
        XCTAssertNotNil(awaited18)
    }

    func testLegacyExactKeyFilesAreIgnoredAndRemovedLazily() async throws {
        let directory = cacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyA = directory.appendingPathComponent("preview-aaaa-bbbb.jpg")
        let legacyB = directory.appendingPathComponent("preview-cccc-dddd.jpg")
        let version = directory.appendingPathComponent("version")
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data(try FrameFixtures.jpeg()).write(to: legacyA)
        try Data(try FrameFixtures.jpeg()).write(to: legacyB)
        try Data("34:3".utf8).write(to: version)
        try Data("keep".utf8).write(to: unrelated)

        let store = LatestPreviewFrameStore(directory: directory)
        let identity = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await store.waitForPendingWrites()
        await store.waitForLegacyCleanup()

        for url in [legacyA, legacyB, version] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        let awaited19 = await store.read(for: identity)
        XCTAssertNotNil(awaited19)
    }

    func testConstructingAStoreDoesNoFilesystemWork() throws {
        let directory = cacheDirectory("never-created")
        _ = LatestPreviewFrameStore(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testUnreadableDirectoryDegradesToMisses() async throws {
        let blocker = tempDirectory.appendingPathComponent("blocker")
        try Data("file".utf8).write(to: blocker)
        let store = LatestPreviewFrameStore(directory: blocker.appendingPathComponent("frames"))
        let identity = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await store.waitForPendingWrites()
        let awaited20 = await store.read(for: identity)
        XCTAssertNil(awaited20)

        let reopened = LatestPreviewFrameStore(directory: blocker.appendingPathComponent("frames"))
        let reopenedHit = await reopened.read(for: identity)
        XCTAssertNil(reopenedHit, "a failed cache write must reopen as a cache miss")
    }

    func testSettledHitSkipsTheRendererAndStillAdmitsHistogram() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: "cache-hit.png", in: tempDirectory
        )
        let data = try Data(contentsOf: imageURL)
        let rendered = try XCTUnwrap(
            CGImageSourceCreateWithURL(imageURL as CFURL, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            }
        )
        let fake = FakeRenderEngine(previewResult: rendered)
        let cacheDirectory = tempDirectory.appendingPathComponent("shared-preview-cache")
        let viewModel = makeAppViewModel(
            engine: fake, previewFrameStoreDirectory: cacheDirectory
        )

        viewModel.openImage(data: data, name: "cache-hit.png")
        try await waitUntil("first preview") { viewModel.previewState == .ready }
        try await waitUntil("disk cache write") {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory, includingPropertiesForKeys: nil
            ) else { return false }
            return files.contains { $0.pathExtension == "kframe" }
        }
        let firstRenderCount = await fake.previewRequests.count
        XCTAssertGreaterThan(firstRenderCount, 0)

        viewModel.openImage(data: data, name: "cache-hit.png")
        try await waitUntil("warm preview") { viewModel.previewState == .ready }
        let warmRenderCount = await fake.previewRequests.count
        XCTAssertEqual(warmRenderCount, firstRenderCount,
                       "a settled disk hit must not call the render engine")

        viewModel.inspectorState.isPresented = true
        viewModel.inspectorState.tab = .info
        try await waitUntil("histogram from warm presentation") { viewModel.histogram != nil }
    }

    /// A cached entry is the whole photo at the canonical long edge. A zoomed request asks for an
    /// ROI, so reusing that entry would publish the complete frame through ROI geometry — which is
    /// what made a double-click in the editor look like a jump back to Fit.
    func testZoomedSettledRequestRendersInsteadOfAdoptingTheCanonicalDiskEntry() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: "zoom-cache.png", in: tempDirectory
        )
        let data = try Data(contentsOf: imageURL)
        let rendered = try XCTUnwrap(
            CGImageSourceCreateWithURL(imageURL as CFURL, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            }
        )
        let fake = FakeRenderEngine(previewResult: rendered)
        let cacheDirectory = tempDirectory.appendingPathComponent("zoom-preview-cache")
        let viewModel = makeAppViewModel(
            engine: fake, previewFrameStoreDirectory: cacheDirectory
        )

        viewModel.openImage(data: data, name: "zoom-cache.png")
        try await waitUntil("first preview") { viewModel.previewState == .ready }
        try await waitUntil("disk cache write") {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory, includingPropertiesForKeys: nil
            ) else { return false }
            return files.contains { $0.pathExtension == "kframe" }
        }
        let warmCount = await fake.previewRequests.count

        viewModel.toggleCanvasZoom()
        XCTAssertEqual(viewModel.canvasState.navigation.mode, .custom)
        XCTAssertGreaterThan(viewModel.canvasState.navigation.zoom, 1)

        let deadline = Date().addingTimeInterval(5)
        var renderCount = await fake.previewRequests.count
        while renderCount <= warmCount, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
            renderCount = await fake.previewRequests.count
        }
        XCTAssertGreaterThan(renderCount, warmCount,
                             "a zoomed settled request must reach the renderer")
        let requests = await fake.previewRequests
        let zoomed = try XCTUnwrap(requests.last)
        XCTAssertNotNil(
            zoomed.sourceROI,
            "the zoomed frame must be rendered as an ROI rather than taken from the full-photo cache"
        )
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5,
        _ condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitUntilAsync(
        _ description: String, timeout: TimeInterval = 5,
        _ condition: @MainActor @escaping () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
