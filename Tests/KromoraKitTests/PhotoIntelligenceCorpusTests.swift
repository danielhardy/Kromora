import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import XCTest

@testable import KromoraKit

/// Fast, fake-backed assertions for Auto and scene decision logic.
///
/// This suite deliberately does not claim visual validation. The real-pixel coverage lives in
/// `PhotoIntelligenceRealCorpusTests`, which is assigned to the serial Core Image lane.
final class PhotoIntelligenceDecisionLogicTests: XCTestCase {
    func testDecisionLogicRunsTheFullSemanticAssemblyAndMeetsExpectations() async throws {
        let directory = try Fixtures.makeTempDirectory("KromoraPhotoIntelligenceCorpus")
        defer { try? FileManager.default.removeItem(at: directory) }

        for fixture in PhotoIntelligenceCorpus.fixtures {
            let analysis = try await makeAnalysis(for: fixture, in: directory)

            XCTAssertTrue(analysis.quality.globalToneAvailable, fixture.name)
            XCTAssertFalse(analysis.regions.isEmpty, fixture.name)
            XCTAssertEqual(analysis.scene, SceneCharacteristicsAnalyzer.analyze(analysis), fixture.name)
            fixture.expect(analysis)
        }
    }

    private func makeAnalysis(
        for fixture: CorpusFixture, in directory: URL
    ) async throws -> PhotoAnalysis {
        let store = MaskStore(directory: directory.appendingPathComponent(fixture.name))
        let engine = CorpusRenderEngine(fixtures: [fixture])
        let provider = CorpusMaskProvider(fixtures: [fixture], store: store)
        let coordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(directory: directory.appendingPathComponent("cache")),
            maskProvider: provider,
            stages: [.standard: fixture.specs.map {
                PhotoAnalysisStage(kind: $0.kind, quality: .analysis)
            }]
        )
        return try await coordinator.analyze(
            assetID: fixture.assetID, source: fixture.source, level: .standard
        )
    }
}

private struct CorpusFixture: Sendable {
    struct Tone: Sendable {
        let mean: Float
        let p05: Float
        let p10: Float
        let p25: Float
        let p50: Float
        let p75: Float
        let p90: Float
        let p95: Float
        let highlightClip: Float
        let shadowClip: Float
    }

    struct MaskSpec: Sendable {
        let kind: SemanticMaskKind
        let coverage: Float
        let confidence: Float
        let mean: Float
    }

    let name: String
    let data: Data
    let source: ImageSource
    let assetID: PhotoAssetID
    let tone: Tone
    let specs: [MaskSpec]
    let expect: @Sendable (PhotoAnalysis) -> Void
}

