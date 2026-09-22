import Foundation

/// Disposable packed-thumbnail spike used only by benchmark and correctness tests.
///
/// This deliberately has no product-facing API. A pack is a concatenation of thumbnail bytes;
/// the single JSON index records the shard, byte offset, and length for the current value of each
/// key. Replacing a key appends a new value and leaves the old bytes stale until compaction.
final class PackedThumbnailStore {

    struct Record: Sendable {
        let key: String
        let data: Data
    }

    enum LookupResult: Equatable {
        case found(Data)
        case missing
        case stale
    }

    struct ScanResult: Equatable {
        let indexedEntries: Int
        let validEntries: Int
        let staleEntries: Int
    }

    struct CompactionResult: Equatable {
        let bytesBefore: Int
        let bytesAfter: Int
        let indexedEntriesBefore: Int
        let indexedEntriesAfter: Int
        let staleEntriesRemoved: Int
    }

    private struct Entry: Codable, Equatable {
        let key: String
        let shard: Int
        var offset: UInt64
        var length: UInt64
    }

    private struct IndexFile: Codable {
        let schemaVersion: Int
        let entries: [Entry]
    }

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let indexURL: URL
    private var entries: [String: Entry]

    init(at rootURL: URL) throws {
        self.rootURL = rootURL
        self.indexURL = rootURL.appendingPathComponent("index.json")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: indexURL.path) {
            let index = try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: indexURL))
            guard index.schemaVersion == 1 else {
                throw PrototypeError.invalidIndex("unsupported packed index schema")
            }
            self.entries = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.key, $0) })
        } else {
            self.entries = [:]
        }
    }

    var liveEntryCount: Int { entries.count }

    var physicalFileCount: Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        return urls.reduce(into: 0) { count, url in
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
    }

    var physicalByteCount: Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        return urls.reduce(into: 0) { total, url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return }
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    func append(_ record: Record) throws {
        try append(records: [record])
    }

    func append(records: [Record]) throws {
        for record in records {
            let shard = Self.shard(for: record.key)
            let packURL = packURL(for: shard)
            if !fileManager.fileExists(atPath: packURL.path) {
                try Data().write(to: packURL)
            }

            let handle = try FileHandle(forWritingTo: packURL)
            defer { try? handle.close() }
            let offset = try handle.seekToEnd()
            try handle.write(contentsOf: record.data)
            entries[record.key] = Entry(
                key: record.key,
                shard: shard,
                offset: offset,
                length: UInt64(record.data.count)
            )
        }
        try saveIndex()
    }

    func remove(keys: [String]) throws {
        for key in keys { entries.removeValue(forKey: key) }
        try saveIndex()
    }

    func lookup(_ key: String) throws -> LookupResult {
        guard let entry = entries[key] else { return .missing }
        guard entry.shard == Self.shard(for: key),
              let values = try? packURL(for: entry.shard).resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              entry.offset <= UInt64(fileSize),
              entry.length <= UInt64(fileSize) - entry.offset,
              let length = Int(exactly: entry.length) else {
            return .stale
        }
        do {
            let handle = try FileHandle(forReadingFrom: packURL(for: entry.shard))
            defer { try? handle.close() }
            handle.seek(toFileOffset: entry.offset)
            guard let data = try handle.read(upToCount: length), data.count == length else {
                return .stale
            }
            return .found(data)
        } catch {
            return .stale
        }
    }

    /// Validate offsets without reading every thumbnail payload. This is the packed cold-scan
    /// shape: one index decode and one size lookup per shard, rather than one directory item per
    /// thumbnail.
    func coldScan() throws -> ScanResult {
        var packSizes: [Int: UInt64] = [:]
        for shard in 0..<256 {
            let url = packURL(for: shard)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            packSizes[shard] = UInt64(values.fileSize ?? 0)
        }

        let stale = entries.values.reduce(into: 0) { count, entry in
            guard let size = packSizes[entry.shard],
                  entry.offset <= size,
                  entry.length <= size - entry.offset else {
                count += 1
                return
            }
        }
        return ScanResult(
            indexedEntries: entries.count,
            validEntries: entries.count - stale,
            staleEntries: stale
        )
    }

    /// Rewrites only the currently valid values, dropping stale/replaced/deleted bytes and
    /// removing dangling index entries. The result makes space reclamation measurable.
    func compact() throws -> CompactionResult {
        let bytesBefore = physicalByteCount
        let indexedEntriesBefore = entries.count
        var compactedEntries: [String: Entry] = [:]
        var validByShard: [Int: [(String, Data)]] = [:]
        var staleEntries = 0

        for entry in entries.values {
            switch try lookup(entry.key) {
            case .found(let data):
                validByShard[entry.shard, default: []].append((entry.key, data))
            case .missing, .stale:
                staleEntries += 1
            }
        }

        for shard in 0..<256 {
            let destination = packURL(for: shard)
            let values = (validByShard[shard] ?? []).sorted { $0.0 < $1.0 }
            if values.isEmpty {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                continue
            }

            let temporary = rootURL.appendingPathComponent(
                String(format: "%02x.pack.compact-%@", shard, UUID().uuidString),
                isDirectory: false
            )
            var offset: UInt64 = 0
            var output = Data()
            for (key, data) in values {
                output.append(data)
                compactedEntries[key] = Entry(
                    key: key, shard: shard, offset: offset, length: UInt64(data.count)
                )
                offset += UInt64(data.count)
            }
            try output.write(to: temporary, options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
        }

        entries = compactedEntries
        try saveIndex()
        return CompactionResult(
            bytesBefore: bytesBefore,
            bytesAfter: physicalByteCount,
            indexedEntriesBefore: indexedEntriesBefore,
            indexedEntriesAfter: entries.count,
            staleEntriesRemoved: staleEntries
        )
    }

    /// Test-only corruption hook for deterministic stale-offset coverage.
    func injectStalePackedThumbnailEntry(key: String) throws {
        let shard = Self.shard(for: key)
        entries[key] = Entry(key: key, shard: shard, offset: UInt64.max, length: 1)
        try saveIndex()
    }

    private func saveIndex() throws {
        let index = IndexFile(schemaVersion: 1, entries: entries.values.sorted { $0.key < $1.key })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private func packURL(for shard: Int) -> URL {
        rootURL.appendingPathComponent(String(format: "%02x.pack", shard))
    }

    private static func shard(for key: String) -> Int {
        let bytes = Array(key.utf8)
        if bytes.count >= 2,
           let first = hexValue(bytes[0]), let second = hexValue(bytes[1]) {
            return first * 16 + second
        }
        var hash: UInt8 = 216
        for byte in bytes { hash = hash &* 31 &+ byte }
        return Int(hash)
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: return Int(byte - 48)
        case 65...70: return Int(byte - 65 + 10)
        case 97...102: return Int(byte - 97 + 10)
        default: return nil
        }
    }
}

final class PerFileThumbnailStore {
    private let fileManager = FileManager.default
    private let rootURL: URL

    init(at rootURL: URL) throws {
        self.rootURL = rootURL
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func append(records: [PackedThumbnailStore.Record]) throws {
        for record in records {
            try record.data.write(to: fileURL(for: record.key), options: .atomic)
        }
    }

    func remove(keys: [String]) throws {
        for key in keys {
            let url = fileURL(for: key)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }

    func lookup(_ key: String) throws -> Data? {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// A per-file layout has no separate compaction rewrite: deleting a file reclaims its bytes.
    /// The scan is retained as a comparable maintenance cost and verifies the remaining entries.
    func coldScan() throws -> Int {
        try fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ).reduce(into: 0) { count, url in
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
    }

    var physicalFileCount: Int { (try? coldScan()) ?? 0 }

    var physicalByteCount: Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        return urls.reduce(into: 0) { total, url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return }
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    private func fileURL(for key: String) -> URL {
        rootURL.appendingPathComponent(key + ".thumb")
    }
}

enum PrototypeError: Error, CustomStringConvertible {
    case invalidIndex(String)

    var description: String {
        switch self { case .invalidIndex(let message): return message }
    }
}
