import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// The durable cache for the final, display-referred preview raster.
///
/// This deliberately stores one canonical long-edge size rather than a raster for every window
/// size. The presentation surface already fits the image, so a 2048px long edge is a stable,
/// visually lossless preview target while keeping one entry per source/document/look.
struct PreviewDiskCache: Sendable {
    static let canonicalLongEdge = 2048
    static let defaultCapBytes: Int64 = 1_000_000_000

    struct Key: Hashable, Sendable {
        let sourceFingerprint: String
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
            self.sourceFingerprint = sourceFingerprint
            self.documentHash = documentHash
            self.lookFingerprint = lookFingerprint
            self.targetSizeBucket = targetSizeBucket
            self.space = space.rawValue
            self.pipelineVersion = pipelineVersion
        }

        var canonicalKeyString: String {
            [sourceFingerprint, documentHash, lookFingerprint, targetSizeBucket, space,
             String(pipelineVersion)].joined(separator: "|")
        }
    }

    let directory: URL
    let capBytes: Int64
    private let pipelineVersion: Int

    init(
        directory: URL = PreviewDiskCache.defaultDirectory(),
        capBytes: Int64 = PreviewDiskCache.defaultCapBytes,
        pipelineVersion: Int = RenderPipeline.cacheVersion
    ) {
        self.directory = directory
        self.capBytes = max(0, capBytes)
        self.pipelineVersion = pipelineVersion
        prepareDirectory(at: directory)
        enforceCap()
    }

    /// A missing, malformed, or stale entry is always a cache miss. Preview rendering must never
    /// fail because a cache file was truncated, removed, or written by an older pipeline.
    func read(for key: Key) -> CGImage? {
        let url = fileURL(for: key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        // File modification time is the LRU signal. A failed touch is harmless; the image is still
        // a valid exact-key hit.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: url.path
        )
        return image
    }

    /// Checks for an exact-key entry without decoding its pixels. The key includes the source,
    /// document, look, target bucket, working space, and pipeline version, so a file hit is a fresh
    /// entry for the caller's render identity. Malformed files remain harmless: the eventual read
    /// path treats them as misses and the next write replaces them.
    func contains(_ key: Key) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    /// Encodes JPEG data first and then replaces the destination with Foundation's atomic write.
    /// All errors are intentionally swallowed: disk caching is an optimization, never a render
    /// prerequisite.
    func write(_ image: CGImage, for key: Key) {
        guard !Task.isCancelled,
              let data = Self.jpegData(for: image) else { return }
        let url = fileURL(for: key)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: url.path
            )
            enforceCap()
        } catch {
            // The cache must not affect the settled presentation path.
        }
    }

    /// Invalidate persisted preview rasters after a library deletion. Preview keys intentionally
    /// use source fingerprints rather than asset IDs, so the cache cannot cheaply map old entries
    /// back to one source. Removing the rasters is safe and leaves the version marker intact.
    func invalidateAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Turns an already-presented image into the cache's canonical upright raster. Callers only
    /// invoke this for a full settled frame; ROI/zoom frames are deliberately not disk-cacheable.
    static func canonicalRaster(from image: CIImage, space: WorkingSpace) -> CGImage? {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0,
              extent.width.isFinite, extent.height.isFinite else { return nil }
        let context = CIContext(options: [.workingColorSpace: space.cgColorSpace])
        guard let source = context.createCGImage(
            image, from: extent, format: .RGBA8, colorSpace: space.cgColorSpace
        ) else { return nil }

        let scale = CGFloat(canonicalLongEdge) / CGFloat(max(source.width, source.height))
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        let colorSpace = space.cgColorSpace
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        bitmap.interpolationQuality = CGInterpolationQuality.high
        bitmap.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap.makeImage()
    }

    static func defaultDirectory() -> URL {
        KromoraStorage.applicationSupportRoot()
            .appendingPathComponent("DevelopedPreviews", isDirectory: true)
    }

    private static let versionFileName = "version"
    private static let filePrefix = "preview-"

    private func fileURL(for key: Key) -> URL {
        let digest = SHA256.hash(data: Data(key.canonicalKeyString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(Self.filePrefix)\(digest).jpg")
    }

    private func prepareDirectory(at directory: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let versionURL = directory.appendingPathComponent(Self.versionFileName)
            let current = try? String(contentsOf: versionURL, encoding: .utf8)
            if current?.trimmingCharacters(in: .whitespacesAndNewlines)
                != String(pipelineVersion) {
                for url in try fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil
                ) {
                    try? fileManager.removeItem(at: url)
                }
                try String(pipelineVersion).write(
                    to: versionURL, atomically: true, encoding: .utf8
                )
            }
        } catch {
            // A later read/write will continue to treat the directory as an unavailable cache.
        }
    }

    private func enforceCap() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard url.pathExtension.lowercased() == "jpg",
                  let values = try? url.resourceValues(
                      forKeys: [.fileSizeKey, .contentModificationDateKey]
                  ),
                  let size = values.fileSize.map(Int64.init) else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        entries.sort { $0.2 < $1.2 }
        while total > capBytes, let oldest = entries.first {
            entries.removeFirst()
            try? fileManager.removeItem(at: oldest.0)
            total -= oldest.1
        }
    }

    private static func jpegData(for image: CGImage) -> Data? {
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
}
