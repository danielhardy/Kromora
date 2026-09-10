import XCTest
import CoreGraphics
import CoreImage
@testable import KromoraKit

@MainActor
final class PreviewDiskCacheTests: TempDirectoryTestCase {
    private func image(width: Int = 320, height: Int = 240) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8((x * 255) / max(1, width - 1))
                pixels[i + 1] = UInt8((y * 255) / max(1, height - 1))
                pixels[i + 2] = 127
                pixels[i + 3] = 255
            }
        }
        return try XCTUnwrap(pixels.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        })
    }

    private func key(
        source: String = "source",
        document: String = "document",
        look: String = "look",
        bucket: String = "2048",
        space: WorkingSpace = .sRGB,
        version: Int = RenderPipeline.cacheVersion
    ) -> PreviewDiskCache.Key {
        PreviewDiskCache.Key(
            sourceFingerprint: source, documentHash: document, lookFingerprint: look,
            targetSizeBucket: bucket, space: space, pipelineVersion: version
        )
    }

    func testRoundTripUsesJPEGAndARealCIImageRaster() throws {
        let cacheDirectory = tempDirectory.appendingPathComponent("preview-cache")
        let cache = PreviewDiskCache(directory: cacheDirectory)
        let source = CIImage(cgImage: try image())
        let raster = try XCTUnwrap(
            PreviewDiskCache.canonicalRaster(from: source, space: .sRGB)
        )
        let cacheKey = key()
        cache.write(raster, for: cacheKey)

        let relaunched = PreviewDiskCache(directory: cacheDirectory)
        let decoded = try XCTUnwrap(relaunched.read(for: cacheKey))
        XCTAssertEqual(decoded.width, 2048)
        XCTAssertEqual(decoded.height, 1536)
        let lhs = try Pixels.bytes(of: raster)
        let rhs = try Pixels.bytes(of: decoded)
        let total = zip(lhs, rhs).reduce(0.0) { sum, pair in
            sum + abs(Double(pair.0) - Double(pair.1)) / 255.0
        }
        XCTAssertLessThan(total / Double(lhs.count), 3.0 / 255.0)
    }

    func testEveryKeyComponentIsASeparateMiss() throws {
        let directory = tempDirectory.appendingPathComponent("sensitivity-cache")
        let cache = PreviewDiskCache(directory: directory)
        let image = try image(width: 32, height: 24)
        let base = key()
        cache.write(image, for: base)

        let variants = [
            key(source: "source-bit-flip"), key(document: "document-bit-flip"),
            key(look: "look-bit-flip"), key(bucket: "1024"),
            key(space: .displayP3), key(version: RenderPipeline.cacheVersion + 1)
        ]
        for variant in variants {
            XCTAssertNil(cache.read(for: variant), "variant must not hit: \(variant)")
        }
        XCTAssertNotNil(cache.read(for: base))
    }

    func testVersionChangeWipesOldEntries() throws {
        let directory = tempDirectory.appendingPathComponent("version-cache")
        let old = PreviewDiskCache(directory: directory, pipelineVersion: 1)
        let oldKey = key(version: 1)
        old.write(try image(width: 64, height: 48), for: oldKey)
        XCTAssertNotNil(old.read(for: oldKey))

        let current = PreviewDiskCache(directory: directory, pipelineVersion: 2)
        XCTAssertNil(current.read(for: oldKey))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), ["version"])
    }

    func testCapEvictsOldestEntryAndKeepsNewest() throws {
        let directory = tempDirectory.appendingPathComponent("cap-cache")
        let uncapped = PreviewDiskCache(directory: directory)
        let firstKey = key(source: "first")
        let secondKey = key(source: "second")
        let image = try image(width: 256, height: 192)
        uncapped.write(image, for: firstKey)
        let jpg = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
                .first(where: { $0.pathExtension == "jpg" })
        )
        let firstSize = try XCTUnwrap(jpg.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: jpg.path
        )

        let capped = PreviewDiskCache(directory: directory, capBytes: Int64(firstSize) + 1)
        capped.write(image, for: secondKey)
        XCTAssertNil(capped.read(for: firstKey))
        XCTAssertNotNil(capped.read(for: secondKey))
        let total = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "jpg" }.reduce(Int64(0)) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        XCTAssertLessThanOrEqual(total, Int64(firstSize) + 1)
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
            engine: fake, previewDiskCacheDirectory: cacheDirectory
        )

        viewModel.openImage(data: data, name: "cache-hit.png")
        try await waitUntil("first preview") { viewModel.previewState == .ready }
        try await waitUntil("disk cache write") {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory, includingPropertiesForKeys: nil
            ) else { return false }
            return files.contains { $0.pathExtension == "jpg" }
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
}
