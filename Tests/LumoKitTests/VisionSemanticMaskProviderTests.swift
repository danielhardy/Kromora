import Foundation
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

    func testUnsupportedKindsUseTypedErrors() async throws {
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
            _ = try await provider.mask(for: .face, image: image, quality: .analysis)
            XCTFail("unsupported face masks should throw")
        } catch let error as VisionSemanticMaskError {
            XCTAssertEqual(error, .unsupported(.face))
        }
    }
}
