import CoreGraphics
import CoreImage
import XCTest
@testable import KromoraKit

/// Builders shared by the frame, envelope, and store tests.
enum FrameFixtures {
    static let lookID = LUTID(raw: "look")

    static func identity(
        asset: PortablePhotoAssetID = PortablePhotoAssetID(), content: String = "source"
    ) -> PortablePhotoIdentity {
        PortablePhotoIdentity(
            assetID: asset,
            sourceFingerprint: .data(Data(content.utf8), decoderVersion: "test")
        )
    }

    static func digest(_ value: UInt8 = 128) -> PerceptualDigest {
        PerceptualDigest(bytes: Data(repeating: value, count: PerceptualDigest.byteCount))!
    }

    static func metadata(
        identity: PortablePhotoIdentity,
        edit: String = "edit",
        look: LookSignature = .none,
        space: WorkingSpace = .sRGB,
        epoch: Int = RenderPipeline.pixelEpoch,
        raster: RasterColorSpace = .sRGB,
        kind: PresentationFrameKind = .preview2048,
        width: Int = 64, height: Int = 48,
        digest: PerceptualDigest = FrameFixtures.digest()
    ) -> PresentationFrameMetadata {
        PresentationFrameMetadata(
            identity: identity, kind: kind,
            signature: FrameSignature(
                source: identity, editHash: edit, look: look, workingSpace: space,
                pixelEpoch: epoch
            ),
            geometry: PresentedGeometry(
                crop: CropAdjustments(), rotation: ImageRotation(rawValue: 0)!,
                orientedAspectRatio: Double(width) / Double(max(abs(height), 1))
            ),
            rasterColorSpace: raster, perceptualDigest: digest,
            presentedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pixelWidth: width, pixelHeight: height
        )
    }

    static func jpeg(
        width: Int = 64, height: Int = 48, red: CGFloat = 0.5, green: CGFloat = 0.4,
        blue: CGFloat = 0.3
    ) throws -> Data {
        let image = try Fixtures.makeCGImage(
            width: width, height: height, red: red, green: green, blue: blue
        )
        return try XCTUnwrap(RenderEngineResources.jpegData(for: image, quality: 0.9))
    }

    static func frame(
        identity: PortablePhotoIdentity = FrameFixtures.identity(),
        edit: String = "edit", look: LookSignature = .none, space: WorkingSpace = .sRGB,
        epoch: Int = RenderPipeline.pixelEpoch, width: Int = 64, height: Int = 48,
        red: CGFloat = 0.5
    ) throws -> PresentationFrame {
        PresentationFrame(
            metadata: metadata(
                identity: identity, edit: edit, look: look, space: space, epoch: epoch,
                width: width, height: height
            ),
            rasterData: try jpeg(width: width, height: height, red: red)
        )
    }
}

final class PresentationFrameClassifierTests: XCTestCase {
    private let identity = FrameFixtures.identity()
    private let look = LookSignature.resolved(id: FrameFixtures.lookID, contentHash: "h1")

    private func current(
        edit: String? = "edit", look: LookSignature? = LookSignature.none,
        space: WorkingSpace = .sRGB, epoch: Int = RenderPipeline.pixelEpoch,
        source: PortablePhotoIdentity? = nil
    ) -> FrameCurrentInputs {
        FrameCurrentInputs(
            source: source ?? identity, editHash: edit, look: look, workingSpace: space,
            pixelEpoch: epoch
        )
    }

    private func classify(
        _ metadata: PresentationFrameMetadata, _ inputs: FrameCurrentInputs
    ) -> FrameClassification { FrameClassifier.classify(metadata, against: inputs) }

    func testEveryInputEqualIsExact() {
        let frame = FrameFixtures.metadata(identity: identity, look: look)
        XCTAssertEqual(classify(frame, current(look: look)), .exact)
    }

    func testEditMismatchIsStaleCompatible() {
        let frame = FrameFixtures.metadata(identity: identity, edit: "old")
        XCTAssertEqual(classify(frame, current(edit: "new")), .staleCompatible)
    }

