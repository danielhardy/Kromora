import CoreGraphics
import Foundation

/// A neutral, downsampled source image in CIE Lab. Only value storage crosses the render actor.
struct RetouchAnalysisProxy: Sendable, Equatable {
    let width: Int
    let height: Int
    let pixels: [SIMD3<Float>]

    init(width: Int, height: Int, pixels: [SIMD3<Float>]) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.pixels = pixels.count == max(0, width) * max(0, height) ? pixels : []
    }

    var isUsable: Bool { width > 0 && height > 0 && pixels.count == width * height }

    func lab(x: Int, y: Int) -> SIMD3<Float>? {
        guard isUsable, x >= 0, y >= 0, x < width, y < height else { return nil }
        return pixels[y * width + x]
    }

    /// Converts an sRGB RGBA8 raster into linear-light Lab values.
    static func fromRGBA8(_ data: Data, width: Int, height: Int) -> Self {
        guard width > 0, height > 0, data.count >= width * height * 4 else {
            return Self(width: 0, height: 0, pixels: [])
        }
        let bytes = [UInt8](data.prefix(width * height * 4))
        let values = stride(from: 0, to: bytes.count, by: 4).map { i -> SIMD3<Float> in
            func linear(_ byte: UInt8) -> Float {
                let v = Float(byte) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let r = linear(bytes[i]), g = linear(bytes[i + 1]), b = linear(bytes[i + 2])
            let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
            let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
            let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
            func f(_ t: Float) -> Float { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
            let fx = f(x), fy = f(y), fz = f(z)
            return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
        }
        return Self(width: width, height: height, pixels: values)
    }
}

/// Full-resolution Lab pixels for a bounded source-space window, supplied on demand by RenderEngine.
struct RetouchAnalysisRegion: Sendable, Equatable {
    let sourceWidth: Int
    let sourceHeight: Int
    let originX: Int
    let originY: Int
    let proxy: RetouchAnalysisProxy

    func lab(sourceX: Int, sourceY: Int) -> SIMD3<Float>? {
        proxy.lab(x: sourceX - originX, y: sourceY - originY)
    }
}
