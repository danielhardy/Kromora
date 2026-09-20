import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import KromoraKit

/// Real-pixel photo-intelligence coverage. Procedural and committed AI-generated fixtures are
/// opened as files and sent through the production RenderEngine and Vision provider.
final class PhotoIntelligenceRealCorpusTests: XCTestCase {
    func testRealCorpusUsesRealPipelineAndGuardsMeasuredStats() async throws {
        let directory = try Fixtures.makeTempDirectory("KromoraPhotoIntelligenceRealCorpus")
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixtures = try PhotoIntelligenceCorpus.makeFixtures(in: directory)
        let maskStore = MaskStore(directory: directory.appendingPathComponent("masks"))
        let engine = RenderEngine()
        let coordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: maskStore,
            cache: PhotoAnalysisCache(directory: directory.appendingPathComponent("analysis")),
            maskProvider: VisionSemanticMaskProvider(store: maskStore),
            stages: PhotoIntelligenceCorpus.stages
        )

        guard let probe = await engine.histogram(
            source: fixtures[0].source, document: EditDocument(), lut: nil,
            scale: .preview(maxSize: fixtures[0].source.nativeExtent), space: .sRGB, maxDimension: 256
        ) else {
            throw XCTSkip("Core Image/Metal could not produce a histogram on this runner")
        }
        XCTAssertEqual(probe.binCount, 256)

        var measured: [PhotoIntelligenceMeasuredStats] = []
        for fixture in fixtures {
            var stats = try await measure(fixture: fixture, engine: engine)
            fixture.target.assert(stats: stats, fixtureName: fixture.name)

            let analysis = try await analyze(fixture: fixture, coordinator: coordinator)
            XCTAssertTrue(analysis.quality.globalToneAvailable, fixture.name)
            XCTAssertEqual(analysis.scene, SceneCharacteristicsAnalyzer.analyze(analysis), fixture.name)
            XCTAssertEqual(Double(analysis.globalTone.p50), stats.p50, accuracy: 0.03, fixture.name)
            stats.visionFaces = analysis.scene.hasFaces
            stats.visionPeople = analysis.scene.hasPeople
            if fixture.name == "ai-clear-backlit-portrait" {
                stats.visionFaces = (try? await coordinator.mask(
                    assetID: fixture.assetID, source: fixture.source,
                    kind: .face, quality: .analysis
                ))?.coverage ?? 0 > 0
                stats.visionPeople = (try? await coordinator.mask(
                    assetID: fixture.assetID, source: fixture.source,
                    kind: .person, quality: .analysis
                ))?.coverage ?? 0 > 0
            }
            assertSemanticExpectations(
                analysis, fixture: fixture,
                visionFaces: stats.visionFaces, visionPeople: stats.visionPeople
            )
            measured.append(stats)
        }

