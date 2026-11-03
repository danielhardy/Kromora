import CryptoKit
import Darwin
import Foundation

/// Application-level retention policy for a disposable on-disk cache.
///
/// Both limits apply to the cache directory only. Saved recipes, edit revisions, and canonical
/// originals live in the library package and are never reachable from a trim.
struct DiskCacheBudget: Sendable, Equatable {
    /// Total bytes across every recognized entry file. Over budget, least-recently-used entries go
    /// first.
    var maxBytes: Int64
    /// An entry not read or written for this long is dropped.
    var maxAge: TimeInterval
    /// A superseded variant (an older source fingerprint or provider/analysis version of the same
    /// asset and group) survives this long after a newer sibling exists, so an editor that
    /// alternates between two identities does not thrash.
    var supersededGrace: TimeInterval = 24 * 3600
    /// Incomplete two-file entries and unrecognized temp files younger than this are left alone
    /// because another writer may still be completing them.
    var interruptedWriteGrace: TimeInterval = 3600

    static let analysis = DiskCacheBudget(maxBytes: 128 << 20, maxAge: 90 * 24 * 3600)
    /// Roughly eight full-resolution 60-megapixel Float32 masks plus lower-quality variants.
    static let masks = DiskCacheBudget(maxBytes: 2 << 30, maxAge: 30 * 24 * 3600)
}

/// What one trim removed, for logging and tests.
struct DiskCacheTrimReport: Sendable, Equatable {
    enum Reason: String, Sendable, CaseIterable {
        case legacyLayout, interrupted, staleVersion, superseded, expired, overBudget, emptyDirectory
    }

    var removedByReason: [Reason: Int] = [:]
    var removedBytes: Int64 = 0
    var remainingBytes: Int64 = 0
    var remainingEntries = 0
    var duration: Duration = .zero

    var removedCount: Int { removedByReason.values.reduce(0, +) }
    func removed(_ reason: Reason) -> Int { removedByReason[reason, default: 0] }
}

/// Entry names are `<prefix>-<group>-<version>-<digest>.<ext>` inside a per-asset directory.
/// `group` identifies what an entry is a variant of (mask kind and quality), `version` the
/// producing algorithm. Both are recoverable from the file name, so retention decisions never
/// open a file.
struct DiskCacheEntryName: Equatable, Sendable {
    let prefix: String
    let group: String
    let version: String
    let digest: String

    func filename(extension ext: String) -> String {
        "\(prefix)-\(group)-\(version)-\(digest).\(ext)"
    }

    /// Short stable tag for free-form key components (which may contain separators).
    static func tag(_ components: String...) -> String {
        let joined = components.joined(separator: "\u{1f}")
        return String(SHA256.hash(data: Data(joined.utf8)).hexString.prefix(10))
    }

    static func parse(_ filename: String, prefix expectedPrefix: String) -> (name: Self, ext: String)? {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let parts = url.deletingPathExtension().lastPathComponent.split(
            separator: "-", omittingEmptySubsequences: false
        )
        guard parts.count == 4, parts[0] == expectedPrefix, !ext.isEmpty,
              parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return (Self(prefix: String(parts[0]), group: String(parts[1]),
                     version: String(parts[2]), digest: String(parts[3])), ext)
    }
}

/// File-system primitives shared by the analysis and mask caches.
enum DiskCacheIO {
    /// The directory that owns every entry for one asset. Hashing keeps the name filesystem-safe
    /// and means a delete addresses the directory directly instead of searching for it.
    static func assetDirectory(in root: URL, for assetID: PortablePhotoAssetID) -> URL {
        let digest = SHA256.hash(data: Data("asset=\(assetID.raw)".utf8)).hexString
        return root.appendingPathComponent(String(digest.prefix(32)), isDirectory: true)
    }