    func testLookContentChangeIsStaleCompatible() {
        let frame = FrameFixtures.metadata(identity: identity, look: look)
        let replaced = LookSignature.resolved(id: FrameFixtures.lookID, contentHash: "h2")
        XCTAssertEqual(classify(frame, current(look: replaced)), .staleCompatible)
        XCTAssertEqual(classify(frame, current(look: LookSignature.none)), .staleCompatible)
    }

    func testPixelEpochBumpIsStaleCompatibleNotUnusable() {
        let frame = FrameFixtures.metadata(identity: identity, epoch: RenderPipeline.pixelEpoch - 1)
        XCTAssertEqual(classify(frame, current()), .staleCompatible)
    }

    func testEveryRejectionReportsItsFirstReason() {
        let otherAsset = FrameFixtures.identity()
        let otherFingerprint = FrameFixtures.identity(asset: identity.assetID, content: "replaced")
        let placeholder = PortablePhotoIdentity(
            assetID: identity.assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(contentHash: "", decoderVersion: "test")
        )
        let rows: [(FrameRejectionReason, PresentationFrameMetadata, FrameCurrentInputs)] = [
            (.assetMismatch, FrameFixtures.metadata(identity: otherAsset), current()),
            (.sourceFingerprintMismatch, FrameFixtures.metadata(identity: otherFingerprint), current()),
            (.placeholderSourceIdentity, FrameFixtures.metadata(identity: identity), current(source: placeholder)),
            (.dimensionsInvalid, FrameFixtures.metadata(identity: identity, width: 0), current()),
            (.colorSpaceUnpresentable, FrameFixtures.metadata(identity: identity, raster: .displayP3), current())
        ]

        for (reason, metadata, inputs) in rows {
            let result = FrameClassifier.classifyWithReason(metadata, against: inputs)
            XCTAssertEqual(result.classification, .unusable, "\(reason)")
            XCTAssertEqual(result.reason, reason, "\(reason)")
            XCTAssertEqual(FrameClassifier.classify(metadata, against: inputs), .unusable, "\(reason)")
        }
    }

    func testSRGBFrameUnderAWiderWorkingSpaceIsStaleCompatible() {
        let frame = FrameFixtures.metadata(identity: identity, space: .sRGB, raster: .sRGB)
        XCTAssertEqual(classify(frame, current(space: .displayP3)), .staleCompatible)
    }

    func testDisplayP3RasterCannotBePresentedInSRGB() {
        let frame = FrameFixtures.metadata(identity: identity, space: .displayP3, raster: .displayP3)
        XCTAssertEqual(classify(frame, current(space: .sRGB)), .unusable)
        XCTAssertEqual(classify(frame, current(space: .displayP3)), .exact)
    }

    func testUnresolvedInputsAreProvisionalOnly() {
        let frame = FrameFixtures.metadata(identity: identity)
        XCTAssertEqual(classify(frame, current(edit: nil, look: nil)), .provisionalOnly)
        XCTAssertEqual(classify(frame, current(edit: "edit", look: nil)), .provisionalOnly)
        XCTAssertEqual(classify(frame, current(edit: nil, look: LookSignature.none)), .provisionalOnly)
    }

    func testUnresolvedLookNeverMatchesEvenItself() {
        let unresolved = LookSignature.unresolved(id: FrameFixtures.lookID)
        let frame = FrameFixtures.metadata(identity: identity, look: unresolved)
        XCTAssertEqual(classify(frame, current(look: unresolved)), .provisionalOnly)
        XCTAssertEqual(classify(frame, current(look: look)), .staleCompatible)
    }

    func testSourceReplacementIsUnusableEvenWhenEverythingElseMatches() {
        let frame = FrameFixtures.metadata(identity: identity)
        let replaced = FrameFixtures.identity(asset: identity.assetID, content: "replacement")
        XCTAssertEqual(classify(frame, current(source: replaced)), .unusable)
        XCTAssertEqual(
            classify(frame, current(edit: nil, look: nil, source: replaced)), .unusable,
            "an unresolved edit must not let a different source through"
        )
    }

