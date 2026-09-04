import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import LumoKit

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
            _ = try await provider.mask(for: .person, image: image, quality: .analysis)
            XCTFail("unsupported person masks should throw")
        } catch let error as VisionSemanticMaskError {
            XCTAssertEqual(error, .unsupported(.person))
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

    func testNoForegroundIsEmptyAndBackgroundIsItsComplement() async throws {
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
        let provider = VisionSemanticMaskProvider(store: MaskStore(directory: directory))

        let foregrounds = try await provider.foregroundMasks(image: analysisImage, quality: .analysis)
        XCTAssertTrue(foregrounds.isEmpty)

        let background = try await provider.mask(for: .background, image: analysisImage, quality: .analysis)
        XCTAssertEqual(background.kind, .background)
        XCTAssertEqual(background.coverage, 1, accuracy: 0.0001)
        XCTAssertEqual(background.bounds, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
    }
}
