import Foundation
import XCTest

@testable import KromoraKit

/// Opt-in timing harness for the semantic-mask resize hot path. Run it in both configurations
/// with `KROMORA_MASK_RESAMPLING_BENCHMARK=1`; the ticket records the resulting wall times alongside
/// the scalar-loop baseline.
final class MaskResamplingPerformanceTests: XCTestCase {
    func testPlanarMaskUpscaleBenchmark() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_MASK_RESAMPLING_BENCHMARK"] == "1",
            "set KROMORA_MASK_RESAMPLING_BENCHMARK=1 to run the mask resize timing harness"
        )

        let sourceSize = PixelDimensions(width: 768, height: 512)
        let targetSize = PixelDimensions(width: 1920, height: 1280)
        let source = try NormalizedMask(
            size: sourceSize,
            values: (0..<sourceSize.width * sourceSize.height).map {
                Float($0 % sourceSize.width) / Float(sourceSize.width - 1)
            }
        )
        let iterations = max(
            3, Int(ProcessInfo.processInfo.environment["KROMORA_MASK_RESAMPLING_ITERATIONS"] ?? "5") ?? 5
        )

        _ = try scalarResize(source, to: targetSize)
        let scalarStart = Date()
        for _ in 0..<iterations {
            _ = try scalarResize(source, to: targetSize)
        }
        let scalarMilliseconds = Date().timeIntervalSince(scalarStart) * 1000 / Double(iterations)

        _ = try MaskOperations.scaleValues(source, to: targetSize)
        let rawStart = Date()
        for _ in 0..<iterations {
            _ = try MaskOperations.scaleValues(source, to: targetSize)
        }
        let rawMilliseconds = Date().timeIntervalSince(rawStart) * 1000 / Double(iterations)

        _ = try MaskOperations.resized(source, to: targetSize)
        let start = Date()
        for _ in 0..<iterations {
            _ = try MaskOperations.resized(source, to: targetSize)
        }
        let milliseconds = Date().timeIntervalSince(start) * 1000 / Double(iterations)
        let configuration = ProcessInfo.processInfo.environment[
            "KROMORA_MASK_RESAMPLING_CONFIGURATION"
        ] ?? "unspecified"
        print(
            String(
                format: "MASK_RESAMPLING_BENCHMARK configuration=%@ target=%dx%d scalar_ms=%.3f raw_planarF_ms=%.3f planarF_ms=%.3f speedup=%.2fx",
                configuration as NSString, targetSize.width, targetSize.height,
                scalarMilliseconds, rawMilliseconds, milliseconds, scalarMilliseconds / milliseconds
            )
        )
    }

    private func scalarResize(_ mask: NormalizedMask, to size: PixelDimensions) throws -> NormalizedMask {
        var values: [Float] = []
        values.reserveCapacity(size.width * size.height)
        for y in 0..<size.height {
            let sourceY = Double(y) / Double(max(1, size.height - 1))
                * Double(max(1, mask.size.height - 1))
            for x in 0..<size.width {
                let sourceX = Double(x) / Double(max(1, size.width - 1))
                    * Double(max(1, mask.size.width - 1))
                values.append(bilinear(mask, x: sourceX, y: sourceY))
            }
        }
        return try NormalizedMask(size: size, values: values)
    }

    private func bilinear(_ mask: NormalizedMask, x: Double, y: Double) -> Float {
        let clampedX = min(max(0, x), Double(mask.size.width - 1))
        let clampedY = min(max(0, y), Double(mask.size.height - 1))
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(mask.size.width - 1, x0 + 1)
        let y1 = min(mask.size.height - 1, y0 + 1)
        let fx = Float(clampedX - Double(x0))
        let fy = Float(clampedY - Double(y0))
        func value(_ px: Int, _ py: Int) -> Float {
            mask.values[py * mask.size.width + px]
        }
        let top = value(x0, y0) * (1 - fx) + value(x1, y0) * fx
        let bottom = value(x0, y1) * (1 - fx) + value(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }
}
