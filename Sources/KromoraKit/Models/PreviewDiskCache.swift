import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Durable cache for the final, display-referred preview raster.
///
/// Construction performs no filesystem scan. The first asynchronous cache operation loads one
/// in-memory size/LRU index; subsequent writes update that index incrementally.
struct PreviewDiskCache: Sendable {
    static let canonicalLongEdge = 2048
    static let defaultCapBytes: Int64 = 1_000_000_000

    struct Key: Hashable, Sendable {
        let identity: PortablePhotoIdentity
        let documentHash: String
        let lookFingerprint: String
        let targetSizeBucket: String
        let space: String
        let pipelineVersion: Int

        init(
            sourceFingerprint: String,
            documentHash: String,
            lookFingerprint: String,
            targetSizeBucket: String = String(PreviewDiskCache.canonicalLongEdge),
            space: WorkingSpace = .current,
            pipelineVersion: Int = RenderPipeline.cacheVersion
        ) {
            self.identity = .compatibility(
                assetID: PhotoAssetID(rawValue: "preview-source:\(sourceFingerprint)"),
                sourceFingerprint: PhotoSourceFingerprint.data(Data(sourceFingerprint.utf8))
            )
            self.documentHash = documentHash
            self.lookFingerprint = lookFingerprint
            self.targetSizeBucket = targetSizeBucket
            self.space = space.rawValue
            self.pipelineVersion = pipelineVersion
        }

        init(
            identity: PortablePhotoIdentity,
            documentHash: String,
            lookFingerprint: String,
            targetSizeBucket: String = String(PreviewDiskCache.canonicalLongEdge),
            space: WorkingSpace = .current,
            pipelineVersion: Int = RenderPipeline.cacheVersion
        ) {
            self.identity = identity
            self.documentHash = documentHash
            self.lookFingerprint = lookFingerprint
            self.targetSizeBucket = targetSizeBucket
            self.space = space.rawValue
            self.pipelineVersion = pipelineVersion
        }

        var canonicalKeyString: String {
            [identity.cacheKey, documentHash, lookFingerprint, targetSizeBucket, space,
             String(pipelineVersion)].joined(separator: "|")
        }
    }

    let directory: URL
    let capBytes: Int64
    private let pipelineVersion: Int
    private let writer: PreviewDiskCacheWriter

    init(
        directory: URL,
        capBytes: Int64 = PreviewDiskCache.defaultCapBytes,
        pipelineVersion: Int = RenderPipeline.cacheVersion
    ) {
        self.directory = directory
        self.capBytes = max(0, capBytes)
        self.pipelineVersion = pipelineVersion
        self.writer = PreviewDiskCacheWriter(
            directory: directory, capBytes: max(0, capBytes), pipelineVersion: pipelineVersion
        )
    }

    func readAsync(for key: Key) async -> CGImage? { await writer.read(for: key) }
    func containsAsync(_ key: Key) async -> Bool { await writer.contains(key) }

    /// Queue a serialized, coalescing write. A later write for the same key cancels the older
    /// pending job before it reaches the filesystem.
    func enqueueWrite(_ image: sending CGImage, for key: Key) async {
        await writer.enqueue(image, for: key)
    }

    func invalidate(identities: Set<PortablePhotoIdentity>) async {
        await writer.invalidate(identities: identities)
    }

    func cancelPendingWrites() async { await writer.cancelAll() }

    // MARK: Compatibility/test seams