    static func fileSize(at url: URL) -> Int64? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int64(info.st_size)
    }

    /// Reads a whole file only after its size is known to be within `maxBytes`, so a corrupt or
    /// legacy file cannot force a huge allocation.
    static func boundedData(at url: URL, maxBytes: Int64) -> Data? {
        guard let size = fileSize(at: url), size <= maxBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Reads exactly `count` Float32 values, directly into the destination array. A size mismatch
    /// is rejected from the file's metadata before any allocation.
    static func floats(at url: URL, count: Int) -> [Float]? {
        let (byteCount, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !overflow, fileSize(at: url) == Int64(byteCount) else { return nil }
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var complete = false
        let values = [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            initialized = 0
            guard let base = UnsafeMutableRawPointer(buffer.baseAddress) else { return }
            var total = 0
            while total < byteCount {
                let n = read(descriptor, base + total, byteCount - total)
                if n < 0, errno == EINTR { continue }
                if n <= 0 { return }
                total += n
            }
            complete = true
            initialized = count
        }
        return complete ? values : nil
    }

    /// Writes through a same-directory temp file and renames it into place, so a reader or an
    /// interrupted write never sees a partial entry. The temp file's `.tmp` name is not a
    /// recognized entry and is reclaimed by trim if the process dies mid-write.
    static func writeAtomically(
        _ bytes: UnsafeRawBufferPointer, to url: URL
    ) throws {
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = 0
        var offset = 0
        while offset < bytes.count, let base = bytes.baseAddress {
            let n = write(descriptor, base + offset, bytes.count - offset)
            if n < 0, errno == EINTR { continue }
            if n <= 0 { failure = errno == 0 ? EIO : errno; break }
            offset += n
        }
        if close(descriptor) != 0, failure == 0 { failure = errno }
        if failure == 0, rename(temp.path, url.path) != 0 { failure = errno }
        if failure != 0 {
            unlink(temp.path)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }

    static func writeAtomically(_ data: Data, to url: URL) throws {
        try data.withUnsafeBytes { try writeAtomically($0, to: url) }
    }

    /// Records a read as use, at most once per `minimumInterval`, so a hot entry is not
    /// rewritten on every lookup yet LRU eviction still sees it as recent.
    static func touch(_ url: URL, now: Date, minimumInterval: TimeInterval = 3600) {
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate,
            now.timeIntervalSince(modified) > minimumInterval else { return }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
}

/// One traversal that enforces a `DiskCacheBudget` over a root of per-asset directories.
enum DiskCacheTrimmer {
    struct Configuration: Sendable {
        let prefix: String
        /// Extensions that together make a complete entry (`["json", "bin"]` for masks).
        let requiredExtensions: [String]
        var budget: DiskCacheBudget
        /// When set, an entry whose version tag differs is stale regardless of age.
        var liveVersion: String?
    }

    private struct Entry {
        let name: DiskCacheEntryName
        let directory: URL
        var files: [String: (bytes: Int64, modified: Date)] = [:]

        var bytes: Int64 { files.values.reduce(0) { $0 + $1.bytes } }
        var modified: Date { files.values.map(\.modified).max() ?? .distantPast }
    }

    static func trim(
        root: URL,
        configuration: Configuration,
        now: Date,
        clock: ContinuousClock = ContinuousClock()
    ) async throws -> DiskCacheTrimReport {
        let start = clock.now
        var report = DiskCacheTrimReport()
        let fm = FileManager.default
        let budget = configuration.budget
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let children = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(keys), options: []
        ) else { return report }

        func remove(_ url: URL, bytes: Int64, reason: DiskCacheTrimReport.Reason, count: Bool = true) {
            guard (try? fm.removeItem(at: url)) != nil else { return }
            report.removedBytes += bytes
            if count { report.removedByReason[reason, default: 0] += 1 }
        }

        var survivors: [Entry] = []
        for child in children {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: keys)
            if values?.isDirectory != true {
                // The previous flat layout: unreachable by the per-asset lookup, so reclaim it
                // without decoding (a legacy mask's metadata may embed hundreds of MB of floats).
                guard child.lastPathComponent.hasPrefix(configuration.prefix + "-") else { continue }
                remove(child, bytes: Int64(values?.fileSize ?? 0), reason: .legacyLayout)
                continue
            }
            let removedBefore = report.removedByReason.values.reduce(0, +)
            var entries: [String: Entry] = [:]
            var newestInDirectory = values?.contentModificationDate ?? .distantPast
            let files = (try? fm.contentsOfDirectory(
                at: child, includingPropertiesForKeys: Array(keys), options: []
            )) ?? []
            for file in files {
                let fileValues = try? file.resourceValues(forKeys: keys)
                let bytes = Int64(fileValues?.fileSize ?? 0)
                let modified = fileValues?.contentModificationDate ?? now
                newestInDirectory = max(newestInDirectory, modified)
                guard let parsed = DiskCacheEntryName.parse(
                    file.lastPathComponent, prefix: configuration.prefix
                ), configuration.requiredExtensions.contains(parsed.ext) else {
                    if now.timeIntervalSince(modified) > budget.interruptedWriteGrace {
                        remove(file, bytes: bytes, reason: .interrupted)
                    }
                    continue
                }
                let stem = file.deletingPathExtension().lastPathComponent
                var entry = entries[stem] ?? Entry(name: parsed.name, directory: child)
                entry.files[parsed.ext] = (bytes, modified)
                entries[stem] = entry
            }

            func drop(_ stem: String, _ entry: Entry, _ reason: DiskCacheTrimReport.Reason) {
                var first = true
                for (ext, file) in entry.files {
                    remove(entry.directory.appendingPathComponent("\(stem).\(ext)"),
                           bytes: file.bytes, reason: reason, count: first)
                    first = false
                }
            }

            var kept: [(stem: String, entry: Entry)] = []
            for (stem, entry) in entries {
                let complete = configuration.requiredExtensions.allSatisfy { entry.files[$0] != nil }
                let age = now.timeIntervalSince(entry.modified)
                if !complete {
                    if age > budget.interruptedWriteGrace {
                        drop(stem, entry, .interrupted)
                    } else {
                        kept.append((stem, entry))
                    }
                } else if let live = configuration.liveVersion, entry.name.version != live {
                    drop(stem, entry, .staleVersion)
                } else if age > budget.maxAge {
                    drop(stem, entry, .expired)
                } else {
                    kept.append((stem, entry))
                }
            }

            // Within one group, a complete entry that a newer sibling has replaced (a source,
            // provider, or version change) goes once it has gone unused for the grace period.
            // Reads refresh recency, so an identity still in use is never superseded.
            let complete = kept.filter { item in
                configuration.requiredExtensions.allSatisfy { item.entry.files[$0] != nil }
            }
            let newestByGroup = Dictionary(grouping: complete, by: \.entry.name.group)
                .mapValues { $0.map(\.entry.modified).max() ?? .distantPast }
            for item in complete {
                guard let newest = newestByGroup[item.entry.name.group],
                      item.entry.modified < newest,
                      now.timeIntervalSince(item.entry.modified) > budget.supersededGrace
                else { continue }
                drop(item.stem, item.entry, .superseded)
                kept.removeAll { $0.stem == item.stem }
            }

            // An empty directory is reclaimed once this pass emptied it, or once it has sat empty
            // past the grace period; a brand-new one may be about to receive a write.
            let emptiedHere = report.removedByReason.values.reduce(0, +) > removedBefore
            if kept.isEmpty,
               emptiedHere || now.timeIntervalSince(newestInDirectory) > budget.interruptedWriteGrace,
               (try? fm.contentsOfDirectory(atPath: child.path))?.isEmpty ?? true {
                remove(child, bytes: 0, reason: .emptyDirectory)
            }
            survivors.append(contentsOf: kept.map(\.entry))
            // Yield between asset directories so a large cache never monopolizes the actor or
            // delays visible work queued behind it.
            await Task.yield()
        }

        var total = survivors.reduce(Int64(0)) { $0 + $1.bytes }
        var remaining = survivors.count
        if total > budget.maxBytes {
            for entry in survivors.sorted(by: { $0.modified < $1.modified }) {
                try Task.checkCancellation()
                guard total > budget.maxBytes else { break }
                var first = true
                for (ext, file) in entry.files {
                    remove(entry.directory.appendingPathComponent(entry.name.filename(extension: ext)),
                           bytes: file.bytes, reason: .overBudget, count: first)
                    first = false
                }
                total -= entry.bytes
                remaining -= 1
            }
        }
        report.remainingBytes = max(0, total)
        report.remainingEntries = remaining
        report.duration = start.duration(to: clock.now)
        return report
    }
}
