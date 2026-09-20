import CoreGraphics
import Foundation

/// The crop ratios exposed by the editor.
///
/// Presets are named in their conventional photographer-facing orientation. Legacy callers can
/// use `.automatic` orientation to retain the source-aware behavior; the crop UI stores an
/// explicit portrait or landscape choice when one is selected.
enum CropAspectRatio: String, Codable, CaseIterable, Hashable, Sendable {
    case original = "Original"
    case freeform = "Freeform"
    case square = "1:1"
    case sixteenToNine = "16:9"
    case fourToFive = "4:5"
    case fiveToSeven = "5:7"
    case fourToThree = "4:3"
    case threeToFive = "3:5"
    case threeToTwo = "3:2"
    case custom = "Custom"

    var label: String { rawValue }

    var isFreeform: Bool { self == .freeform || self == .custom }

    var supportsOrientationSelection: Bool {
        self != .original && !isFreeform && self != .square
    }

    func selectionLabel(for orientation: CropAspectRatioOrientation) -> String {
        guard supportsOrientationSelection else { return label }
        switch orientation {
        case .landscape: return "\(landscapeLabel) Landscape"
        case .portrait: return "\(portraitLabel) Portrait"
        case .automatic: return label
        }
    }

    /// The ratio label for the resulting frame shape, without an orientation suffix — for UI
    /// that presents orientation separately from the ratio picker (e.g. an icon control).
    func shapeLabel(for orientation: CropAspectRatioOrientation) -> String {
        guard supportsOrientationSelection else { return label }
        switch orientation {
        case .landscape: return landscapeLabel
        case .portrait: return portraitLabel
        case .automatic: return label
        }
    }

    private var landscapeLabel: String {
        switch self {
        case .fourToFive: return "5:4"
        case .fiveToSeven: return "7:5"
        case .threeToFive: return "5:3"
        case .original, .freeform, .square, .sixteenToNine, .fourToThree, .threeToTwo, .custom:
            return label
        }
    }

    private var portraitLabel: String {
        switch self {
        case .threeToTwo: return "2:3"
        case .fourToThree: return "3:4"
        case .sixteenToNine: return "9:16"
        case .fourToFive: return "4:5"
        case .fiveToSeven: return "5:7"
        case .threeToFive: return "3:5"
        case .original, .freeform, .square, .custom: return label
        }
    }

    private var landscapePixelRatio: CGFloat? {
        switch self {
        case .original: return 1
        case .freeform, .custom: return nil
        case .square: return 1
        case .fourToThree: return 4.0 / 3.0
        case .sixteenToNine: return 16.0 / 9.0
        case .fourToFive: return 5.0 / 4.0
        case .fiveToSeven: return 7.0 / 5.0
        case .threeToFive: return 5.0 / 3.0
        case .threeToTwo: return 3.0 / 2.0
        }
    }

    /// The width-to-height ratio in normalized source coordinates. Normalization is necessary
    /// because a 1:1 rectangle in a 3:2 image has a normalized width-to-height ratio of 2:3.
    func normalizedRatio(
        for imageSize: CGSize,
        orientation: CropAspectRatioOrientation = .automatic
    ) -> CGFloat? {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
            imageSize.width > 0, imageSize.height > 0
        else { return nil }

        // The source's pixel aspect becomes a 1:1 ratio in normalized coordinates. This keeps
        // Original tied to the source framing without treating it as a crop reset.
        if self == .original { return 1 }
        guard let landscapePixelRatio else { return nil }

        let pixelRatio: CGFloat
        switch orientation {
        case .landscape:
            pixelRatio = landscapePixelRatio
        case .portrait:
            pixelRatio = 1 / landscapePixelRatio
        case .automatic:
            pixelRatio =
                imageSize.width < imageSize.height
                ? 1 / landscapePixelRatio
                : landscapePixelRatio
        }
        let normalizedRatio = pixelRatio * imageSize.height / imageSize.width
        guard normalizedRatio.isFinite, normalizedRatio > 0 else { return nil }
        return normalizedRatio
    }
}

/// Orientation selected for a non-square crop preset. `automatic` preserves the behavior of
/// documents written before explicit portrait/landscape choices were added.
enum CropAspectRatioOrientation: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case landscape
    case portrait
}

/// The committed, non-destructive crop framing.
///
/// The rectangle is expressed in the oriented source image's normalized coordinate space. Its
/// origin is bottom-left, matching Core Image and keeping the value independent of preview scale.
/// The selected aspect ratio and orientation are persisted alongside the rectangle so reopening
/// the crop tool, undoing, or exporting never loses the user's framing constraint.
struct CropAdjustments: Codable, Equatable, Sendable {
    static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let neutral = CropAdjustments()

