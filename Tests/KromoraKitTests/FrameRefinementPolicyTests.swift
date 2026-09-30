import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import KromoraKit

/// Pins `FrameRefinementPolicy.crossfadeDigestThreshold` against generated images: edits a person
/// can see must clear it, and changes they cannot must not.
final class FrameRefinementPolicyTests: XCTestCase {
    private let context = RenderEngineResources.makeOneShotContext(
        workingColorSpace: WorkingSpace.sRGB.cgColorSpace
    )

    /// A photographic stand-in: a diagonal luminance ramp with colored blocks, so exposure and
    /// white-balance edits move the grid means the way they would on a real frame.
    private func baseImage() -> CIImage {
        let size = CGSize(width: 512, height: 384)
        let ramp = CIFilter.linearGradient()
        ramp.point0 = .zero
        ramp.point1 = CGPoint(x: size.width, y: size.height)
        ramp.color0 = CIColor(red: 0.08, green: 0.1, blue: 0.14)
        ramp.color1 = CIColor(red: 0.85, green: 0.8, blue: 0.75)
        var image = ramp.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
        let blocks: [(CGRect, CIColor)] = [
            (CGRect(x: 40, y: 60, width: 160, height: 120), CIColor(red: 0.7, green: 0.2, blue: 0.15)),
            (CGRect(x: 280, y: 180, width: 180, height: 140), CIColor(red: 0.15, green: 0.45, blue: 0.3)),
            (CGRect(x: 100, y: 250, width: 120, height: 90), CIColor(red: 0.2, green: 0.25, blue: 0.7)),
        ]
        for (rect, color) in blocks {
            image = CIImage(color: color).cropped(to: rect).composited(over: image)
        }
        return image
    }

    private func digest(_ image: CIImage) throws -> PerceptualDigest {
        try XCTUnwrap(RenderEngineResources.perceptualDigest(
            of: image, space: .sRGB, context: context
        ))
    }

    private func exposure(_ image: CIImage, ev: Float) -> CIImage {
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = ev
        return filter.outputImage!
    }

    private func warm(_ image: CIImage, amount: CGFloat) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: 1 + amount, y: 0, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: 1 - amount, w: 0)
        return filter.outputImage!
    }

    private func brightness(_ image: CIImage, levels: CGFloat) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.biasVector = CIVector(x: levels / 255, y: levels / 255, z: levels / 255, w: 0)
        return filter.outputImage!
    }

    func testDigestIsDeterministicAndSizeIndependent() throws {
        let base = baseImage()
        XCTAssertEqual(try digest(base), try digest(base))
        let half = base.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        XCTAssertLessThan(
            try digest(base).distance(to: try digest(half)), 0.005,
            "a 2048 px frame and a viewport-sized render of it must compare as the same picture"
        )
    }

    func testThresholdSitsBetweenSubVisibleAndVisibleChanges() throws {
        let base = try digest(baseImage())
        let visible = [
            ("+0.5 EV exposure", try digest(exposure(baseImage(), ev: 0.5))),
            ("-0.5 EV exposure", try digest(exposure(baseImage(), ev: -0.5))),
            ("warm white balance", try digest(warm(baseImage(), amount: 0.12))),
        ]
        let subVisible = [
            ("1-level brightness", try digest(brightness(baseImage(), levels: 1))),
            ("2-level brightness", try digest(brightness(baseImage(), levels: 2))),
            ("+0.01 EV exposure", try digest(exposure(baseImage(), ev: 0.01))),
            ("identical pixels", try digest(baseImage())),
        ]
        for (name, digest) in visible {
            let distance = base.distance(to: digest)
            XCTAssertGreaterThan(distance, FrameRefinementPolicy.crossfadeDigestThreshold, name)
        }
        for (name, digest) in subVisible {
            let distance = base.distance(to: digest)
            XCTAssertLessThan(distance, FrameRefinementPolicy.crossfadeDigestThreshold, name)
        }
    }

    func testVisibleChangeCrossfadesOnceForTheDocumentedDuration() throws {
        let old = try digest(baseImage())
        let new = try digest(exposure(baseImage(), ev: 0.5))
        XCTAssertEqual(
            FrameRefinementPolicy.transition(from: old, to: new, reduceMotion: false),
            .crossfade(duration: 0.12)
        )
    }

    func testSubVisibleChangeAndReduceMotionSwapImmediately() throws {
        let old = try digest(baseImage())
        let tiny = try digest(brightness(baseImage(), levels: 1))
        let big = try digest(exposure(baseImage(), ev: 0.5))
        XCTAssertEqual(
            FrameRefinementPolicy.transition(from: old, to: tiny, reduceMotion: false), .immediate
        )
        XCTAssertEqual(
            FrameRefinementPolicy.transition(from: old, to: big, reduceMotion: true), .immediate
        )
    }

    func testUnknownDigestsNeverAnimate() throws {
        let digest = try digest(baseImage())
        XCTAssertEqual(
            FrameRefinementPolicy.transition(from: nil, to: digest, reduceMotion: false), .immediate
        )
        XCTAssertEqual(
            FrameRefinementPolicy.transition(from: digest, to: nil, reduceMotion: false), .immediate
        )
    }

    func testDigestDistanceIsSymmetricAndBounded() {
        let black = PerceptualDigest(bytes: Data(repeating: 0, count: PerceptualDigest.byteCount))!
        let white = PerceptualDigest(bytes: Data(repeating: 255, count: PerceptualDigest.byteCount))!
        XCTAssertEqual(black.distance(to: white), 1, accuracy: 1e-9)
        XCTAssertEqual(white.distance(to: black), 1, accuracy: 1e-9)
        XCTAssertEqual(black.distance(to: black), 0)
    }

    func testDigestRejectsTheWrongSize() {
        XCTAssertNil(PerceptualDigest(bytes: Data(count: 10)))
    }
}
