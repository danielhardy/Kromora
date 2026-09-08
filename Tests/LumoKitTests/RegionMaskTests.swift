import Foundation
import XCTest

@testable import LumoKit

final class RegionMaskTests: XCTestCase {
    func testSemanticKindsAndQualityRoundTrip() throws {
        let kinds: [SemanticMaskKind] = [.subject, .background, .person, .face, .faceInstance(1), .foregroundInstance(2), .unknown("sky")]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(SemanticMaskKind.self, from: data), kind)
        }

        XCTAssertLessThan(MaskQuality.analysis, .preview)
        XCTAssertLessThan(MaskQuality.preview, .render)
    }

    func testRegionMaskCarriesReferenceInsteadOfPixels() throws {
        let source = PhotoSourceFingerprint.data(Data([1, 2, 3]))
        let asset = PhotoAssetID.data(Data([1, 2, 3]))
        let key = MaskCacheKey(
            assetID: asset, sourceFingerprint: source,
            kind: .subject, quality: .analysis, providerVersion: "vision-1"
        )
        let reference = RegionMaskReference(
            cacheKey: key, size: PixelDimensions(width: 8, height: 4)
        )
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6),
            quality: .analysis, reference: reference, confidence: 0.9, coverage: 0.3
        )

        let data = try JSONEncoder().encode(mask)
        XCTAssertEqual(try JSONDecoder().decode(RegionMask.self, from: data), mask)
        XCTAssertEqual(reference.cacheKey.quality, .analysis)
    }

    func testNormalizedMaskValidatesPixelPayload() throws {
        let size = PixelDimensions(width: 2, height: 2)
        let mask = try NormalizedMask(size: size, values: [0, 0.5, 1, 2])
        XCTAssertEqual(mask.values, [0, 0.5, 1, 1])
        XCTAssertEqual(mask.coverage, 0.625, accuracy: 0.0001)
        XCTAssertThrowsError(try NormalizedMask(size: size, values: [0, 1]))
        XCTAssertThrowsError(try NormalizedMask(size: size, values: [0, .nan, 1, 0]))
    }

    func testTrustedMaskCarriesGenerationCoverageAndKeepsCodableSchema() throws {
        let size = PixelDimensions(width: 2, height: 2)
        let mask = NormalizedMask(
            trustingSize: size, values: [0, 0.5, 1, 0], coverage: 0.375
        )

        XCTAssertEqual(mask.coverage, 0.375, accuracy: 0.0001)
        let decoded = try JSONDecoder().decode(
            NormalizedMask.self, from: JSONEncoder().encode(mask)
        )
        XCTAssertEqual(decoded, mask)
    }

    func testMaskStoreKeepsQualityLevelsIndependentAcrossReopen() async throws {
        let directory = try Fixtures.makeTempDirectory("MaskStoreTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let key = MaskCacheKey(
            assetID: .data(Data([4, 5, 6])), sourceFingerprint: .data(Data([4, 5, 6])),
            kind: .subject, providerVersion: "vision-1"
        )
        let pixels = try NormalizedMask(size: PixelDimensions(width: 2, height: 2), values: [0, 1, 0.5, 0.25])

        let analysis = try await store.store(pixels, for: key, quality: .analysis)
        let renderReference = await store.mask(for: key, quality: .render)
        let storedPixels = await store.pixels(for: analysis)
        XCTAssertNil(renderReference)
        XCTAssertEqual(storedPixels, pixels)

        let reopened = MaskStore(directory: directory)
        let reopenedPixels = await reopened.pixels(for: analysis)
        XCTAssertEqual(reopenedPixels, pixels)
    }

    func testMaskOperationsComposeAndRejectDifferentSizes() throws {
        let size = PixelDimensions(width: 2, height: 2)
        let left = try NormalizedMask(size: size, values: [1, 1, 0, 0])
        let right = try NormalizedMask(size: size, values: [1, 0, 1, 0])

        XCTAssertEqual(try MaskOperations.intersect(left, right).values, [1, 0, 0, 0])
        XCTAssertEqual(try MaskOperations.union(left, right).values, [1, 1, 1, 0])
        XCTAssertEqual(try MaskOperations.subtract(right, from: left).values, [0, 1, 0, 0])
        XCTAssertEqual(try MaskOperations.invert(left).values, [0, 0, 1, 1])
        XCTAssertThrowsError(try MaskOperations.intersect(
            left, try NormalizedMask(size: PixelDimensions(width: 1, height: 1), values: [1])
        ))
    }

    func testResizeInterpolatesAcrossSizesAndPreservesIdentity() throws {
        let source = try NormalizedMask(size: PixelDimensions(width: 2, height: 2), values: [0, 1, 0, 0])

        XCTAssertEqual(
            try MaskOperations.resized(source, to: source.size).values,
            source.values,
            "same-size resize must be the identity"
        )
        let upscaled = try MaskOperations.resized(
            source, to: PixelDimensions(width: 4, height: 4)
        )
        XCTAssertEqual(upscaled.size, PixelDimensions(width: 4, height: 4))
        // Corners reproduce the source samples; the interpolation stays in [0, 1].
        XCTAssertEqual(upscaled.values[0], 0)
        XCTAssertEqual(upscaled.values[3], 1, accuracy: 0.0001)
        XCTAssertEqual(upscaled.values[15], 0)
        XCTAssertGreaterThanOrEqual(upscaled.values.max() ?? 0, 0)
        XCTAssertLessThanOrEqual(upscaled.values.max() ?? 0, 1)
        XCTAssertEqual(
            upscaled.coverage,
            upscaled.values.reduce(0, +) / Float(upscaled.values.count),
            accuracy: 0.0001
        )

        // Asymmetric upscale distinguishes the row and column interpolation weights: with the
        // bottom-row lerp mistakenly using fy this interior sample reads 0.4167 instead of 0.5.
        let corners = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [0, 1, 1, 0]
        )
        let wide = try MaskOperations.resized(corners, to: PixelDimensions(width: 4, height: 3))
        XCTAssertEqual(wide.values[1 * 4 + 1], 0.5, accuracy: 0.0001)
        // vImage's default high-quality kernel is not bit-for-bit bilinear, but remains within
        // this stated tolerance on the existing asymmetric fixture while preserving the shape.
        let bilinearFixture = [
            0, 1.0 / 3, 2.0 / 3, 1,
            0.5, 0.5, 0.5, 0.5,
            1, 2.0 / 3, 1.0 / 3, 0,
        ]
        for (actual, expected) in zip(wide.values, bilinearFixture) {
            XCTAssertEqual(actual, Float(expected), accuracy: 0.2)
        }
    }

    func testResizeUsesClampToEdgeForSinglePixelDimensions() throws {
        let source = try NormalizedMask(
            size: PixelDimensions(width: 1, height: 1), values: [0.37]
        )

        let resized = try MaskOperations.resized(
            source, to: PixelDimensions(width: 3, height: 2)
        )

        XCTAssertEqual(resized.values.count, 6)
        for value in resized.values {
            XCTAssertEqual(value, 0.37, accuracy: 0.0001)
        }
    }

    func testMaskStoreRoundTripsPixelsThroughSidecar() async throws {
        let directory = try Fixtures.makeTempDirectory("MaskStoreSidecarTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let key = MaskCacheKey(
            assetID: .photos(localIdentifier: "sidecar"),
            sourceFingerprint: PhotoSourceFingerprint(
                byteCount: 8, modificationDate: nil,
                resourceIdentifier: "sidecar", sampleDigest: "digest"
            ),
            kind: .person, quality: .preview, providerVersion: "test-1"
        )
        let pixels = try NormalizedMask(
            size: PixelDimensions(width: 4, height: 3),
            values: (0..<12).map { Float($0) / 11 }
        )
        let reference = try await store.store(pixels, for: key, quality: .preview)

        // Existence must not require reading the pixels.
        let found = await store.mask(for: key, quality: .preview)
        XCTAssertEqual(found, reference)
        let loaded = await store.pixels(for: reference)
        XCTAssertEqual(loaded, pixels)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains(where: { $0.hasSuffix(".json") }))
        XCTAssertTrue(files.contains(where: { $0.hasSuffix(".bin") }))
        let metadata = try Data(contentsOf: directory.appendingPathComponent(
            files.first(where: { $0.hasSuffix(".json") })!
        ))
        let metadataObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: metadata) as? [String: Any]
        )
        let persistedMask = try XCTUnwrap(metadataObject["mask"] as? [String: Any])
        XCTAssertNil(persistedMask["values"], "pixel values must stay out of JSON metadata")
    }

    func testMaskStoreLoadsLegacyInlinePayloads() async throws {
        // Files written before the binary sidecar inline the floats in the JSON metadata.
        // Real user stores contain these at preview/analysis sizes, and the person gate
        // depends on reading them, so they must keep loading.
        struct LegacyFile: Codable {
            let key: MaskCacheKey
            let mask: NormalizedMask
        }
        let directory = try Fixtures.makeTempDirectory("MaskStoreLegacyTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = MaskCacheKey(
            assetID: .photos(localIdentifier: "legacy"),
            sourceFingerprint: PhotoSourceFingerprint(
                byteCount: 8, modificationDate: nil,
                resourceIdentifier: "legacy", sampleDigest: "digest"
            ),
            kind: .face, quality: .analysis, providerVersion: "vision-1"
        )
        let pixels = try NormalizedMask(
            size: PixelDimensions(width: 4, height: 3),
            values: (0..<12).map { Float($0) / 11 }
        )
        let exactKey = key.with(quality: .analysis)
        let data = try JSONEncoder().encode(LegacyFile(key: exactKey, mask: pixels))
        try data.write(to: directory.appendingPathComponent(
            MaskStore.filenameForTesting(for: exactKey)
        ))

        let store = MaskStore(directory: directory)
        let maybeReference = await store.mask(for: key, quality: .analysis)
        let reference = try XCTUnwrap(maybeReference)
        let loaded = await store.pixels(for: reference)
        XCTAssertEqual(loaded, pixels)
    }

    func testRefineReusesStoredRenderResult() async throws {
        // Without a render-cache check every photo open recomputed (and re-persisted) the
        // full-resolution mask — minutes on a 60MP source, i.e. a permanent spinner.
        let directory = try Fixtures.makeTempDirectory("MaskRefineCacheTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let service = MaskRefinementService(store: store)
        let key = MaskCacheKey(
            assetID: .photos(localIdentifier: "refine-cache"),
            sourceFingerprint: PhotoSourceFingerprint(
                byteCount: 8, modificationDate: nil,
                resourceIdentifier: "refine", sampleDigest: "digest"
            ),
            kind: .person, quality: .preview, providerVersion: "test-1"
        )
        let seedPixels = try NormalizedMask(
            size: PixelDimensions(width: 4, height: 4),
            values: (0..<16).map { $0 < 8 ? Float(1) : Float(0) }
        )
        let seedReference = try await store.store(seedPixels, for: key, quality: .preview)
        let seed = RegionMask(
            kind: .person,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: seedReference,
            confidence: 1,
            coverage: seedPixels.coverage
        )
        let targetSize = PixelDimensions(width: 8, height: 8)
        let refinedPixels = try NormalizedMask(
            size: targetSize, values: [Float](repeating: 0.5, count: 64)
        )
        let refinedReference = try await store.store(
            refinedPixels, for: key.with(kind: .person, quality: .render), quality: .render
        )
        let source = ImageSource(
            backing: .data(Data([1, 2])), kind: .standard,
            nativeExtent: CGSize(width: 8, height: 8)
        )
        let result = try await service.refine(
            mask: seed, source: source, targetDimensions: targetSize
        )
        XCTAssertEqual(result.quality, .render)
        XCTAssertEqual(result.reference, refinedReference)
        let resultPixels = await store.pixels(for: result.reference)
        XCTAssertEqual(resultPixels, refinedPixels)
    }

    func testRefineDoesNotReuseRenderResultAtAnotherTargetSize() async throws {
        let directory = try Fixtures.makeTempDirectory("MaskRefineSizeTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let service = MaskRefinementService(store: store)
        let key = MaskCacheKey(
            assetID: .photos(localIdentifier: "refine-size"),
            sourceFingerprint: PhotoSourceFingerprint(
                byteCount: 8, modificationDate: nil,
                resourceIdentifier: "refine-size", sampleDigest: "digest"
            ),
            kind: .subject, quality: .preview, providerVersion: "test-1"
        )
        let seedPixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [1, 0, 0, 1]
        )
        let seedReference = try await store.store(seedPixels, for: key, quality: .preview)
        let seed = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview, reference: seedReference, confidence: 1,
            coverage: seedPixels.coverage
        )
        let source = ImageSource(
            backing: .data(Data([1, 2])), kind: .standard,
            nativeExtent: CGSize(width: 4, height: 4)
        )
        let first = try await service.refine(
            mask: seed, source: source, targetDimensions: PixelDimensions(width: 4, height: 4)
        )
        let second = try await service.refine(
            mask: seed, source: source, targetDimensions: PixelDimensions(width: 8, height: 8)
        )

        XCTAssertEqual(first.reference.size, PixelDimensions(width: 4, height: 4))
        XCTAssertEqual(second.reference.size, PixelDimensions(width: 8, height: 8))
        XCTAssertNotEqual(first.reference, second.reference)
    }
}
