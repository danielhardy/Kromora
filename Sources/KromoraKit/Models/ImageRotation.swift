import CoreGraphics
import CoreImage
import Foundation

/// A quarter-turn image rotation stored as part of the non-destructive edit document.
///
/// The editor deliberately stores only the four canonical orientations. Repeated button presses
/// therefore cannot accumulate floating-point transform error, and the value is stable in JSON,
/// edit-history snapshots, and render-cache identities.
enum ImageRotation: Int, Codable, CaseIterable, Hashable, Sendable {
    case zero = 0
    case clockwise90 = 90
    case half = 180
    case counterClockwise90 = 270

    /// Compatibility spellings for callers that describe a turn rather than its direction.
    static let quarterTurnClockwise = Self.clockwise90
    static let quarterTurnCounterClockwise = Self.counterClockwise90

    var degrees: Int { rawValue }

    var swapsDimensions: Bool {
        self == .clockwise90 || self == .counterClockwise90
    }

    func orientedExtent(_ size: CGSize) -> CGSize {
        guard swapsDimensions else { return size }
        return CGSize(width: size.height, height: size.width)
    }

    func addingClockwiseQuarterTurns(_ count: Int = 1) -> Self {
        let normalized = ((rawValue / 90 + count) % 4 + 4) % 4
        return Self(rawValue: normalized * 90) ?? .zero
    }

    var coreImageOrientation: CGImagePropertyOrientation? {
        switch self {
        case .zero: return nil
        case .clockwise90: return .right
        case .half: return .down
        case .counterClockwise90: return .left
        }
    }
}

