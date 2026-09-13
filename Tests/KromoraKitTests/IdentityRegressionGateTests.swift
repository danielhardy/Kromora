import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import KromoraKit

/// Permanent Phase 1 identity gate.
///
/// This suite intentionally owns the 1,000-asset relocation scenario instead of leaving the
/// individual cache tests to prove the same contract in isolation. Later package/index phases
/// must keep this class in the required serial lane when they change identity or persistence.
@MainActor
final class IdentityRegressionGateTests: TempDirectoryTestCase {

    func testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore() async throws {
        let library = try await SyntheticLibraryGenerator.generate(
            scale: .oneThousand, seed: 0x4001, in: tempDirectory
        )
        let movedRoot = tempDirectory.appendingPathComponent("relocated-library", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: movedRoot)
            try? library.cleanup()
        }

        let snapshots = try library.assets.map { asset -> Snapshot in
            Snapshot(
                asset: asset,
                identity: try identity(for: asset.url, index: asset.index),
                document: asset.editDocument
            )
        }
        XCTAssertEqual(snapshots.count, 1_000)
        XCTAssertEqual(Set(snapshots.map(\.identity)).count, snapshots.count)

        // Write the whole library through the portable UUID key before relocation. A moved open
        // must hit this direct key and report .ready, never enter the legacy relink path.
        let editStore = makeInMemoryEditStore()
        for snapshot in snapshots {
            try await editStore.save(
                snapshot.document,
                for: sourceReference(snapshot, url: snapshot.asset.url)
            )
        }

        // Exercise one real entry in each derived cache while the source is still at its first
        // location. The complete identity vector below covers all 1,000 assets.
        let representative = try XCTUnwrap(snapshots.first)
        let originalSource = ImageSource(
            url: representative.asset.url,
            nativeExtent: extent(for: representative.asset),
            portableIdentity: representative.identity
        )
        let engine = RenderEngine()
        let renderRequest = RenderRequest(
            source: originalSource,
            document: representative.document,
            targetSize: CGSize(width: 32, height: 32),
            quality: .preview,
            output: .raster,
            space: .sRGB
        )
        let originalRender = try await engine.render(renderRequest)

        let previewDirectory = tempDirectory.appendingPathComponent("preview-cache")
        let previewCache = PreviewDiskCache(directory: previewDirectory)
        let previewKey = PreviewDiskCache.Key(
            identity: representative.identity,
            documentHash: representative.document.editHash,
            lookFingerprint: "none",
            targetSizeBucket: "32",
            space: .sRGB
        )
        let originalRaster = try image(at: representative.asset.url)
        previewCache.write(originalRaster, for: previewKey)