    func testDifferentAssetIsUnusable() {
        let frame = FrameFixtures.metadata(identity: identity)
        XCTAssertEqual(classify(frame, current(source: FrameFixtures.identity())), .unusable)
    }

    func testInvalidStoredResolutionIsUnusable() {
        let tooLarge = FrameFixtures.metadata(
            identity: identity, width: FrameClassifier.previewLongEdge + 1, height: 10
        )
        XCTAssertEqual(classify(tooLarge, current()), .unusable)
        let empty = FrameFixtures.metadata(identity: identity, width: 0, height: 10)
        XCTAssertEqual(classify(empty, current()), .unusable)
        let canonical = FrameFixtures.metadata(
            identity: identity, width: FrameClassifier.previewLongEdge, height: 1365
        )
        XCTAssertEqual(classify(canonical, current()), .exact)
    }

    func testSourceFingerprintGeometryIsTolerantOfAnUnknownSide() {
        let known = PortablePhotoIdentity(
            assetID: identity.assetID,
            sourceFingerprint: identity.sourceFingerprint.with(
                geometry: PhotoPixelDimensions(width: 400, height: 300)
            )
        )
        let frame = FrameFixtures.metadata(identity: known)
        XCTAssertEqual(classify(frame, current(source: identity)), .exact)
    }
}

final class ThumbnailFrameStoreTests: TempDirectoryTestCase {
    func testStableKeysReplaceTheLiveEditedRecordAndSurviveRelaunch() async throws {
        let identity = FrameFixtures.identity()
        let directory = tempDirectory.appendingPathComponent("Thumbnails")
        let store = ThumbnailFrameStore(directory: directory)
        let first = try thumbnailFrame(identity: identity, kind: .editedThumbnail480, red: 0.2)
        let second = try thumbnailFrame(identity: identity, kind: .editedThumbnail480, red: 0.8)
        let original = try thumbnailFrame(identity: identity, kind: .originalThumbnail480, red: 0.4)

        await store.enqueueWrite(first)
        await store.enqueueWrite(second)
        await store.enqueueWrite(original)
        let pendingCount = await store.pendingWriteCount
        XCTAssertEqual(pendingCount, 2)
        await store.flush()
        let liveCount = await store.liveEntryCount
        XCTAssertEqual(liveCount, 2)

        let relaunched = ThumbnailFrameStore(directory: directory)
        let frames = await relaunched.readFrames(for: identity)
        XCTAssertEqual(frames.original?.frame.kind, .originalThumbnail480)
        XCTAssertEqual(frames.edited?.frame.kind, .editedThumbnail480)
        XCTAssertEqual(frames.edited?.frame.rasterData, second.rasterData)
        let relaunchedCount = await relaunched.liveEntryCount
        XCTAssertEqual(relaunchedCount, 2)
    }

    func testUnavailableDirectoryWriteReopensAsCacheMiss() async throws {
        let blocker = tempDirectory.appendingPathComponent("thumbnail-blocker")
        try Data("file".utf8).write(to: blocker)
        let directory = blocker.appendingPathComponent("Thumbnails")
        let identity = FrameFixtures.identity()
        let store = ThumbnailFrameStore(directory: directory)
        await store.enqueueWrite(try thumbnailFrame(
            identity: identity, kind: .editedThumbnail480, red: 0.6
        ))
        await store.flush()

        let reopened = ThumbnailFrameStore(directory: directory)
        let frames = await reopened.readFrames(for: identity)
        XCTAssertNil(frames.original)
        XCTAssertNil(frames.edited, "a failed cache write must reopen as a cache miss")
    }

    func testReadWindowIsVisibleIDsPlusAtMostOnePrefetchPage() {
        let visible = (0..<5).map { PhotoAssetID(rawValue: "visible-\($0)") }
        let following = (0..<80).map { PhotoAssetID(rawValue: "following-\($0)") }
        let window = ThumbnailFrameReadPolicy.window(visible: visible, following: following)

        XCTAssertEqual(ThumbnailFrameReadPolicy.maxConcurrentReads, 4)
        XCTAssertEqual(ThumbnailFrameReadPolicy.prefetchPageSize, 24)
        XCTAssertEqual(window.count, ThumbnailFrameReadPolicy.windowCap(visibleCount: visible.count))
        XCTAssertEqual(Array(window.prefix(visible.count)), visible)
        XCTAssertEqual(Set(window).count, window.count)
    }

