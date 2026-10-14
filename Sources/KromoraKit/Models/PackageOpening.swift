import Foundation

/// A library package that is open and whose writer lease this process holds, but that no session
/// owns yet. Both members are `Sendable`, so the blocking open can run off the main actor and hand
/// the result to the main actor, which builds the non-`Sendable` ``PortableLibrarySession``.
///
/// Whoever holds one must either build a session from it or release the lease.
struct OpenedPackage: Sendable {
    let package: PortableLibraryPackage
    let lease: PortablePackageLease
    var recoveredPreviousWriter = false

    /// Releases a lease that was acquired but never bound. Idempotent: a released lease is a no-op.
    func releaseUnbound() { try? lease.release() }
}

/// Opens the library package without occupying the main actor.
protocol PackageOpening: Sendable {
    /// `allowsExpiredLeaseTakeover` answers the question about a lease that expired under a writer
    /// that is not conclusively dead; a conclusively dead local writer is always recovered.
    func open(at url: URL, allowsExpiredLeaseTakeover: Bool) async throws -> OpenedPackage
}

struct PortablePackageOpener: PackageOpening {
    @concurrent
    func open(at url: URL, allowsExpiredLeaseTakeover: Bool) async throws -> OpenedPackage {
        try Task.checkCancellation()
        // Cancellation cannot interrupt this call: recovery checksums staged files and the
        // filesystem calls block. A cancelled open is therefore detected by the caller after the
        // fact, which releases the lease instead of binding it.
        return try Self.openBlocking(at: url, asynchronousIndexLoading: true) { _ in
            allowsExpiredLeaseTakeover
        }
    }

    /// Acquires the lease, recovering a dead or (confirmed) expired writer first.
    nonisolated static func openBlocking(
        at url: URL,
        asynchronousIndexLoading: Bool,
        confirmTakeover: (PortablePackageLeaseInfo) -> Bool
    ) throws -> OpenedPackage {
        func acquire(recoverExpiredLease: Bool = false) throws -> OpenedPackage {
            try PortableLibrarySession.acquire(
                at: url, now: Date(), recoverExpiredLease: recoverExpiredLease,
                asynchronousIndexLoading: asynchronousIndexLoading)
        }
        do {
            return try acquire()
        } catch let error as PortablePackageLeaseError {
            switch error {
            case .contended(let info) where info.localWriterState == .dead:
                try PortablePackageLease.recoverDeadWriter(at: url)
                var opened = try acquire()
                opened.recoveredPreviousWriter = true
                return opened
            case .expired(let info):
                let shouldRecover: Bool
                switch info.localWriterState {
                case .dead:
                    shouldRecover = true
                case .live, .remoteOrUnknown:
                    shouldRecover = confirmTakeover(info)
                }
                guard shouldRecover else { throw error }
                var opened = try acquire(recoverExpiredLease: true)
                opened.recoveredPreviousWriter = true
                return opened
            default:
                throw error
            }
        }
    }
}
