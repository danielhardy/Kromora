/// Keyboard audition of Looks. The cycle is `None` followed by the library's display order, matching
/// the inspector list so Up from the first Look returns to None instead of stalling there.
enum LookNavigation {
    enum Direction {
        case previous
        case next
    }

    /// `currentIndex` is the selected Look in `allLUTs`, or `nil` for None / an unresolved reference.
    /// Returning the same slot is an intentional no-op at either end of the cycle.
    static func adjacentIndex(
        currentIndex: Int?,
        count: Int,
        direction: Direction
    ) -> Int? {
        guard count > 0 else { return nil }
        switch direction {
        case .next:
            guard let currentIndex else { return 0 }
            return min(currentIndex + 1, count - 1)
        case .previous:
            guard let currentIndex else { return nil }
            if currentIndex <= 0 { return nil }
            return currentIndex - 1
        }
    }
}