    func testPlaceholderWritesAreSkippedForBothKindsAndLegacyRecordsAreSwept() async throws {
        let directory = tempDirectory.appendingPathComponent("PlaceholderThumbnails")
        let store = ThumbnailFrameStore(directory: directory)
        let assetID = PortablePhotoAssetID()
        let placeholder = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "browsing:\(assetID.raw)", decoderVersion: "browsing-v1"
            )
        )
        let placeholderOriginal = try thumbnailFrame(
            identity: placeholder, kind: .originalThumbnail480, red: 0.2
        )
        let placeholderEdited = try thumbnailFrame(
            identity: placeholder, kind: .editedThumbnail480, red: 0.8
        )
        await store.enqueueWrite(placeholderOriginal)
        await store.enqueueWrite(placeholderEdited)
        await store.flush()
        let skipped = await store.placeholderWritesSkipped
        let countAfterPlaceholderWrites = await store.liveEntryCount
        XCTAssertEqual(skipped, 2)
        XCTAssertEqual(countAfterPlaceholderWrites, 0)

        let real = FrameFixtures.identity()
        await store.enqueueWrite(try thumbnailFrame(
            identity: real, kind: .originalThumbnail480, red: 0.4
        ))
        await store.enqueueWrite(try thumbnailFrame(
            identity: real, kind: .editedThumbnail480, red: 0.6
        ))
        await store.flush()
        let realCount = await store.liveEntryCount
        XCTAssertEqual(realCount, 2)

        let legacyID = PortablePhotoAssetID()
        let legacy = PortablePhotoIdentity(
            assetID: legacyID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: "browsing:\(legacyID.raw)", decoderVersion: "browsing-v1"
            )
        )
        let packed = try PortablePackagePackedThumbnailStore(at: directory)
        let legacyFrame = try thumbnailFrame(
            identity: legacy, kind: .originalThumbnail480, red: 0.3
        )
        let legacyKey = try XCTUnwrap(ThumbnailFrameStore.key(.original, for: legacyID))
        let realKey = try XCTUnwrap(ThumbnailFrameStore.key(.original, for: real.assetID))
        let realBefore: Data
        if case .found(let data) = try packed.lookup(realKey) { realBefore = data }
        else { throw XCTSkip("real thumbnail setup did not persist") }
        try packed.append(.init(
            key: legacyKey, data: try PresentationFrameEnvelope.encode(legacyFrame)
        ))

        let reopened = ThumbnailFrameStore(directory: directory)
        let result = await reopened.readWithOutcome(.original, for: legacy)
        XCTAssertNil(result.hit)
        XCTAssertFalse(result.corrupt)
        let verify = try PortablePackagePackedThumbnailStore(at: directory)
        XCTAssertEqual(try verify.lookup(legacyKey), .missing)
        XCTAssertEqual(try verify.lookup(realKey), .found(realBefore))
    }

    private func thumbnailFrame(
        identity: PortablePhotoIdentity, kind: PresentationFrameKind, red: CGFloat
    ) throws -> PresentationFrame {
        let base = try FrameFixtures.frame(identity: identity, red: red)
        let baseMetadata = base.metadata
        let metadata = PresentationFrameMetadata(
            identity: baseMetadata.identity,
            kind: kind,
            signature: baseMetadata.signature,
            geometry: baseMetadata.geometry,
            rasterColorSpace: baseMetadata.rasterColorSpace,
            perceptualDigest: baseMetadata.perceptualDigest,
            presentedAt: baseMetadata.presentedAt,
            pixelWidth: baseMetadata.pixelWidth,
            pixelHeight: baseMetadata.pixelHeight
        )
        return PresentationFrame(metadata: metadata, rasterData: base.rasterData)
    }
}

