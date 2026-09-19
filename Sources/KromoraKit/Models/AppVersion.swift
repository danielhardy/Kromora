#if KROMORA_DIRECT_DISTRIBUTION
import Foundation

/// A numeric release version used by Kromora's GitHub Releases updater.
///
/// GitHub tags may have a leading `v`; prerelease and build suffixes are deliberately rejected so
/// a malformed release cannot silently win an update comparison.
public struct AppVersion: Sendable, Equatable, Comparable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// The packaged app's version. A bare SwiftPM executable has no app metadata and returns nil.
    public static var current: Self? {
        guard let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return Self(value)
    }
}
#endif
