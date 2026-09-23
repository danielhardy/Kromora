import Foundation

extension BinaryFloatingPoint {
    /// Clamps finite values to a range and substitutes the caller's neutral value for NaN/infinity.
    func clamped(to range: ClosedRange<Self>, default fallback: Self) -> Self {
        guard isFinite else { return fallback }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