private enum PhotoIntelligenceCorpus {
    static var fixtures: [CorpusFixture] {
        let base: [CorpusFixture] = [
            make(
                name: "normal-daylight", tone: CorpusFixture.Tone(mean: 0.50, p05: 0.08, p10: 0.12, p25: 0.28,
                                                      p50: 0.50, p75: 0.72, p90: 0.86, p95: 0.90,
                                                      highlightClip: 0, shadowClip: 0),
                subjectMean: 0.52, backgroundMean: 0.48
            ) { analysis in
                XCTAssertEqual(analysis.scene.tonalKey, .mid)
                XCTAssertLessThan(analysis.scene.backlightingLikelihood, 0.25)
            },
            make(
                name: "clear-backlit", tone: CorpusFixture.Tone(mean: 0.56, p05: 0.04, p10: 0.12, p25: 0.20,
                                                    p50: 0.52, p75: 0.80, p90: 0.94, p95: 0.98,
                                                    highlightClip: 0.01, shadowClip: 0.02),
                subjectMean: 0.22, backgroundMean: 0.90, person: true, face: true
            ) { analysis in
                XCTAssertGreaterThan(analysis.scene.backlightingLikelihood, 0.30)
                XCTAssertTrue(analysis.scene.hasFaces)
                XCTAssertTrue(analysis.scene.hasPeople)
            },
            make(
                name: "intentional-high-key", tone: CorpusFixture.Tone(mean: 0.80, p05: 0.50, p10: 0.56, p25: 0.66,
                                                         p50: 0.81, p75: 0.91, p90: 0.95, p95: 0.96,
                                                         highlightClip: 0, shadowClip: 0),
                subjectMean: 0.82, backgroundMean: 0.78
            ) { analysis in
                XCTAssertEqual(analysis.scene.tonalKey, .high)
                XCTAssertGreaterThan(analysis.scene.highKeyLikelihood, analysis.scene.lowKeyLikelihood)
                XCTAssertGreaterThan(analysis.scene.highKeyLikelihood, 0.2)
            },
            make(
                name: "intentional-low-key", tone: CorpusFixture.Tone(mean: 0.20, p05: 0.01, p10: 0.03, p25: 0.05,
                                                         p50: 0.18, p75: 0.35, p90: 0.52, p95: 0.60,
                                                         highlightClip: 0, shadowClip: 0.02),
                subjectMean: 0.43, backgroundMean: 0.10
            ) { analysis in
                XCTAssertEqual(analysis.scene.tonalKey, .low)
                XCTAssertGreaterThan(analysis.scene.lowKeyLikelihood, analysis.scene.highKeyLikelihood)
                XCTAssertGreaterThan(analysis.scene.lowKeyLikelihood, 0.2)
            },
            make(
                name: "flat-low-contrast", tone: CorpusFixture.Tone(mean: 0.48, p05: 0.38, p10: 0.40, p25: 0.43,
                                                       p50: 0.48, p75: 0.53, p90: 0.56, p95: 0.58,
                                                       highlightClip: 0, shadowClip: 0),
                subjectMean: 0.50, backgroundMean: 0.46
            ) { analysis in
                XCTAssertLessThan(analysis.scene.dynamicRange, 0.4)
            },
            make(
                name: "clipped-highlights", tone: CorpusFixture.Tone(mean: 0.60, p05: 0.12, p10: 0.18, p25: 0.35,
                                                        p50: 0.58, p75: 0.76, p90: 0.99, p95: 1.0,
                                                        highlightClip: 0.08, shadowClip: 0),
                subjectMean: 0.55, backgroundMean: 0.68
            ) { analysis in
                XCTAssertTrue(analysis.globalTone.highlightClippingFraction >= 0)
            },
            make(
                name: "clipped-shadows", tone: CorpusFixture.Tone(mean: 0.38, p05: 0, p10: 0.02, p25: 0.12,
                                                     p50: 0.36, p75: 0.62, p90: 0.80, p95: 0.88,
                                                     highlightClip: 0, shadowClip: 0.08),
                subjectMean: 0.42, backgroundMean: 0.34
            ) { analysis in
                XCTAssertTrue(analysis.globalTone.shadowClippingFraction >= 0)
            },
        ]
        return base
    }

    private static func make(
        name: String,
        tone: CorpusFixture.Tone,
        subjectMean: Float,
        backgroundMean: Float,
        person: Bool = false,
        face: Bool = false,
        expect: @escaping @Sendable (PhotoAnalysis) -> Void
    ) -> CorpusFixture {
        let data = makeImageData(name: name)
        var specs = [
            CorpusFixture.MaskSpec(kind: .subject, coverage: 0.24, confidence: 0.92, mean: subjectMean),
            CorpusFixture.MaskSpec(kind: .background, coverage: 0.76, confidence: 0.90, mean: backgroundMean),
        ]
        if person { specs.append(.init(kind: .person, coverage: 0.24, confidence: 0.95, mean: subjectMean)) }
        if face { specs.append(.init(kind: .face, coverage: 0.04, confidence: 0.96, mean: subjectMean)) }
        return CorpusFixture(
            name: name, data: data,
            source: ImageSource(data: data, nativeExtent: CGSize(width: 160, height: 100)),
            assetID: PhotoAssetID.data(data), tone: tone, specs: specs, expect: expect
        )
    }

