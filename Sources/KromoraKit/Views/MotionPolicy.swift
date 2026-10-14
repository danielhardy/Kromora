import SwiftUI

extension Animation {
    /// This animation, or `nil` when Reduce Motion is on. Pass the result to `.animation(_:value:)`
    /// or `withAnimation`; both treat `nil` as an immediate, non-animated change.
    func respectingReduceMotion(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}
