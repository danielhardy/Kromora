import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import KromoraKit

final class VisionSemanticMaskProviderTests: XCTestCase {
    func testProviderCanConstructAnActorLocalRequestHandler() async throws {
        let source = ImageSource(
            backing: .data(Data([0, 1, 2])), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 32)
        )
        let image = AnalysisImage(
            source: source, dimensions: PixelDimensions(width: 32, height: 32),
            configuration: .init(maximumDimension: 32)
        )
        let directory = try Fixtures.makeTempDirectory("VisionTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = VisionSemanticMaskProvider(store: MaskStore(directory: directory))

        do {
            try await provider.validateRequestHandler(for: image)
            XCTFail("invalid image data should not construct a handler")
        } catch {
            XCTAssertTrue(error is VisionSemanticMaskError)
        }
    }

    func testStillUnsupportedKindsUseTypedErrors() async throws {
        let source = ImageSource(
            backing: .data(Data()), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 32)
        )
        let image = AnalysisImage(
            source: source, dimensions: PixelDimensions(width: 32, height: 32),
            configuration: .init(maximumDimension: 32)
        )
        let provider = VisionSemanticMaskProvider()

        do {
            _ = try await provider.mask(for: .unknown("future"), image: image, quality: .analysis)
            XCTFail("unknown mask kinds should throw")
        } catch let error as VisionSemanticMaskError {
            XCTAssertEqual(error, .unsupported(.unknown("future")))
        }
    }

    func testNoFaceIsReportedAsTypedFailureForValidImage() async throws {
        let directory = try Fixtures.makeTempDirectory("FaceMaskTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try Fixtures.makeCGImage(width: 64, height: 48, red: 0.25, green: 0.25, blue: 0.25)
        let url = directory.appendingPathComponent("solid.png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { XCTFail("could not create image destination"); return }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let source = ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 48))
        let analysisImage = try AnalysisImageFactory.make(from: source, configuration: .init(maximumDimension: 64))
        let provider = VisionSemanticMaskProvider(store: MaskStore(directory: directory))

        do {
            _ = try await provider.mask(for: .face, image: analysisImage, quality: .analysis)
            XCTFail("a flat image should not produce a face mask")
        } catch let error as VisionSemanticMaskError {
            XCTAssertEqual(error, .noFaceDetected)
        }
    }

    func testNoForegroundIsEmptyAndBackgroundIsItsComplementThroughCoordinator() async throws {
        let directory = try Fixtures.makeTempDirectory("ForegroundMaskTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try Fixtures.makeCGImage(width: 64, height: 48, red: 0.25, green: 0.25, blue: 0.25)
        let url = directory.appendingPathComponent("solid.png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { XCTFail("could not create image destination"); return }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let source = ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 48))
        let analysisImage = try AnalysisImageFactory.make(from: source, configuration: .init(maximumDimension: 64))
        let store = MaskStore(directory: directory)
        let provider = VisionSemanticMaskProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )

        let foregrounds = try await provider.foregroundMasks(image: analysisImage, quality: .analysis)
        XCTAssertTrue(foregrounds.isEmpty)

        let assetID = PhotoAnalysisCoordinator.assetID(for: source)
        let foreground = try await coordinator.mask(
            assetID: assetID, source: source, kind: .foreground, quality: .analysis
        )
        XCTAssertEqual(foreground.kind, .foreground)
        XCTAssertEqual(foreground.coverage, 0, accuracy: 0.0001)

        let background = try await coordinator.mask(
            assetID: assetID, source: source, kind: .background, quality: .analysis
        )
        XCTAssertEqual(background.kind, .background)
        XCTAssertEqual(background.coverage, 1, accuracy: 0.0001)
        XCTAssertEqual(background.bounds, NormalizedRect(x: 0, y: 0, width: 1, height: 1))

        let foregroundPixels = await store.pixels(for: foreground.reference)
        let backgroundPixels = await store.pixels(for: background.reference)
        XCTAssertEqual(backgroundPixels?.values, foregroundPixels?.values.map { 1 - $0 })

        let cachedBackground = try await coordinator.mask(
            assetID: assetID, source: source, kind: .background, quality: .analysis
        )
        XCTAssertEqual(cachedBackground.reference, background.reference)
    }

    func testPersonSegmentationIsGatedWithoutCachedSignals() async throws {
        let source = ImageSource(
            backing: .data(Data()), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 32)
        )
        let image = AnalysisImage(
            source: source, dimensions: PixelDimensions(width: 32, height: 32),
            configuration: .init(maximumDimension: 32)
        )
        let provider = VisionSemanticMaskProvider()

        do {
            _ = try await provider.mask(for: .person, image: image, quality: .analysis)
            XCTFail("person segmentation should not run without a face or foreground signal")
        } catch let error as VisionSemanticMaskError {
            XCTAssertEqual(error, .personNotApplicable)
        }
    }

    func testForegroundUnionAcceptsInstanceMasksAtProviderResolution() async throws {
        // Regression: Vision reports instance masks at its own output resolution (e.g. a square
        // 512×512 buffer for a 3:2 source), so seeding the union at the analysis dimensions made
        // MaskOperations.union throw incompatibleSizes for every real Foreground/Background mask.
        let directory = try Fixtures.makeTempDirectory("ForegroundUnionSizeTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let provider = VisionSemanticMaskProvider(store: store)

        let source = ImageSource(
            backing: .data(Data([7, 8, 9])), kind: .standard,
            nativeExtent: CGSize(width: 96, height: 64)
        )
        let image = try AnalysisImageFactory.make(
            from: source, configuration: .init(maximumDimension: 96)
        )
        XCTAssertNotEqual(image.dimensions, PixelDimensions(width: 16, height: 16))

        // Two instance entries at Vision-style dimensions that differ from the analysis dims.
        let instanceSize = PixelDimensions(width: 16, height: 16)
        let first = try NormalizedMask(
            size: instanceSize,
            values: (0..<256).map { $0 % 16 < 8 ? Float(1) : Float(0) }
        )
        let second = try NormalizedMask(
            size: instanceSize,
            values: (0..<256).map { $0 / 16 < 4 ? Float(0.5) : Float(0) }
        )
        for (kind, pixels) in [(SemanticMaskKind.foregroundInstance(0), first),
                               (.foregroundInstance(1), second)] {
            let key = await provider.cacheKey(for: kind, image: image, quality: .analysis)
            _ = try await store.store(pixels, for: key, quality: .analysis)
        }

        let union = try await provider.foregroundUnionMask(image: image, quality: .analysis)
        XCTAssertEqual(union.kind, .foreground)
        let maybeUnionPixels = await store.pixels(for: union.reference)
        let unionPixels = try XCTUnwrap(maybeUnionPixels)
        XCTAssertEqual(unionPixels.size, instanceSize, "the union must adopt the instance resolution")
        let expected = try MaskOperations.union(first, second)
        XCTAssertEqual(unionPixels.values, expected.values)
    }

    func testCachedPersonMaskIsReturnedWithoutGatingSignals() async throws {
        // Regression: the person gate ran before the cache lookup, so an already-paid person
        // matte failed with personNotApplicable whenever the face/foreground entries were not
        // cached at the same quality — surfacing as "could not be resolved" on photo re-opens.
        let directory = try Fixtures.makeTempDirectory("PersonCacheGateTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let provider = VisionSemanticMaskProvider(store: store)

        let source = ImageSource(
            backing: .data(Data([3, 1, 4])), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 32)
        )
        let image = try AnalysisImageFactory.make(
            from: source, configuration: .init(maximumDimension: 32)
        )
        let pixels = try NormalizedMask(
            size: PixelDimensions(width: 8, height: 8),
            values: (0..<64).map { $0 % 8 < 3 ? Float(1) : Float(0) }
        )
        let key = await provider.cacheKey(for: .person, image: image, quality: .analysis)
        let reference = try await store.store(pixels, for: key, quality: .analysis)

        let mask = try await provider.mask(for: .person, image: image, quality: .analysis)
        XCTAssertEqual(mask.reference, reference)
        XCTAssertEqual(mask.coverage, pixels.coverage, accuracy: 0.0001)
    }
}