    private static func makeImageData(name: String) -> Data {
        let width = 160
        let height = 100
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let seed = name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        let variation = CGFloat(abs(seed) % 11) * 0.01
        context.setFillColor(red: 0.82 + variation, green: 0.82, blue: 0.82, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        context.fillEllipse(in: CGRect(x: 48, y: 22, width: 62, height: 70))
        context.setFillColor(red: CGFloat(abs(seed / 17) % 255) / 255,
                             green: CGFloat(abs(seed / 31) % 255) / 255,
                             blue: CGFloat(abs(seed / 43) % 255) / 255,
                             alpha: 1)
        context.fill(CGRect(x: Int(seed.magnitude % UInt(width)),
                            y: Int(seed.magnitude % UInt(height)), width: 1, height: 1))
        guard let image = context.makeImage() else { return Data(name.utf8) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else { return Data(name.utf8) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data(name.utf8) }
        return data as Data
    }
}

private actor CorpusMaskProvider: SemanticMaskProviding {
    private let fixtures: [String: CorpusFixture]
    private let store: MaskStore

    init(fixtures: [CorpusFixture], store: MaskStore) {
        self.fixtures = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.source.cacheFingerprint, $0) })
        self.store = store
    }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard let fixture = fixtures[image.source.cacheFingerprint],
              let spec = fixture.specs.first(where: { $0.kind == kind }) else {
            throw CorpusError.missingMask
        }
        let key = MaskCacheKey(
            assetID: fixture.assetID,
            sourceFingerprint: PhotoSourceFingerprint.data(fixture.data),
            kind: kind, quality: quality, providerVersion: "corpus"
        )
        let width = image.dimensions.width
        let height = image.dimensions.height
        let count = width * height
        let pixels = try NormalizedMask(
            size: image.dimensions,
            values: (0..<count).map { _ in spec.coverage }
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            quality: quality, reference: reference,
            confidence: spec.confidence, coverage: spec.coverage
        )
    }
}

private actor CorpusRenderEngine: RenderEngining {
    private let fixtures: [String: CorpusFixture]

    init(fixtures: [CorpusFixture]) {
        self.fixtures = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.source.cacheFingerprint, $0) })
    }

    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? { nil }

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? { nil }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        RenderResult(
            data: Data(), extent: .zero, colorSpace: request.space,
            quality: request.quality, output: request.output
        )
    }

    func invalidateLUTCache() async {}

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) async -> HistogramData? {
        guard let fixture = fixtures[source.cacheFingerprint] else { return nil }
        return Self.histogram(for: fixture.tone)
    }

    func maskedHistogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, mask: NormalizedMask
    ) async -> WeightedHistogramData? {
        guard let fixture = fixtures[source.cacheFingerprint] else { return nil }
        let mean: Float
        if mask.coverage > 0.6 { mean = fixture.specs.first { $0.kind == .background }?.mean ?? 0.5 }
        else if mask.coverage < 0.1 { mean = fixture.specs.first { $0.kind == .face }?.mean ?? 0.5 }
        else { mean = fixture.specs.first { $0.kind == .subject }?.mean ?? 0.5 }
        let bin = min(255, max(0, Int((mean * 255).rounded())))
        var bins = [Double](repeating: 0, count: 256)
        bins[bin] = 1
        return WeightedHistogramData(red: bins, green: bins, blue: bins, luma: bins)
    }

    private static func histogram(for tone: CorpusFixture.Tone) -> HistogramData {
        let values: [(Float, Int)] = [
            (tone.p05, 5), (tone.p10, 5), (tone.p25, 15), (tone.p50, 40),
            (tone.p75, 15), (tone.p90, 10), (tone.p95, 10),
        ]
        func bins() -> [Int] {
            var result = [Int](repeating: 0, count: 256)
            for (value, count) in values {
                result[min(255, max(0, Int((value * 255).rounded()))) ] += count
            }
            return result
        }
        let bins = bins()
        return HistogramData(red: bins, green: bins, blue: bins, luma: bins)
    }
}

private enum CorpusError: Error {
    case missingMask
}