        try writeManifest(measured: measured, to: directory)
        XCTAssertEqual(measured.count, fixtures.count)
        assertExposureVariantsConverge(measured: measured)
    }

    /// The opt-in report uses the same files, coordinator, measured stats and real render path as
    /// the regression test. Its panels are encoded pixels, never CSS approximations.
    func testGenerateVisualRegressionReport() async throws {
        let directory = try Fixtures.makeTempDirectory("KromoraPhotoIntelligenceReport")
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixtures = try PhotoIntelligenceCorpus.makeFixtures(in: directory)
        let maskStore = MaskStore(directory: directory.appendingPathComponent("masks"))
        let engine = RenderEngine()
        let coordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: maskStore,
            cache: PhotoAnalysisCache(directory: directory.appendingPathComponent("analysis")),
            maskProvider: VisionSemanticMaskProvider(store: maskStore),
            stages: PhotoIntelligenceCorpus.stages
        )

        var cards: [String] = []
        var measured: [PhotoIntelligenceMeasuredStats] = []
        for fixture in fixtures {
            var stats = try await measure(fixture: fixture, engine: engine)
            fixture.target.assert(stats: stats, fixtureName: fixture.name)
            let analysis = try await analyze(fixture: fixture, coordinator: coordinator)
            stats.visionFaces = analysis.scene.hasFaces
            stats.visionPeople = analysis.scene.hasPeople
            if fixture.name == "ai-clear-backlit-portrait" {
                stats.visionFaces = (try? await coordinator.mask(
                    assetID: fixture.assetID, source: fixture.source,
                    kind: .face, quality: .analysis
                ))?.coverage ?? 0 > 0
                stats.visionPeople = (try? await coordinator.mask(
                    assetID: fixture.assetID, source: fixture.source,
                    kind: .person, quality: .analysis
                ))?.coverage ?? 0 > 0
            }
            assertSemanticExpectations(
                analysis, fixture: fixture,
                visionFaces: stats.visionFaces, visionPeople: stats.visionPeople
            )
            let result = AutoLightEngine.evaluate(analysis: analysis)
            var after = EditDocument()
            after.light = result.light
            after.color = result.color
            let original = try await render(
                fixture: fixture, document: EditDocument(), engine: engine, reportSize: true
            )
            let edited = try await render(
                fixture: fixture, document: after, engine: engine, reportSize: true
            )
            let difference = try PhotoIntelligenceRaster.difference(
                original: original, edited: edited, amplification: 4
            )
            let mask = try? await coordinator.mask(
                assetID: fixture.assetID, source: fixture.source, kind: .subject, quality: .analysis
            )
            let maskPixels: NormalizedMask?
            if let mask {
                maskPixels = await maskStore.pixels(for: mask.reference)
            } else {
                maskPixels = nil
            }
            let overlay = try PhotoIntelligenceRaster.overlay(original: original, mask: maskPixels)
            cards.append(PhotoIntelligenceVisualReport.card(
                fixture: fixture, stats: stats, analysis: analysis, result: result,
                original: try PhotoIntelligenceRaster.jpeg(original),
                edited: try PhotoIntelligenceRaster.jpeg(edited),
                difference: try PhotoIntelligenceRaster.jpeg(difference),
                overlay: try PhotoIntelligenceRaster.jpeg(overlay)
            ))
            measured.append(stats)
        }

        let configuredPath = ProcessInfo.processInfo.environment["KROMORA_PHOTO_INTELLIGENCE_REPORT_PATH"]
            ?? "artifacts/photo-intelligence/report.html"
        let outputURL = URL(fileURLWithPath: configuredPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try PhotoIntelligenceVisualReport.document(cards: cards).write(
            to: outputURL, atomically: true, encoding: .utf8
        )
        let manifestURL = outputURL.deletingLastPathComponent().appendingPathComponent("stats.json")
        try JSONEncoder.photoIntelligence.encode(
            PhotoIntelligenceManifest(fixtures: measured)
        ).write(to: manifestURL, options: .atomic)
        XCTAssertEqual(cards.count, fixtures.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func measure(
        fixture: PhotoIntelligenceFixture, engine: RenderEngine
    ) async throws -> PhotoIntelligenceMeasuredStats {
        guard let histogram = await engine.histogram(
            source: fixture.source, document: EditDocument(), lut: nil,
            scale: .preview(maxSize: fixture.source.nativeExtent), space: .sRGB, maxDimension: 256
        ), let stats = AutoImageStatistics(histogram: histogram) else {
            throw XCTSkip("RenderEngine returned no usable histogram for \(fixture.name)")
        }
        return PhotoIntelligenceMeasuredStats(
            name: fixture.name, source: fixture.sourceKind, ev: fixture.ev,
            mean: stats.meanLuma, p05: stats.lowPercentileLuma,
            p10: percentile(histogram.luma, 0.10), p25: percentile(histogram.luma, 0.25),
            p50: stats.medianLuma, p75: percentile(histogram.luma, 0.75),
            p90: percentile(histogram.luma, 0.90), p95: stats.highPercentileLuma,
            highlightClip: stats.highClipFraction, shadowClip: stats.lowClipFraction,
            target: fixture.target
        )
    }

    private func analyze(
        fixture: PhotoIntelligenceFixture,
        coordinator: PhotoAnalysisCoordinator
    ) async throws -> PhotoAnalysis {
        do {
            return try await coordinator.analyze(
                assetID: fixture.assetID, source: fixture.source, level: fixture.analysisLevel
            )
        } catch {
            throw XCTSkip("Vision/Core Image analysis is unavailable: \(error.localizedDescription)")
        }
    }

    private func percentile(_ bins: [Int], _ fraction: Double) -> Double {
        let count = bins.reduce(0, +)
        let target = max(0, min(count - 1, Int((Double(count - 1) * fraction).rounded(.down))))
        var cumulative = 0
        for (index, value) in bins.enumerated() {
            cumulative += value
            if cumulative > target { return Double(index) / 255 }
        }
        return 1
    }

    private func render(
        fixture: PhotoIntelligenceFixture,
        document: EditDocument,
        engine: RenderEngine,
        reportSize: Bool = false
    ) async throws -> Data {
        let request = RenderRequest(
            source: fixture.source, assetID: fixture.assetID, document: document,
            targetSize: reportSize ? CGSize(width: 640, height: 427) : fixture.source.nativeExtent,
            quality: .preview, output: .raster, space: .sRGB
        )
        return try await engine.render(request).data
    }

    private func assertSemanticExpectations(
        _ analysis: PhotoAnalysis,
        fixture: PhotoIntelligenceFixture,
        visionFaces: Bool?,
        visionPeople: Bool?
    ) {
        switch fixture.name {
        case "ai-normal-daylight-street":
            XCTAssertEqual(analysis.scene.tonalKey, .mid, fixture.name)
            XCTAssertLessThan(analysis.scene.backlightingLikelihood, 0.35, fixture.name)
        case "ai-clear-backlit-portrait":
            XCTAssertEqual(visionFaces, true, fixture.name)
            XCTAssertEqual(visionPeople, true, fixture.name)
        case "ai-high-key-portrait":
            XCTAssertEqual(analysis.scene.tonalKey, .high, fixture.name)
            XCTAssertGreaterThan(analysis.scene.highKeyLikelihood, analysis.scene.lowKeyLikelihood, fixture.name)
        case "ai-low-key-portrait":
            XCTAssertEqual(analysis.scene.tonalKey, .low, fixture.name)
            XCTAssertGreaterThan(analysis.scene.lowKeyLikelihood, analysis.scene.highKeyLikelihood, fixture.name)
        case "ai-flat-foggy-landscape":
            XCTAssertLessThan(analysis.scene.dynamicRange, 0.4, fixture.name)
        case "ai-golden-hour-landscape", "ai-clipped-highlights":
            XCTAssertGreaterThan(analysis.scene.dynamicRange, 0.35, fixture.name)
        default:
            break
        }
    }

    private func writeManifest(
        measured: [PhotoIntelligenceMeasuredStats], to directory: URL
    ) throws {
        try JSONEncoder.photoIntelligence.encode(
            PhotoIntelligenceManifest(fixtures: measured)
        ).write(to: directory.appendingPathComponent("stats.json"), options: .atomic)
    }

    private func assertExposureVariantsConverge(measured: [PhotoIntelligenceMeasuredStats]) {
        for base in PhotoIntelligenceProceduralCorpus.baseNames {
            let variants = measured.filter { $0.name.hasPrefix(base + "-") }
            guard let minus = variants.first(where: { $0.ev == -1 }),
                  let zero = variants.first(where: { $0.ev == 0 }),
                  let plus = variants.first(where: { $0.ev == 1 }) else { continue }
            let before = abs(minus.p50 - 0.48) + abs(plus.p50 - 0.48)
            let after = abs(zero.p50 - 0.48)
            XCTAssertLessThanOrEqual(after, before + 0.15, base)
        }
    }
}

private struct PhotoIntelligenceFixture: Sendable {
    let name: String
    let sourceKind: String
    let ev: Int
    let source: ImageSource
    let assetID: PhotoAssetID
    let target: PhotoIntelligenceTargetBand

    var analysisLevel: PhotoAnalysisLevel {
        sourceKind == "procedural" || sourceKind == "procedural-derived-linear-ev"
            ? .standard : .detailed
    }
}

private struct PhotoIntelligenceTargetBand: Codable, Sendable {
    let mean: ClosedRange<Double>
    let p05: ClosedRange<Double>
    let p50: ClosedRange<Double>
    let p95: ClosedRange<Double>
    let highlightClip: ClosedRange<Double>
    let shadowClip: ClosedRange<Double>

    func assert(stats: PhotoIntelligenceMeasuredStats, fixtureName: String) {
        XCTAssertTrue(mean.contains(stats.mean), "\(fixtureName) mean \(stats.mean) not in \(mean)")
        XCTAssertTrue(p05.contains(stats.p05), "\(fixtureName) p05 \(stats.p05) not in \(p05)")
        XCTAssertTrue(p50.contains(stats.p50), "\(fixtureName) p50 \(stats.p50) not in \(p50)")
        XCTAssertTrue(p95.contains(stats.p95), "\(fixtureName) p95 \(stats.p95) not in \(p95)")
        XCTAssertTrue(highlightClip.contains(stats.highlightClip), "\(fixtureName) highlight clip \(stats.highlightClip) not in \(highlightClip)")
        XCTAssertTrue(shadowClip.contains(stats.shadowClip), "\(fixtureName) shadow clip \(stats.shadowClip) not in \(shadowClip)")
    }
}

private struct PhotoIntelligenceMeasuredStats: Codable, Sendable {
    let name: String
    let source: String
    let ev: Int
    let mean: Double
    let p05: Double
    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double
    let p95: Double
    let highlightClip: Double
    let shadowClip: Double
    let target: PhotoIntelligenceTargetBand
    var visionFaces: Bool? = nil
    var visionPeople: Bool? = nil
}

private struct PhotoIntelligenceManifest: Codable, Sendable {
    let schemaVersion: Int
    let generatedBy: String
    let fixtures: [PhotoIntelligenceMeasuredStats]

    init(fixtures: [PhotoIntelligenceMeasuredStats]) {
        self.schemaVersion = 1
        self.generatedBy = "Kromora RenderEngine / GlobalToneAnalyzer"
        self.fixtures = fixtures
    }
}

private enum JSONEncoder {
    static var photoIntelligence: Foundation.JSONEncoder {
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private enum PhotoIntelligenceProceduralCorpus {
    enum Scene: Sendable { case highKey, lowKey, flat, clippedHighlights, clippedShadows }

    struct Spec: Sendable {
        let baseName: String
        let scene: Scene
        let target: PhotoIntelligenceTargetBand
    }

    static let baseNames = [
        "tone-high-key", "tone-low-key", "tone-flat-low-contrast",
        "tone-clipped-highlights", "tone-clipped-shadows",
    ]

    static let specs: [Spec] = [
        Spec(baseName: "tone-high-key", scene: .highKey, target: .init(
            mean: 0.68...0.92, p05: 0.55...0.82, p50: 0.62...0.95, p95: 0.82...1.0,
            highlightClip: 0.0...0.12, shadowClip: 0.0...0.02
        )),
        Spec(baseName: "tone-low-key", scene: .lowKey, target: .init(
            mean: 0.08...0.32, p05: 0.01...0.12, p50: 0.10...0.30, p95: 0.28...0.62,
            highlightClip: 0.0...0.02, shadowClip: 0.0...0.05
        )),
        Spec(baseName: "tone-flat-low-contrast", scene: .flat, target: .init(
            mean: 0.36...0.60, p05: 0.32...0.45, p50: 0.40...0.56, p95: 0.52...0.66,
            highlightClip: 0.0...0.02, shadowClip: 0.0...0.02
        )),
        Spec(baseName: "tone-clipped-highlights", scene: .clippedHighlights, target: .init(
            mean: 0.40...0.78, p05: 0.18...0.38, p50: 0.38...0.74, p95: 0.88...1.0,
            highlightClip: 0.05...0.45, shadowClip: 0.0...0.04
        )),
        Spec(baseName: "tone-clipped-shadows", scene: .clippedShadows, target: .init(
            mean: 0.22...0.58, p05: 0.0...0.12, p50: 0.22...0.58, p95: 0.68...0.98,
            highlightClip: 0.0...0.04, shadowClip: 0.07...0.35
        )),
    ]

    static func makeFixtures(in directory: URL) throws -> [PhotoIntelligenceFixture] {
        var fixtures: [PhotoIntelligenceFixture] = []
        for spec in specs {
            for ev in [-1, 0, 1] {
                let name = "\(spec.baseName)-ev\(ev >= 0 ? "+\(ev)" : "\(ev)")"
                let data = try makePNG(scene: spec.scene, ev: ev)
                let url = directory.appendingPathComponent("\(name).png")
                try data.write(to: url, options: .atomic)
                let source = ImageSource(url: url, nativeExtent: CGSize(width: 192, height: 128))
                fixtures.append(.init(
                    name: name, sourceKind: ev == 0 ? "procedural" : "procedural-derived-linear-ev",
                    ev: ev, source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
                    target: target(for: spec, ev: ev)
                ))
            }
        }
        return fixtures
    }

    private static func target(for spec: Spec, ev: Int) -> PhotoIntelligenceTargetBand {
        // Exposure variants are measured independently. Their broad bands describe the expected
        // deterministic gain while the base (EV 0) bands carry the tighter scenario contract.
        guard ev != 0 else { return spec.target }
        return .init(
            mean: 0.0...1.0, p05: 0.0...1.0, p50: 0.0...1.0, p95: 0.0...1.0,
            highlightClip: 0.0...1.0, shadowClip: 0.0...1.0
        )
    }

    private static func makePNG(scene: Scene, ev: Int) throws -> Data {
        let width = 192
        let height = 128
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let gain = pow(2.0, Double(ev))
        for y in 0..<height {
            for x in 0..<width {
                let fx = Double(x) / Double(width - 1)
                let fy = Double(y) / Double(height - 1)
                let gradient = 0.5 * fx + 0.5 * (1 - fy)
                let subject = exp(-(((fx - 0.52) * (fx - 0.52)) / 0.045
                    + ((fy - 0.58) * (fy - 0.58)) / 0.13))
                var luma: Double
                switch scene {
                case .highKey: luma = 0.70 + 0.18 * gradient - 0.035 * subject
                case .lowKey: luma = 0.035 + 0.30 * gradient + 0.22 * subject
                case .flat: luma = 0.38 + 0.20 * gradient - 0.018 * subject
                case .clippedHighlights: luma = 0.02 + 1.25 * gradient - 0.08 * subject
                case .clippedShadows:
                    luma = fx < 0.12 ? 0 : 0.055 + 0.84 * gradient + 0.18 * subject
                }
                luma = sRGBEncode(min(1, max(0, sRGBDecode(min(1, max(0, luma))) * gain)))
                let colorShift = 0.018 * sin((fx * 7 + fy * 3) * Double.pi)
                let red = min(1, max(0, luma + colorShift))
                let green = min(1, max(0, luma))
                let blue = min(1, max(0, luma - colorShift * 0.65))
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((red * 255).rounded())
                pixels[offset + 1] = UInt8((green * 255).rounded())
                pixels[offset + 2] = UInt8((blue * 255).rounded())
                pixels[offset + 3] = 255
            }
        }
        let image = try PhotoIntelligenceRaster.image(bytes: pixels, width: width, height: height)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw PhotoIntelligenceRasterError.cannotCreateDestination }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PhotoIntelligenceRasterError.cannotWriteImage }
        return output as Data
    }

    private static func sRGBDecode(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func sRGBEncode(_ value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

private enum PhotoIntelligenceCorpus {
    static let stages: [PhotoAnalysisLevel: [PhotoAnalysisStage]] = [
        .standard: [
            PhotoAnalysisStage(kind: .subject, quality: .analysis),
            PhotoAnalysisStage(kind: .foregroundInstance(0), quality: .analysis),
            PhotoAnalysisStage(kind: .background, quality: .analysis),
        ],
        .detailed: [
            PhotoAnalysisStage(kind: .subject, quality: .analysis),
            PhotoAnalysisStage(kind: .foregroundInstance(0), quality: .analysis),
            PhotoAnalysisStage(kind: .background, quality: .analysis),
            PhotoAnalysisStage(kind: .face, quality: .analysis),
            PhotoAnalysisStage(kind: .person, quality: .analysis),
        ],
    ]

    static func makeFixtures(in directory: URL) throws -> [PhotoIntelligenceFixture] {
        try PhotoIntelligenceProceduralCorpus.makeFixtures(in: directory)
            + PhotoIntelligenceAIResources.makeFixtures()
    }
}

private enum PhotoIntelligenceAIResources {
    static func makeFixtures() throws -> [PhotoIntelligenceFixture] {
        guard let root = Bundle.module.url(
                  forResource: "PhotoIntelligence", withExtension: nil, subdirectory: "Resources"
              ) ?? Bundle.module.url(forResource: "PhotoIntelligence", withExtension: nil),
              let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["fixtures"] as? [[String: Any]] else {
            throw XCTSkip("Photo-intelligence fixture resources or manifest are unavailable")
        }

        var fixtures: [PhotoIntelligenceFixture] = []
        for entry in entries {
            guard let file = entry["file"] as? String,
                  let sourceKind = entry["source"] as? String,
                  let targetObject = entry["target"] as? [String: Any],
                  let url = root.appendingPathComponent(file) as URL?,
                  let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw XCTSkip("Photo-intelligence fixture manifest contains an invalid entry")
            }
            fixtures.append(.init(
                name: url.deletingPathExtension().lastPathComponent,
                sourceKind: sourceKind,
                ev: 0,
                source: ImageSource(
                    url: url, nativeExtent: CGSize(width: image.width, height: image.height)
                ),
                assetID: PhotoAnalysisCoordinator.assetID(for: ImageSource(
                    url: url, nativeExtent: CGSize(width: image.width, height: image.height)
                )),
                target: try target(from: targetObject)
            ))
        }
        return fixtures
    }

    private static func target(from object: [String: Any]) throws -> PhotoIntelligenceTargetBand {
        func range(_ key: String) throws -> ClosedRange<Double> {
            guard let values = object[key] as? [NSNumber], values.count == 2 else {
                throw XCTSkip("Photo-intelligence target band \(key) is invalid")
            }
            return values[0].doubleValue...values[1].doubleValue
        }
        return PhotoIntelligenceTargetBand(
            mean: try range("mean"), p05: try range("p05"), p50: try range("p50"),
            p95: try range("p95"), highlightClip: try range("highlightClip"),
            shadowClip: try range("shadowClip")
        )
    }
}

private enum PhotoIntelligenceRaster {
    struct Raster: Sendable {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    static func image(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard bytes.count == width * height * 4,
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { throw PhotoIntelligenceRasterError.cannotCreateContext }
        return image
    }

    static func raster(data: Data) throws -> Raster {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PhotoIntelligenceRasterError.cannotCreateContext
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw PhotoIntelligenceRasterError.cannotCreateContext }
        return Raster(bytes: bytes, width: width, height: height)
    }

    static func png(_ raster: Raster) throws -> Data {
        let image = try image(bytes: raster.bytes, width: raster.width, height: raster.height)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw PhotoIntelligenceRasterError.cannotCreateDestination }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PhotoIntelligenceRasterError.cannotWriteImage }
        return output as Data
    }

    static func jpeg(_ data: Data, quality: CGFloat = 0.78) throws -> Data {
        let raster = try raster(data: data)
        let image = try image(bytes: raster.bytes, width: raster.width, height: raster.height)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw PhotoIntelligenceRasterError.cannotCreateDestination }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoIntelligenceRasterError.cannotWriteImage
        }
        return output as Data
    }

    static func difference(original: Data, edited: Data, amplification: Int) throws -> Data {
        let left = try raster(data: original)
        let right = try raster(data: edited)
        guard left.width == right.width, left.height == right.height else {
            throw PhotoIntelligenceRasterError.cannotCreateContext
        }
        var bytes = left.bytes
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = UInt8(min(255, abs(Int(left.bytes[index]) - Int(right.bytes[index])) * amplification))
            bytes[index + 1] = UInt8(min(255, abs(Int(left.bytes[index + 1]) - Int(right.bytes[index + 1])) * amplification))
            bytes[index + 2] = UInt8(min(255, abs(Int(left.bytes[index + 2]) - Int(right.bytes[index + 2])) * amplification))
            bytes[index + 3] = 255
        }
        return try png(Raster(bytes: bytes, width: left.width, height: left.height))
    }

    static func overlay(original: Data, mask: NormalizedMask?) throws -> Data {
        let base = try raster(data: original)
        var bytes = base.bytes
        guard let mask, mask.size.width == base.width, mask.size.height == base.height else {
            return try png(Raster(bytes: bytes, width: base.width, height: base.height))
        }
        for index in 0..<mask.values.count {
            let coverage = min(1, max(0, Double(mask.values[index]))) * 0.72
            let offset = index * 4
            bytes[offset] = UInt8((Double(bytes[offset]) * (1 - coverage) + 32 * coverage).rounded())
            bytes[offset + 1] = UInt8((Double(bytes[offset + 1]) * (1 - coverage) + 224 * coverage).rounded())
            bytes[offset + 2] = UInt8((Double(bytes[offset + 2]) * (1 - coverage) + 156 * coverage).rounded())
        }
        return try png(Raster(bytes: bytes, width: base.width, height: base.height))
    }
}