    /// Synchronous compatibility seam for existing model tests and non-production callers. The
    /// presentation path uses `enqueueWrite`, which never scans the directory per write.
    func write(_ image: CGImage, for key: Key) {
        guard let data = Self.jpegData(for: image) else { return }
        do {
            try Self.prepareDirectorySynchronously(at: directory, pipelineVersion: pipelineVersion)
            let url = Self.fileURL(for: key, in: directory)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: url.path
            )
            Self.enforceCapSynchronously(in: directory, capBytes: capBytes)
        } catch {
            // Disk caching is an optimization and never a render prerequisite.
        }
    }

    /// Synchronous read retained for existing callers. Preview presentation uses `readAsync`.
    func read(for key: Key) -> CGImage? {
        guard prepareForSynchronousAccess() else { return nil }
        let url = Self.fileURL(for: key, in: directory)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: url.path
        )
        return image
    }

    func contains(_ key: Key) -> Bool {
        guard prepareForSynchronousAccess() else { return false }
        return FileManager.default.fileExists(atPath: Self.fileURL(for: key, in: directory).path)
    }

    /// Legacy broad invalidation remains only for compatibility. Production deletion calls the
    /// identity-scoped async method above.
    func invalidateAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Test-only compatibility for callers that still build a raster from a CIImage directly.
    /// Production preview rasterization goes through `RenderEngining.makeCanonicalPreviewRaster`.
    static func canonicalRaster(from image: CIImage, space: WorkingSpace) -> CGImage? {
        RenderEngineResources.canonicalPreviewRaster(
            from: image, space: space, longEdge: canonicalLongEdge
        )
    }

    static func packageDirectory(for packageURL: URL) -> URL {
        KromoraStorage.packageDerivedDirectory(named: "Previews", under: packageURL)
    }

    fileprivate static let versionFileName = "version"
    fileprivate static let filePrefix = "preview-"
    fileprivate static let cacheFormatVersion = 3

    fileprivate static func assetPrefix(for identity: PortablePhotoIdentity) -> String {
        // Keep every source revision for one portable asset under the same prefix. Deletion must
        // also remove previews made before an in-place source replacement changed its fingerprint.
        SHA256.hash(data: Data(identity.assetID.raw.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func fileURL(for key: Key, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(key.canonicalKeyString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let asset = assetPrefix(for: key.identity)
        return directory.appendingPathComponent("\(filePrefix)\(asset)-\(digest).jpg")
    }

    fileprivate static func jpegData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func expectedVersion(_ pipelineVersion: Int) -> String {
        "\(pipelineVersion):\(cacheFormatVersion)"
    }

    private static func prepareDirectorySynchronously(
        at directory: URL, pipelineVersion: Int
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let versionURL = directory.appendingPathComponent(versionFileName)
        let current = try? String(contentsOf: versionURL, encoding: .utf8)
        guard current?.trimmingCharacters(in: .whitespacesAndNewlines)
            != expectedVersion(pipelineVersion) else { return }
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try? fileManager.removeItem(at: url)
        }
        try expectedVersion(pipelineVersion).write(
            to: versionURL, atomically: true, encoding: .utf8
        )
    }

    private func prepareForSynchronousAccess() -> Bool {
        do {
            try Self.prepareDirectorySynchronously(at: directory, pipelineVersion: pipelineVersion)
            return true
        } catch {
            return false
        }
    }

    private static func enforceCapSynchronously(in directory: URL, capBytes: Int64) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard url.pathExtension.lowercased() == "jpg",
                  let values = try? url.resourceValues(
                      forKeys: [.fileSizeKey, .contentModificationDateKey]
                  ), let size = values.fileSize.map(Int64.init) else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        entries.sort { $0.2 < $1.2 }
        while total > capBytes, let oldest = entries.first {
            entries.removeFirst()
            try? FileManager.default.removeItem(at: oldest.0)
            total -= oldest.1
        }
    }
}

private actor PreviewDiskCacheWriter {
    private struct Entry {
        let url: URL
        let size: Int64
        let assetPrefix: String?
        var lastAccess: Date
    }

    private let directory: URL
    private let capBytes: Int64
    private let pipelineVersion: Int
    private var entries: [String: Entry] = [:]
    private var totalBytes: Int64 = 0
    private var didLoadIndex = false
    private var pending: [String: Task<Void, Never>] = [:]
    private var pendingAssetPrefixes: [String: String] = [:]

    init(directory: URL, capBytes: Int64, pipelineVersion: Int) {
        self.directory = directory
        self.capBytes = capBytes
        self.pipelineVersion = pipelineVersion
    }

    func enqueue(_ image: sending CGImage, for key: PreviewDiskCache.Key) {
        let identifier = key.canonicalKeyString
        pending[identifier]?.cancel()
        pendingAssetPrefixes[identifier] = PreviewDiskCache.assetPrefix(for: key.identity)
        pending[identifier] = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.write(image, for: key)
            await self.finished(identifier)
        }
    }

    func read(for key: PreviewDiskCache.Key) -> CGImage? {
        guard loadIndex() else { return nil }
        let name = PreviewDiskCache.fileURL(for: key, in: directory).lastPathComponent
        guard let entry = entries[name],
              let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        touch(name)
        return image
    }

    func contains(_ key: PreviewDiskCache.Key) -> Bool {
        guard loadIndex() else { return false }
        return entries[PreviewDiskCache.fileURL(for: key, in: directory).lastPathComponent] != nil
    }

    func invalidate(identities: Set<PortablePhotoIdentity>) {
        guard loadIndex(), !identities.isEmpty else { return }
        let prefixes = Set(identities.map(PreviewDiskCache.assetPrefix))
        for identifier in pendingAssetPrefixes.keys
            where prefixes.contains(pendingAssetPrefixes[identifier] ?? "") {
            pending[identifier]?.cancel()
            pending.removeValue(forKey: identifier)
            pendingAssetPrefixes.removeValue(forKey: identifier)
        }
        let victims = entries.filter { prefixes.contains($0.value.assetPrefix ?? "") }
        for (name, entry) in victims {
            try? FileManager.default.removeItem(at: entry.url)
            entries.removeValue(forKey: name)
            totalBytes -= entry.size
        }
    }

    func cancelAll() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
        pendingAssetPrefixes.removeAll()
    }

    private func finished(_ identifier: String) {
        pending.removeValue(forKey: identifier)
        pendingAssetPrefixes.removeValue(forKey: identifier)
    }

    private func write(_ image: sending CGImage, for key: PreviewDiskCache.Key) {
        guard !Task.isCancelled, loadIndex(), let data = PreviewDiskCache.jpegData(for: image)
        else { return }
        let url = PreviewDiskCache.fileURL(for: key, in: directory)
        do {
            try data.write(to: url, options: .atomic)
            let now = Date()
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
            let name = url.lastPathComponent
            if let old = entries.updateValue(
                Entry(
                    url: url, size: Int64(data.count),
                    assetPrefix: PreviewDiskCache.assetPrefix(for: key.identity), lastAccess: now
                ), forKey: name
            ) {
                totalBytes -= old.size
            }
            totalBytes += Int64(data.count)
            enforceCapIncrementally()
        } catch {
            // Disk caching is an optimization and never a render prerequisite.
        }
    }

    private func touch(_ name: String) {
        guard var entry = entries[name] else { return }
        let now = Date()
        entry.lastAccess = now
        entries[name] = entry
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: entry.url.path)
    }

    private func enforceCapIncrementally() {
        while totalBytes > capBytes, let oldest = entries.min(by: {
            $0.value.lastAccess < $1.value.lastAccess
        }) {
            try? FileManager.default.removeItem(at: oldest.value.url)
            entries.removeValue(forKey: oldest.key)
            totalBytes -= oldest.value.size
        }
    }

    @discardableResult
    private func loadIndex() -> Bool {
        if didLoadIndex { return true }
        didLoadIndex = true
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let versionURL = directory.appendingPathComponent(PreviewDiskCache.versionFileName)
            let expected = "\(pipelineVersion):\(PreviewDiskCache.cacheFormatVersion)"
            let current = try? String(contentsOf: versionURL, encoding: .utf8)
            if current?.trimmingCharacters(in: .whitespacesAndNewlines) != expected {
                for url in try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil
                ) { try? FileManager.default.removeItem(at: url) }
                try expected.write(to: versionURL, atomically: true, encoding: .utf8)
            }
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for url in files where url.pathExtension.lowercased() == "jpg" {
                guard let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                ), let size = values.fileSize.map(Int64.init) else { continue }
                let components = url.deletingPathExtension().lastPathComponent.split(separator: "-")
                let assetPrefix = components.count >= 3 && components[0] == "preview"
                    ? String(components[1]) : nil
                entries[url.lastPathComponent] = Entry(
                    url: url, size: size, assetPrefix: assetPrefix,
                    lastAccess: values.contentModificationDate ?? .distantPast
                )
                totalBytes += size
            }
            enforceCapIncrementally()
            return true
        } catch {
            return false
        }
    }
}
