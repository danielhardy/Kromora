import Foundation
import Synchronization

/// Owns one active security scope and relinquishes it exactly once.
///
/// Open/save panels and Finder drops can give the app an already-started scope, while a resolved
/// security-scoped bookmark must be started explicitly. Keeping that distinction at the boundary
/// prevents duplicate starts and lets asynchronous workers retain the grant until their I/O ends.
struct SecurityScopedResourceAccess: Sendable {
    private let lifetime: Lifetime

    var url: URL { lifetime.url }

    private init(url: URL, stop: @escaping @Sendable (URL) -> Void) {
        lifetime = Lifetime(url: url, stop: stop)
    }

    /// Wrap access that AppKit or the system already started for a panel or drop result.
    static func systemGranted(
        for url: URL,
        stop: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) -> Self {
        Self(url: url, stop: stop)
    }

    /// Start a security scope and return its owner only when the start succeeds.
    static func startAccessing(
        _ url: URL,
        start: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stop: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) -> Self? {
        guard start(url) else { return nil }
        return Self(url: url, stop: stop)
    }

    func release() {
        lifetime.release()
    }

    private final class Lifetime: Sendable {
        let url: URL
        private let stop: @Sendable (URL) -> Void
        private let released = Mutex(false)

        init(url: URL, stop: @escaping @Sendable (URL) -> Void) {
            self.url = url
            self.stop = stop
        }

        func release() {
            let shouldStop = released.withLock { released in
                guard !released else { return false }
                released = true
                return true
            }
            if shouldStop { stop(url) }
        }

        deinit {
            release()
        }
    }
}