    var normalizedRect: CGRect? {
        didSet { normalizedRect = Self.normalized(normalizedRect) }
    }

    var aspectRatio: CropAspectRatio
    var orientation: CropAspectRatioOrientation

    /// Continuous clockwise deskew in degrees. It is deliberately separate from
    /// `ImageRotation`, whose four values remain exact quarter turns.
    var straightenAngle: Double {
        didSet { straightenAngle = Self.clampedAngle(straightenAngle) }
    }

    /// Mirrors are applied after the quarter-turn and before straighten/crop.
    var flipHorizontal: Bool
    var flipVertical: Bool

    /// Normalized keystone controls. Values are deliberately bounded below one so the
    /// quadrilateral used by Core Image cannot collapse or invert the photo.
    var verticalPerspective: Double {
        didSet { verticalPerspective = Self.clampedPerspective(verticalPerspective) }
    }
    var horizontalPerspective: Double {
        didSet { horizontalPerspective = Self.clampedPerspective(horizontalPerspective) }
    }

    init(
        normalizedRect: CGRect? = nil,
        aspectRatio: CropAspectRatio = .freeform,
        orientation: CropAspectRatioOrientation = .automatic,
        straightenAngle: Double = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        verticalPerspective: Double = 0,
        horizontalPerspective: Double = 0
    ) {
        self.normalizedRect = Self.normalized(normalizedRect)
        self.aspectRatio = aspectRatio
        self.orientation = orientation
        self.straightenAngle = Self.clampedAngle(straightenAngle)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.verticalPerspective = Self.clampedPerspective(verticalPerspective)
        self.horizontalPerspective = Self.clampedPerspective(horizontalPerspective)
    }

    var isIdentity: Bool {
        guard let normalizedRect else {
            return aspectRatio.isFreeform && straightenAngle == 0
                && !flipHorizontal && !flipVertical
                && verticalPerspective == 0 && horizontalPerspective == 0
        }
        return normalizedRect == Self.unitRect
            && (aspectRatio.isFreeform || aspectRatio == .original)
            && straightenAngle == 0 && !flipHorizontal && !flipVertical
            && verticalPerspective == 0 && horizontalPerspective == 0
    }

    var hasGeometryTransform: Bool {
        straightenAngle != 0 || flipHorizontal || flipVertical
            || verticalPerspective != 0 || horizontalPerspective != 0
    }

    private enum CodingKeys: String, CodingKey {
        case normalizedRect, aspectRatio, orientation, straightenAngle, flipHorizontal, flipVertical,
             verticalPerspective, horizontalPerspective
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        normalizedRect = Self.normalized(
            try container.decodeIfPresent(CGRect.self, forKey: .normalizedRect)
        )
        aspectRatio =
            try container.decodeIfPresent(CropAspectRatio.self, forKey: .aspectRatio) ?? .freeform
        orientation =
            try container.decodeIfPresent(
                CropAspectRatioOrientation.self, forKey: .orientation
            ) ?? .automatic
        straightenAngle = Self.clampedAngle(
            try container.decodeIfPresent(Double.self, forKey: .straightenAngle) ?? 0
        )
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        flipVertical = try container.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        verticalPerspective = Self.clampedPerspective(
            try container.decodeIfPresent(Double.self, forKey: .verticalPerspective) ?? 0
        )
        horizontalPerspective = Self.clampedPerspective(
            try container.decodeIfPresent(Double.self, forKey: .horizontalPerspective) ?? 0
        )
    }