final class FrameLookupLedgerTests: TempDirectoryTestCase {
    func testPreviewStoreDistinguishesMissingAndCorruptFramesWithoutThrowing() async throws {
        let directory = tempDirectory.appendingPathComponent("Previews", isDirectory: true)
        let identity = FrameFixtures.identity()
        let store = LatestPreviewFrameStore(directory: directory)
        let missing = await store.readWithOutcome(for: identity)
        XCTAssertNil(missing.hit)
        XCTAssertFalse(missing.corrupt)

        await store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await store.waitForPendingWrites()
        let file = directory.appendingPathComponent(
            "\(LatestPreviewFrameStore.assetHash(identity.assetID)!).kframe"
        )
        try Data("damaged".utf8).write(to: file)
        let corrupt = await store.readWithOutcome(for: identity)
        XCTAssertNil(corrupt.hit)
        XCTAssertTrue(corrupt.corrupt)
    }

    func testLedgerRecordsMonotonicEntriesAndSummarizesRejections() async {
        let ledger = FrameLookupLedger()
        await ledger.record(surface: .editPreview, outcome: .rejected(.assetMismatch))
        await ledger.record(surface: .editPreview, outcome: .rejected(.assetMismatch))
        await ledger.record(surface: .editPreview, outcome: .exact)
        let records = await ledger.snapshot()
        XCTAssertEqual(records.count, 3)
        XCTAssertLessThanOrEqual(records[0].timestampNanoseconds, records[1].timestampNanoseconds)
        let summary = await ledger.summary(for: .editPreview)
        XCTAssertTrue(summary.contains("topRejection=assetMismatch:2"))
    }
}