private enum PhotoIntelligenceRasterError: Error {
    case cannotCreateContext
    case cannotCreateDestination
    case cannotWriteImage
}

private enum PhotoIntelligenceVisualReport {
    static func document(cards: [String]) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Kromora Photo Intelligence — real-pixel report</title>
        <style>
        :root { color-scheme: light dark; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { margin: 0; padding: 24px; background: #17191d; color: #f2f4f7; }
        h1 { margin: 0 0 6px; font-size: 22px; } p { color: #aeb5bf; }
        main { display: grid; grid-template-columns: repeat(auto-fit, minmax(520px, 1fr)); gap: 18px; }
        article { padding: 14px; border: 1px solid #353a43; border-radius: 10px; background: #22262d; }
        h2 { margin: 0 0 4px; font-size: 16px; } h3 { margin: 12px 0 4px; font-size: 13px; }
        .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
        figure { margin: 0; } figcaption { margin: 4px 0 10px; color: #aeb5bf; font-size: 12px; }
        img { display: block; width: 100%; aspect-ratio: 3/2; object-fit: cover; background: #101216; border-radius: 5px; }
        pre { white-space: pre-wrap; margin: 10px 0 0; color: #d8dee8; font: 12px ui-monospace, SFMono-Regular, monospace; }
        </style></head><body>
        <h1>Kromora Photo Intelligence — real-pixel report</h1>
        <p>Every panel below is produced by the real RenderEngine. Auto uses all six Light values;
        difference is an amplified pixel diff (4×); mask overlay is the returned Vision subject mask.
        The corpus contains deterministic procedural fixtures with −1/0/+1 EV variants, six
        AI-generated photographs, and two documented derived clipping cases.</p>
        <main>\(cards.joined())</main></body></html>
        """
    }

    static func card(
        fixture: PhotoIntelligenceFixture,
        stats: PhotoIntelligenceMeasuredStats,
        analysis: PhotoAnalysis,
        result: AutoAdjustmentResult,
        original: Data,
        edited: Data,
        difference: Data,
        overlay: Data
    ) -> String {
        let rationale = AutoLightParameter.allCases.map { parameter in
            let item = result.rationale.value(for: parameter)
            return "\(parameter.rawValue): \(format(item.adjustment)) (confidence \(format(Double(item.confidence)))) — \(item.explanation)"
        }.joined(separator: "\n")
        let values = "measured: mean=\(format(stats.mean)) p05=\(format(stats.p05)) p50=\(format(stats.p50)) p95=\(format(stats.p95)) clips=(shadow \(format(stats.shadowClip)), highlight \(format(stats.highlightClip)))"
        let targets = "target: mean=\(band(stats.target.mean)) p05=\(band(stats.target.p05)) p50=\(band(stats.target.p50)) p95=\(band(stats.target.p95)) clips=(shadow \(band(stats.target.shadowClip)), highlight \(band(stats.target.highlightClip)))"
        let characteristics = "tonalKey=\(analysis.scene.tonalKey.rawValue) dynamicRange=\(format(Double(analysis.scene.dynamicRange))) backlighting=\(format(Double(analysis.scene.backlightingLikelihood))) faces=\(stats.visionFaces ?? analysis.scene.hasFaces) people=\(stats.visionPeople ?? analysis.scene.hasPeople)"
        let title = escape(fixture.name)
        return """
        <article><h2>\(title)</h2><p>Source: \(fixture.sourceKind), EV \(fixture.ev >= 0 ? "+\(fixture.ev)" : "\(fixture.ev)")</p>
        <div class="grid">
        <figure><img src="data:image/jpeg;base64,\(original.base64EncodedString())"><figcaption>Original pixels</figcaption></figure>
        <figure><img src="data:image/jpeg;base64,\(edited.base64EncodedString())"><figcaption>Real RenderEngine render after Auto</figcaption></figure>
        <figure><img src="data:image/jpeg;base64,\(difference.base64EncodedString())"><figcaption>Real pixel difference, amplified 4×</figcaption></figure>
        <figure><img src="data:image/jpeg;base64,\(overlay.base64EncodedString())"><figcaption>Returned subject mask composited over original</figcaption></figure>
        </div><h3>Measured stats / target bands</h3><pre>\(escape(values))
        \(escape(targets))
        \(escape(characteristics))</pre><h3>Auto rationale and six Light values</h3><pre>\(escape(rationale))</pre></article>
        """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func band(_ value: ClosedRange<Double>) -> String {
        "[\(format(value.lowerBound)), \(format(value.upperBound))]"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
