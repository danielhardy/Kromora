import Foundation

/// One Look whose original file bytes the package edit boundary may embed. Only immutable,
/// `Sendable` identity crosses to the worker; `retainedAccesses` keep any security scopes open for
/// the whole read.
struct EmbeddedLookSource: Sendable {
    let id: String
    let url: URL
}

/// Reads whole Look files away from the main actor.
///
/// `read` is injectable so tests can prove which executor performs the I/O and hold a read open
/// deterministically. A Look that cannot be read is skipped, matching the previous policy.
enum EmbeddedLookLoader {
    typealias Reader = @Sendable (URL) -> Data?

    static let fileReader: Reader = { try? Data(contentsOf: $0) }

    @concurrent
    static func load(
        _ sources: [EmbeddedLookSource],
        retaining accesses: [SecurityScopedResourceAccess],
        reader: Reader
    ) async -> [String: Data] {
        var values: [String: Data] = [:]
        for source in sources {
            if Task.isCancelled { break }
            if let data = reader(source.url) { values[source.id] = data }
        }
        withExtendedLifetime(accesses) {}
        return values
    }
}