final class PresentationFrameEnvelopeTests: TempDirectoryTestCase {
    private func write(_ frame: PresentationFrame, named name: String = "frame.kframe") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try PresentationFrameEnvelope.encode(frame).write(to: url)
        return url
    }

    private func assertRejects(
        _ data: Data, expected: PresentationFrameEnvelope.DecodeError,
        assetID: PortablePhotoAssetID? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let url = tempDirectory.appendingPathComponent("bad-\(UUID().uuidString).kframe")
        try data.write(to: url)
        XCTAssertThrowsError(
            try PresentationFrameEnvelope.read(from: url, expectedAssetID: assetID),
            file: file, line: line
        ) { error in
            XCTAssertEqual(
                error as? PresentationFrameEnvelope.DecodeError, expected, file: file, line: line
            )
        }
    }

    func testRoundTripPreservesMetadataAndRaster() throws {
        let frame = try FrameFixtures.frame()
        let url = try write(frame)
        let decoded = try PresentationFrameEnvelope.read(
            from: url, expectedAssetID: frame.identity.assetID
        )
        XCTAssertEqual(decoded, frame)
        let image = try PresentationFrameEnvelope.decodeRaster(of: decoded)
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 48)
    }

    func testHeaderOnlyReadSkipsTheRaster() throws {
        let frame = try FrameFixtures.frame()
        let header = try PresentationFrameEnvelope.read(
            from: try write(frame), expectedAssetID: nil, includeRaster: false
        )
        XCTAssertEqual(header.metadata, frame.metadata)
        XCTAssertTrue(header.rasterData.isEmpty)
    }

    func testBadMagicIsRejected() throws {
        var data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        data[0] = 0x58
        try assertRejects(data, expected: .badMagic)
        try assertRejects(Data("not a frame at all, but long enough".utf8), expected: .badMagic)
    }

    func testEveryTruncationIsRejectedWithoutCrashing() throws {
        let data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        for length in [0, 3, 11, 12, 20, 200, data.count - 1] {
            let url = tempDirectory.appendingPathComponent("trunc-\(length).kframe")
            try data.prefix(length).write(to: url)
            XCTAssertThrowsError(
                try PresentationFrameEnvelope.read(from: url, expectedAssetID: nil),
                "length \(length)"
            )
        }
    }

    func testOversizedHeaderLengthIsRejectedBeforeAllocation() throws {
        var data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        data.replaceSubrange(8..<12, with: [0xFF, 0xFF, 0xFF, 0xFF])
        try assertRejects(data, expected: .badHeaderLength)
        data.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        try assertRejects(data, expected: .badHeaderLength)
    }

    func testHeaderLengthPastEndOfFileIsTruncation() throws {
        var data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        let oversized = UInt32(PresentationFrameEnvelope.maxHeaderBytes)
        data.replaceSubrange(8..<12, with: [
            UInt8(oversized >> 24), UInt8((oversized >> 16) & 0xFF),
            UInt8((oversized >> 8) & 0xFF), UInt8(oversized & 0xFF),
        ])
        try assertRejects(data.prefix(2000), expected: .truncated)
    }

    func testUnsupportedStorageVersionIsReportedNotDecoded() throws {
        var data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        data.replaceSubrange(4..<8, with: [0, 0, 0, 99])
        try assertRejects(data, expected: .unsupportedVersion(99))
    }

    func testTrailingBytesAreRejected() throws {
        var data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        data.append(contentsOf: [1, 2, 3])
        try assertRejects(data, expected: .trailingBytes)
    }

    func testIdentityMismatchIsRejected() throws {
        let data = try PresentationFrameEnvelope.encode(FrameFixtures.frame())
        try assertRejects(data, expected: .identityMismatch, assetID: PortablePhotoAssetID())
    }

    func testMetadataSignedForAnotherAssetIsRejected() throws {
        let identity = FrameFixtures.identity()
        let other = FrameFixtures.identity()
        let forged = PresentationFrameMetadata(
            identity: identity, kind: .preview2048,
            signature: FrameSignature(
                source: other, editHash: "e", look: .none, workingSpace: .sRGB,
                pixelEpoch: RenderPipeline.pixelEpoch
            ),
            geometry: PresentedGeometry(
                crop: CropAdjustments(), rotation: ImageRotation(rawValue: 0)!,
                orientedAspectRatio: 1
            ),
            rasterColorSpace: .sRGB, perceptualDigest: FrameFixtures.digest(),
            presentedAt: Date(), pixelWidth: 8, pixelHeight: 8
        )
        let data = try PresentationFrameEnvelope.encode(
            PresentationFrame(metadata: forged, rasterData: try FrameFixtures.jpeg(width: 8, height: 8))
        )
        try assertRejects(data, expected: .identityMismatch)
    }

    func testInvalidDimensionsAreRejected() throws {
        let identity = FrameFixtures.identity()
        for (width, height) in [(0, 10), (10, 0), (-4, 10), (PresentationFrameEnvelope.maxPixelDimension + 1, 10)] {
            let frame = PresentationFrame(
                metadata: FrameFixtures.metadata(identity: identity, width: width, height: height),
                rasterData: try FrameFixtures.jpeg(width: 8, height: 8)
            )
            try assertRejects(try PresentationFrameEnvelope.encode(frame), expected: .invalidDimensions)
        }
    }

    func testCorruptJPEGIsRejectedAtDecode() throws {
        let identity = FrameFixtures.identity()
        let frame = PresentationFrame(
            metadata: FrameFixtures.metadata(identity: identity),
            rasterData: Data(repeating: 0xAB, count: 512)
        )
        let decoded = try PresentationFrameEnvelope.read(
            from: try write(frame), expectedAssetID: identity.assetID
        )
        XCTAssertThrowsError(try PresentationFrameEnvelope.decodeRaster(of: decoded)) {
            XCTAssertEqual($0 as? PresentationFrameEnvelope.DecodeError, .corruptRaster)
        }
    }

    func testJPEGWhoseSizeDisagreesWithMetadataIsRejected() throws {
        let identity = FrameFixtures.identity()
        let frame = PresentationFrame(
            metadata: FrameFixtures.metadata(identity: identity, width: 64, height: 48),
            rasterData: try FrameFixtures.jpeg(width: 32, height: 24)
        )
        let decoded = try PresentationFrameEnvelope.read(
            from: try write(frame), expectedAssetID: identity.assetID
        )
        XCTAssertThrowsError(try PresentationFrameEnvelope.decodeRaster(of: decoded)) {
            XCTAssertEqual($0 as? PresentationFrameEnvelope.DecodeError, .invalidDimensions)
        }
    }
}
