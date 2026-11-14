import CoreImage
import XCTest

@testable import KromoraKit

/// The tone curve is drawn in sRGB-encoded coordinates, but the engine evaluates the graph in
/// extended **linear** Display P3. These tests run the curve in that context (`MetalKernelParityTests`
/// pin `.sRGB` and cannot see the difference) and pin the documented policy: encoded lookup through a
/// 1024-texel table, slope-1 extension outside [0, 1].
final class ToneCurveEngineContextTests: XCTestCase {
    private let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    private func encode(_ v: Float) -> Float {
        let a = abs(v)
        let e = a <= 0.0031308 ? 12.92 * a : 1.055 * powf(a, 1 / 2.4) - 0.055
        return v < 0 ? -e : e
    }

    /// Renders a flat patch through the curve in the engine's working space and returns the
    /// sRGB-encoded result of the first channel.
    private func curved(_ curve: LightToneCurve, patch color: CIColor) throws -> Float {
        let context = CIContext(options: [
            .workingColorSpace: linearP3, .workingFormat: CIFormat.RGBAh.rawValue,
        ])
        let source = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let result = ToneCurveFilterCache().apply(curve, to: source)
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            result, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
            format: .RGBAf, colorSpace: linearP3)
        return encode(pixel[0])
    }

    private func patch(encoded: CGFloat) -> CIColor {
        CIColor(red: encoded, green: encoded, blue: encoded, colorSpace: displayP3)!
    }

    func testEncodedQuarterMapsToStatedPoint() throws {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.25, output: 0.35),
            LightCurvePoint(input: 1, output: 1),
        ])
        XCTAssertEqual(try curved(curve, patch: patch(encoded: 0.25)), 0.35, accuracy: 0.004)
    }

    func testShadowsKeepPrecision() throws {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.1, output: 0.2),
            LightCurvePoint(input: 1, output: 1),
        ])
        // Encoded 0.05 is linear 0.0039, about one texel of the old 256-entry linear table.
        XCTAssertEqual(
            try curved(curve, patch: patch(encoded: 0.05)), Float(curve.value(at: 0.05)),
            accuracy: 0.004)
    }

    func testExtendedValuesAreExtendedNotClamped() throws {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.5, output: 0.6),
            LightCurvePoint(input: 1, output: 1),
        ])
        // Linear 2.0 encodes above 1; slope-1 extension keeps it above the curve's top output.
        let high = CIColor(red: 2, green: 2, blue: 2, colorSpace: linearP3)!
        let encodedHigh = encode(2)
        XCTAssertEqual(try curved(curve, patch: high), encodedHigh, accuracy: 0.01)
        XCTAssertGreaterThan(try curved(curve, patch: high), 1.2)
        let negative = CIColor(red: -0.05, green: 0, blue: 0, colorSpace: linearP3)!
        XCTAssertLessThan(try curved(curve, patch: negative), 0)
    }
}