    private static func normalized(_ rect: CGRect?) -> CGRect? {
        guard let rect,
            rect.origin.x.isFinite, rect.origin.y.isFinite,
            rect.size.width.isFinite, rect.size.height.isFinite,
            rect.width > 0, rect.height > 0
        else { return nil }

        let clipped = rect.intersection(unitRect)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    /// Remap the crop for a change in the image's quarter-turn rotation so it keeps framing the
    /// same visual content once the underlying image is reoriented.
    ///
    /// `normalizedRect` is defined in the *oriented* source's coordinate space (see the type
    /// comment), so a committed crop must be carried through the same rotation applied to the
    /// image — otherwise the stored rectangle silently gets reinterpreted against the new,
    /// axis-swapped extent and frames the wrong region.
    func rotated(byClockwiseQuarterTurns turns: Int) -> CropAdjustments {
        let steps = ((turns % 4) + 4) % 4
        guard steps != 0 else { return self }

        var result = self
        if var current = normalizedRect {
            for _ in 0..<steps {
                current = CGRect(
                    x: current.minY,
                    y: 1 - current.minX - current.width,
                    width: current.height,
                    height: current.width
                )
            }
            result.normalizedRect = current
        }
        if steps % 2 == 1 {
            swap(&result.flipHorizontal, &result.flipVertical)
            let vertical = result.verticalPerspective
            result.verticalPerspective = result.horizontalPerspective
            result.horizontalPerspective = vertical
        }
        return result
    }

    /// Remap a crop rectangle when the active photo mirror changes, preserving the framed
    /// source content while keeping the rectangle in the post-mirror coordinate space.
    func mirrored(horizontal: Bool = false, vertical: Bool = false) -> CropAdjustments {
        var result = self
        guard var rect = normalizedRect else {
            if horizontal {
                result.flipHorizontal.toggle()
                result.horizontalPerspective *= -1
            }
            if vertical {
                result.flipVertical.toggle()
                result.verticalPerspective *= -1
            }
            return result
        }
        if horizontal {
            rect.origin.x = 1 - rect.maxX
            result.flipHorizontal.toggle()
            result.horizontalPerspective *= -1
        }
        if vertical {
            rect.origin.y = 1 - rect.maxY
            result.flipVertical.toggle()
            result.verticalPerspective *= -1
        }
        result.normalizedRect = rect
        return result
    }

    private static func clampedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -45), 45)
    }

    static let maximumPerspective = 0.8

    private static func clampedPerspective(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -maximumPerspective), maximumPerspective)
    }
}

/// Pure crop geometry shared by the SwiftUI overlay and model tests.
enum CropOverlayInteraction {
    static func applying(
        _ aspectRatio: CropAspectRatio,
        orientation: CropAspectRatioOrientation = .automatic,
        to rect: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        guard
            let targetRatio = aspectRatio.normalizedRatio(for: imageSize, orientation: orientation),
            let current = CropAdjustments(normalizedRect: rect).normalizedRect
        else { return rect }

        // Preserve the current crop area and center wherever possible. Scaling both dimensions
        // from the current area avoids an aspect-ratio change unexpectedly zooming the subject.
        let area = current.width * current.height
        var width = sqrt(area * targetRatio)
        var height = width / targetRatio
        let scale = min(1 / width, 1 / height)
        if scale < 1 {
            width *= scale
            height *= scale
        }
        return centeredRect(width: width, height: height, around: current.center)
    }

    static func translated(_ rect: CGRect, delta: CGSize, imageRect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        return rect.offsetBy(
            dx: min(max(dx, -rect.minX), 1 - rect.maxX),
            dy: min(max(dy, -rect.minY), 1 - rect.maxY)
        )
    }

    static func resized(
        _ rect: CGRect,
        handle: CropHandle,
        delta: CGSize,
        imageRect: CGRect,
        aspectRatio: CropAspectRatio = .freeform,
        orientation: CropAspectRatioOrientation = .automatic,
        imageSize: CGSize = .zero
    ) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
        guard
            let targetRatio = aspectRatio.normalizedRatio(
                for: imageSize, orientation: orientation
            )
        else {
            return freeformResized(rect, handle: handle, delta: delta, imageRect: imageRect)
        }

        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        let anchor: CGPoint
        let target: CGPoint
        let horizontalDirection: CGFloat
        let verticalDirection: CGFloat

        switch handle {
        case .topLeading:
            anchor = CGPoint(x: rect.maxX, y: rect.minY)
            target = CGPoint(x: rect.minX + dx, y: rect.maxY + dy)
            horizontalDirection = -1
            verticalDirection = 1
        case .topTrailing:
            anchor = CGPoint(x: rect.minX, y: rect.minY)
            target = CGPoint(x: rect.maxX + dx, y: rect.maxY + dy)
            horizontalDirection = 1
            verticalDirection = 1
        case .bottomLeading:
            anchor = CGPoint(x: rect.maxX, y: rect.maxY)
            target = CGPoint(x: rect.minX + dx, y: rect.minY + dy)
            horizontalDirection = -1
            verticalDirection = -1
        case .bottomTrailing:
            anchor = CGPoint(x: rect.minX, y: rect.maxY)
            target = CGPoint(x: rect.maxX + dx, y: rect.minY + dy)
            horizontalDirection = 1
            verticalDirection = -1
        }