        let maskStore = MaskStore(
            directory: tempDirectory.appendingPathComponent("mask-cache")
        )
        let maskKey = MaskCacheKey(
            identity: representative.identity,
            kind: .subject,
            quality: .preview,
            providerVersion: "identity-gate-v1"
        )
        let maskPixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [0, 1, 0.5, 1]
        )
        _ = try await maskStore.store(maskPixels, for: maskKey, quality: .preview)

        try FileManager.default.moveItem(at: library.rootURL, to: movedRoot)

        let movedSnapshots = try library.assets.map { asset -> Snapshot in
            let movedURL = movedRoot.appendingPathComponent(asset.relativePath)
            return Snapshot(
                asset: asset,
                identity: try identity(for: movedURL, index: asset.index),
                document: asset.editDocument,
                url: movedURL
            )
        }

        // The identity is byte-identical for every moved source. This assertion catches path,
        // inode, mtime, and accidental per-open UUID inputs before any individual cache is queried.
        XCTAssertEqual(
            snapshots.map(\.identity), movedSnapshots.map(\.identity),
            "relocating the synthetic library changed at least one portable identity"
        )
        XCTAssertEqual(
            snapshots.map { $0.identity.canonicalData },
            movedSnapshots.map { $0.identity.canonicalData }
        )

        let movedRepresentative = try XCTUnwrap(movedSnapshots.first)
        let movedSource = ImageSource(
            url: movedRepresentative.url,
            nativeExtent: extent(for: movedRepresentative.asset),
            portableIdentity: movedRepresentative.identity
        )
        let movedRequest = RenderRequest(
            source: movedSource,
            document: movedRepresentative.document,
            targetSize: CGSize(width: 32, height: 32),
            quality: .preview,
            output: .raster,
            space: .sRGB
        )
        let movedRender = try await engine.render(movedRequest)
        XCTAssertEqual(movedRender.data, originalRender.data)
        let renderStats = await engine.cacheStatistics()
        XCTAssertEqual(renderStats.preview.misses, 1)
        XCTAssertEqual(renderStats.preview.hits, 1, "a moved source must reuse its render entry")

        let movedPreviewKey = PreviewDiskCache.Key(
            identity: movedRepresentative.identity,
            documentHash: movedRepresentative.document.editHash,
            lookFingerprint: "none",
            targetSizeBucket: "32",
            space: .sRGB
        )
        let movedPreview = previewCache.read(for: movedPreviewKey)
        XCTAssertNotNil(movedPreview, "the moved source must hit its preview-disk entry")
        XCTAssertEqual(movedPreview?.width, originalRaster.width)
        XCTAssertEqual(movedPreview?.height, originalRaster.height)

        let movedMaskKey = maskKey.with(quality: .preview)
        let movedMaskPixels = await maskStore.pixels(for: RegionMaskReference(
            cacheKey: movedMaskKey, size: maskPixels.size, quality: .preview
        ))
        XCTAssertEqual(movedMaskPixels, maskPixels)

        for snapshot in movedSnapshots {
            let result = await editStore.load(
                for: sourceReference(snapshot, url: snapshot.url)
            )
            XCTAssertTrue(result.found, "missing moved edit for asset \(snapshot.asset.index)")
            XCTAssertEqual(result.document, snapshot.document)
            XCTAssertEqual(
                result.status, .ready,
                "portable UUID lookup should not require relink for asset \(snapshot.asset.index)"
            )
        }
    }

    func testDistinctSourcesDoNotCollideAndDuplicateDataImportsShareIdentity() throws {
        let duplicateBytes = Data("duplicate-import-content".utf8)
        let first = PhotoAssetSource(data: duplicateBytes)
        let duplicate = PhotoAssetSource(data: duplicateBytes)
        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(first.cacheIdentity, duplicate.cacheIdentity)

        // Keep the superficial shape identical while changing bytes outside the bounded sample
        // regions used by the legacy file fingerprint. The portable full-content hash must still
        // keep the sources distinct.
        let sampleSize = PhotoSourceFingerprint.sampleSize
        let middleSize = 4 * 1024
        let firstBytes = Data(repeating: 0x11, count: sampleSize + middleSize + sampleSize)
        var secondBytes = firstBytes
        secondBytes.replaceSubrange(
            sampleSize..<(sampleSize + middleSize),
            with: Data(repeating: 0x22, count: middleSize)
        )
        let firstURL = tempDirectory.appendingPathComponent("collision-a.jpg")
        let secondURL = tempDirectory.appendingPathComponent("collision-b.jpg")
        try firstBytes.write(to: firstURL)
        try secondBytes.write(to: secondURL)

        let firstFileFingerprint = PhotoSourceFingerprint.file(at: firstURL)
        let secondFileFingerprint = PhotoSourceFingerprint.file(at: secondURL)
        XCTAssertEqual(firstFileFingerprint.sampleDigest, secondFileFingerprint.sampleDigest)

        let firstIdentity = try identity(for: firstURL, index: 7_001)
        let secondIdentity = try identity(for: secondURL, index: 7_002)
        XCTAssertNotEqual(firstIdentity.sourceFingerprint.contentHash,
                          secondIdentity.sourceFingerprint.contentHash)
        XCTAssertNotEqual(firstIdentity, secondIdentity)
        XCTAssertFalse(firstIdentity.cacheKey.contains(firstURL.path))
        XCTAssertFalse(secondIdentity.cacheKey.contains(secondURL.path))
    }

    func testStaleMaskCompletionCannotPublishRenderOrThumbnailState() async throws {
        let sourceURL = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: "stale-mask.png", in: tempDirectory
        )
        let source = ImageSource(url: sourceURL, nativeExtent: CGSize(width: 64, height: 48))
        let document = semanticDocument()

        for quality in [RenderQuality.preview, .thumbnail] {
            let resolver = BlockingMaskResolver()
            let engine = RenderEngine(maskResolver: resolver)
            let firstRequest = RenderRequest(
                source: source,
                document: document,
                targetSize: CGSize(width: 32, height: 24),
                quality: quality,
                output: .raster,
                requestRevision: 1
            )
            let secondRequest = RenderRequest(
                source: source,
                document: document,
                targetSize: CGSize(width: 32, height: 24),
                quality: quality,
                output: .raster,
                requestRevision: 2
            )

            let staleTask = Task {
                if quality == .thumbnail {
                    return await engine.makeThumbnailCGImage(firstRequest)
                }
                return await engine.makeCGImage(firstRequest)
            }
            try await waitUntil("first mask resolution") { await resolver.callCount == 1 }

            let currentTask = Task {
                if quality == .thumbnail {
                    return await engine.makeThumbnailCGImage(secondRequest)
                }
                return await engine.makeCGImage(secondRequest)
            }
            try await waitUntil("replacement mask resolution") { await resolver.callCount == 2 }
            await resolver.releaseFirst()

            let staleImage = await staleTask.value
            let currentImage = await currentTask.value
            XCTAssertNil(staleImage, "stale \(quality.rawValue) pixels were published")
            XCTAssertNotNil(currentImage)
            let stats = await engine.cacheStatistics()
            XCTAssertEqual(stats.localMask.count, 1, "only the current mask may enter the cache")
        }
    }

    func testPreviewCompletionForRelocatedSourceCannotPublishOverCurrentSource() async throws {
        let originalURL = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "preview-before.png", in: tempDirectory
        )
        let movedURL = tempDirectory.appendingPathComponent("preview-after.png")
        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        let identity = try identity(for: movedURL, index: 9_001)
        let firstSource = ImageSource(
            url: originalURL, nativeExtent: CGSize(width: 20, height: 12), portableIdentity: identity
        )
        let currentSource = ImageSource(
            url: movedURL, nativeExtent: CGSize(width: 20, height: 12), portableIdentity: identity
        )
        let fake = LatePreviewRenderEngine()
        await fake.gate()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let assetID = PhotoAssetID.photos(localIdentifier: "identity-gate-asset")

        coordinator.submit(
            request(source: firstSource), assetID: assetID, sourceRevision: 1, displayRevision: 1
        )
        try await waitUntil("stale preview request") { await fake.requestCount == 1 }
        coordinator.submit(
            request(source: currentSource), assetID: assetID, sourceRevision: 2, displayRevision: 2
        )
        await fake.releaseNext()
        try await waitUntil("current preview request") { await fake.requestCount == 2 }
        XCTAssertTrue(publications.isEmpty)

        await fake.releaseNext()
        let publicationDeadline = ContinuousClock.now + .seconds(5)
        while publications.count != 1 {
            guard ContinuousClock.now < publicationDeadline else {
                XCTFail("timed out waiting for current preview publication")
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(publications.first?.assetID, assetID)
        XCTAssertEqual(publications.first?.sourceRevision, 2)
        XCTAssertEqual(publications.first?.request.source, currentSource)
        await coordinator.shutdown()
    }

    private struct Snapshot: Sendable {
        let asset: SyntheticLibraryGenerator.Asset
        let identity: PortablePhotoIdentity
        let document: EditDocument
        let url: URL

        init(
            asset: SyntheticLibraryGenerator.Asset,
            identity: PortablePhotoIdentity,
            document: EditDocument,
            url: URL? = nil
        ) {
            self.asset = asset
            self.identity = identity
            self.document = document
            self.url = url ?? asset.url
        }
    }

    private func identity(for url: URL, index: Int) throws -> PortablePhotoIdentity {
        let uuid = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
        return PortablePhotoIdentity(
            assetID: PortablePhotoAssetID(uuid: uuid),
            sourceFingerprint: try PortablePhotoSourceFingerprint.file(
                at: url,
                sourceRevision: 1,
                decoderVersion: "imageio-standard-v1",
                geometry: PhotoPixelDimensions(width: 64, height: 48)
            )
        )
    }

    private func sourceReference(_ snapshot: Snapshot, url: URL) -> EditSourceReference {
        EditSourceReference(
            assetID: .file(url), portableIdentity: snapshot.identity, url: url
        )
    }

    private func extent(for asset: SyntheticLibraryGenerator.Asset) -> CGSize {
        CGSize(width: asset.metadata.dimensions.width, height: asset.metadata.dimensions.height)
    }

    private func image(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "IdentityRegressionGateTests", code: 1)
        }
        return image
    }

    private func semanticDocument() -> EditDocument {
        EditDocument(localAdjustments: [
            LocalAdjustmentLayer(
                components: [MaskComponent(source: .semantic(SemanticMaskDefinition(
                    target: .subject, generationVersion: 1
                )))],
                adjustments: LocalAdjustments(exposure: 0.5)
            )
        ])
    }

    private func request(source: ImageSource) -> RenderRequest {
        RenderRequest(
            source: source,
            document: EditDocument(),
            targetSize: CGSize(width: 20, height: 12),
            quality: .preview,
            output: .raster
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while await condition() == false {
            guard ContinuousClock.now < deadline else {
                XCTFail("timed out waiting for \(description)")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private actor BlockingMaskResolver: LocalMaskResolving {
    private(set) var callCount = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        callCount += 1
        if callCount == 1 {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        let count = request.targetSize.width * request.targetSize.height
        let mask = try NormalizedMask(
            size: request.targetSize, values: Array(repeating: 1, count: count)
        )
        return LocalMaskPayload(
            sourceFingerprint: request.source.cacheFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            assetID: request.assetID,
            providerVersion: "identity-gate-mask-v1",
            descriptor: .raster(mask)
        )
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

private actor LatePreviewRenderEngine: RenderEngining {
    private(set) var requestCount = 0
    private var isGated = false
    private var waiters: [CheckedContinuation<CGImage?, Never>] = []

    func gate() { isGated = true }

    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        requestCount += 1
        if isGated {
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        return Self.image()
    }

    func releaseNext() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume(returning: Self.image())
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        RenderResult(
            data: Data(), extent: .zero, colorSpace: request.space,
            quality: request.quality, output: request.output
        )
    }

    func invalidateLUTCache() async {}

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) async -> HistogramData? { nil }

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }

    private static func image() -> CGImage? {
        try? Fixtures.makeCGImage(width: 2, height: 2)
    }
}
