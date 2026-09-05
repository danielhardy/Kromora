import CoreGraphics
import Foundation
import ImageIO

struct NormalizedPoint: Codable, Sendable, Equatable, Hashable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = Self.unit(x)
        self.y = Self.unit(y)
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    /// Vision's normalized origin is lower-left. Lumo's sole normalized coordinate system is
    /// upper-left, so this conversion belongs at the adapter boundary and nowhere downstream.
    static func fromVision(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: point.x, y: 1 - point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct NormalizedRect: Codable, Sendable, Equatable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        let originX = Self.unit(x)
        let originY = Self.unit(y)
        self.x = originX
        self.y = originY
        self.width = Self.unit(min(width, 1 - originX))
        self.height = Self.unit(min(height, 1 - originY))
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    static func fromVision(_ rect: CGRect) -> NormalizedRect {
        NormalizedRect(x: rect.origin.x, y: 1 - rect.origin.y - rect.height,
                       width: rect.width, height: rect.height)
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midPoint: NormalizedPoint { NormalizedPoint(x: x + width / 2, y: y + height / 2) }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// The canonical, orientation-baked image descriptor used by every analyzer in one run.
/// Pixel objects remain private to the adapter that materializes them; this value only carries the
/// reproducible source and the one chosen working resolution across actor boundaries.
struct AnalysisImage: Sendable, Equatable {
    let source: ImageSource
    /// The durable asset identity is carried into the provider so cache entries cannot be published
    /// under a source-derived identity when the same bytes represent a Photos asset.
    let assetID: PhotoAssetID?
    let dimensions: PixelDimensions
    let configuration: AnalysisConfiguration

    init(
        source: ImageSource, assetID: PhotoAssetID? = nil, dimensions: PixelDimensions,
        configuration: AnalysisConfiguration
    ) {
        self.source = source
        self.assetID = assetID
        self.dimensions = dimensions
        self.configuration = configuration
    }
}

struct AnalysisConfiguration: Sendable, Equatable {
    // Release benchmark on the reference M1 Pro fixture: 512px 221.3ms, 768px 173.7ms, and
    // 1024px 299.7ms for subject detection. All three retained the subject signal; 768px remains
    // the best balanced default. The opt-in harness and checked-in baseline live in LUMO-206.
    var maximumDimension: Int = 768

    init(maximumDimension: Int = 768) {
        self.maximumDimension = max(1, maximumDimension)
    }
}

enum AnalysisImageFactory {
    static func make(
        from source: ImageSource, assetID: PhotoAssetID? = nil,
        configuration: AnalysisConfiguration = .init()
    ) throws -> AnalysisImage {
        guard source.nativeExtent.width.isFinite, source.nativeExtent.height.isFinite,
              source.nativeExtent.width >= 1, source.nativeExtent.height >= 1 else {
            throw ImageError.processingFailed
        }

        let scale = min(1, Double(configuration.maximumDimension)
            / max(Double(source.nativeExtent.width), Double(source.nativeExtent.height)))
        let width = max(1, Int((Double(source.nativeExtent.width) * scale).rounded()))
        let height = max(1, Int((Double(source.nativeExtent.height) * scale).rounded()))
        return AnalysisImage(
            source: source, assetID: assetID,
            dimensions: PixelDimensions(width: width, height: height),
            configuration: configuration
        )
    }
}
