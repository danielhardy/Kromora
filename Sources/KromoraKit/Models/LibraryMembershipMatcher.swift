import CryptoKit
import Foundation

/// Answers "is this source file already in the open library?" for an import selector.
///
/// The rule is the import-time idempotency rule itself: the SHA-256 of the file's bytes compared
/// with the content hashes recorded by `PortablePackageImportCatalog`. A file this matcher reports
/// as present is therefore exactly a file `PortablePackageImporter` would report as a duplicate,
/// and the reverse. Nothing here remembers imports into other libraries or since-deleted assets;
/// the package is the only authority.
struct LibraryMembershipMatcher: Sendable {
    private static let chunkSize = 1 << 20

    private let knownHashes: Set<String>

    init(knownHashes: Set<String>) {
        self.knownHashes = knownHashes
    }

    /// Reads every live asset record once. Synchronous and I/O bound, so callers run it off the
    /// main actor.
    init(package: PortableLibraryPackage) throws {
        self.init(knownHashes: Set(try PortablePackageImportCatalog(package: package).existingHashes.keys))
    }

    /// Loads the catalog off the calling actor. The catalog read itself is synchronous, so
    /// cancellation is honored before it starts.
    static func loader(for package: PortableLibraryPackage) -> @Sendable () async throws -> LibraryMembershipMatcher {
        { try await load(from: package) }
    }

    @concurrent static func load(from package: PortableLibraryPackage) async throws -> LibraryMembershipMatcher {
        try Task.checkCancellation()
        return try LibraryMembershipMatcher(package: package)
    }

    var isEmpty: Bool { knownHashes.isEmpty }

    /// The digest of in-memory bytes, identical to `contentHash(of:)` for the same content.
    static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    func contains(contentHash: String) -> Bool {
        knownHashes.contains(contentHash)
    }

    /// Streams the file through SHA-256 in bounded chunks, matching the package staging digest.
    /// Returns nil when cancelled; throws when the file cannot be read.
    static func contentHash(of url: URL, isCancelled: () -> Bool = { false }) throws -> String? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if isCancelled() { return nil }
            guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }

    /// The ids of `files` whose bytes are already in the library. Unreadable files are left
    /// untagged: the import reports them as failures, and the selector must not claim membership
    /// it cannot prove. Stops early, returning what it found, when `isCancelled` becomes true.
    func memberIDs(in files: [MediaVolumeFile], isCancelled: () -> Bool = { false }) -> Set<String> {
        guard !knownHashes.isEmpty else { return [] }
        var members: Set<String> = []
        for file in files {
            if isCancelled() { break }
            guard let hash = try? Self.contentHash(of: file.url, isCancelled: isCancelled),
                  knownHashes.contains(hash) else { continue }
            members.insert(file.id)
        }
        return members
    }
}