        let requestedWidth = abs(target.x - anchor.x)
        let requestedHeight = abs(target.y - anchor.y)
        // A one-axis drag must be allowed to change the corresponding dimension. Using `max`
        // unconditionally makes an inward horizontal drag compare against the unchanged height
        // and return the old width, which is especially visible on the top-left handle.
        let horizontalDrag = abs(dx) > 0.000001
        let verticalDrag = abs(dy) > 0.000001
        var width: CGFloat
        if horizontalDrag && !verticalDrag {
            width = requestedWidth
        } else if verticalDrag && !horizontalDrag {
            width = requestedHeight * targetRatio
        } else {
            width = max(requestedWidth, requestedHeight * targetRatio)
        }
        let maxWidth = horizontalDirection > 0 ? 1 - anchor.x : anchor.x
        let maxHeight = verticalDirection > 0 ? 1 - anchor.y : anchor.y
        let maximumWidth = min(maxWidth, maxHeight * targetRatio)
        let minimumWidth = min(maximumWidth, max(0.04, 0.04 * targetRatio))
        width = min(max(width, minimumWidth), maximumWidth)
        let height = width / targetRatio

        let minX = horizontalDirection > 0 ? anchor.x : anchor.x - width
        let minY = verticalDirection > 0 ? anchor.y : anchor.y - height
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func freeformResized(
        _ rect: CGRect, handle: CropHandle, delta: CGSize, imageRect: CGRect
    ) -> CGRect {
        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        let minimum: CGFloat = 0.04
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeading:
            minX = min(max(rect.minX + dx, 0), rect.maxX - minimum)
            maxY = min(max(rect.maxY + dy, rect.minY + minimum), 1)
        case .topTrailing:
            maxX = min(max(rect.maxX + dx, rect.minX + minimum), 1)
            maxY = min(max(rect.maxY + dy, rect.minY + minimum), 1)
        case .bottomLeading:
            minX = min(max(rect.minX + dx, 0), rect.maxX - minimum)
            minY = min(max(rect.minY + dy, 0), rect.maxY - minimum)
        case .bottomTrailing:
            maxX = min(max(rect.maxX + dx, rect.minX + minimum), 1)
            minY = min(max(rect.minY + dy, 0), rect.maxY - minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func centeredRect(width: CGFloat, height: CGFloat, around center: CGPoint)
        -> CGRect
    {
        CGRect(
            x: min(max(center.x - width / 2, 0), 1 - width),
            y: min(max(center.y - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }
}

enum CropHandle: CaseIterable, Hashable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// Result of mapping a pointer location onto the crop overlay. Handle hits win over the interior
/// move surface so a grab on a corner resizes even when that corner sits on the overlay origin.
enum CropOverlayHit: Equatable, Sendable {
    case move
    case resize(CropHandle)
}

extension CropOverlayInteraction {
    static let handleHitTargetSize: CGFloat = 44

    static func handleHitRect(
        _ handle: CropHandle,
        cropRect: CGRect,
        bounds: CGRect,
        hitSize: CGFloat = handleHitTargetSize
    ) -> CGRect {
        let half = hitSize / 2
        let center = corner(handle, in: cropRect)
        var rect = CGRect(
            x: center.x - half, y: center.y - half, width: hitSize, height: hitSize)
        if bounds.width >= hitSize {
            rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - hitSize)
        } else {
            rect.origin.x = bounds.minX
            rect.size.width = max(0, bounds.width)
        }
        if bounds.height >= hitSize {
            rect.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - hitSize)
        } else {
            rect.origin.y = bounds.minY
            rect.size.height = max(0, bounds.height)
        }
        return rect
    }

    static func hit(
        at point: CGPoint,
        cropRect: CGRect,
        bounds: CGRect,
        hitSize: CGFloat = handleHitTargetSize
    ) -> CropOverlayHit? {
        var best: (handle: CropHandle, distance: CGFloat)?
        for handle in CropHandle.allCases {
            let rect = handleHitRect(
                handle, cropRect: cropRect, bounds: bounds, hitSize: hitSize)
            guard containsInclusive(rect, point) else { continue }
            let corner = corner(handle, in: cropRect)
            let dx = point.x - corner.x
            let dy = point.y - corner.y
            let distance = dx * dx + dy * dy
            if let current = best, distance >= current.distance { continue }
            best = (handle, distance)
        }
        if let best {
            return .resize(best.handle)
        }
        if containsInclusive(cropRect, point) {
            return .move
        }
        return nil
    }

    private static func corner(_ handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private static func containsInclusive(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY
            && point.y <= rect.maxY
    }
}

extension CGRect {
    fileprivate var center: CGPoint { CGPoint(x: midX, y: midY) }
}
