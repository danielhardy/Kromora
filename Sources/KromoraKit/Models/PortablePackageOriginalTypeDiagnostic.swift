import Foundation

/// An embedded original whose bytes are positively identified as incompatible with its stored
/// filename extension, such as JPEG bytes named `DSC00160.ARW` (KRMA-1031, KRMA-1036).
struct PortablePackageOriginalTypeFinding: Equatable, Sendable, Identifiable {
    let assetID: PortablePhotoAssetID
    let displayName: String
    /// Package-relative path of the stored original.
    let relativePath: String
    let detectedFormat: String
    let isRAWName: Bool

    var id: String { assetID.raw }

    var message: String {
        let what = isRAWName
            ? "holds \(detectedFormat) image data, not RAW"
            : "holds \(detectedFormat) data that does not match its file extension"
        return "\(displayName) \(what)."
    }

    /// The recovery path. The diagnostic never changes the stored original.
    var guidance: String {
        isRAWName
            ? "Kromora did not change this file. To get the real RAW, remove this photo from the "
                + "library and import the original from Photos again; the import now reads the "
                + "original resource rather than an edited copy."
            : "Kromora did not change this file. Re-import the original from Photos or its source "
                + "folder to replace it."
    }
}

struct PortablePackageOriginalTypeReport: Equatable, Sendable {
    let assetsScanned: Int
    let findings: [PortablePackageOriginalTypeFinding]
}

/// A read-only scan for originals imported before import-time type validation. It reads only each
/// original's leading bytes, and the whole file only when a RAW-named TIFF header needs ImageIO to
/// tell RAW from plain TIFF. It never hashes, rewrites, or deletes anything.
enum PortablePackageOriginalTypeDiagnostic {
    private static let headLength = 16

    static func run(
        package: PortableLibraryPackage,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> PortablePackageOriginalTypeReport {
        var scanned = 0
        var findings: [PortablePackageOriginalTypeFinding] = []
        for shard in PortableLibraryPackage.allShards {
            if isCancelled() { throw CancellationError() }
            guard let membership = try? package.readMembershipShard(shard) else { continue }
            for entry in membership.entries where !entry.isTombstone {
                if isCancelled() { throw CancellationError() }
                guard let url = try? package.verifiedEmbeddedSourceURL(
                    for: entry.assetID, displayName: entry.summary.displayName
                ), let handle = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? handle.close() }
                scanned += 1
                let name = url.lastPathComponent
                guard var data = try? handle.read(upToCount: headLength) else { continue }
                if OriginalFileTypeCheck.needsFullData(name: name, head: data) {
                    try? handle.seek(toOffset: 0)
                    guard let full = try? handle.readToEnd() else { continue }
                    data = full
                }
                guard let mismatch = OriginalFileTypeCheck.mismatch(name: name, data: data) else {
                    continue
                }
                findings.append(.init(
                    assetID: entry.assetID,
                    displayName: entry.summary.displayName,
                    relativePath: relativePath(of: url, in: package.rootURL),
                    detectedFormat: mismatch.detected,
                    isRAWName: mismatch.isRAWName
                ))
            }
        }
        return .init(assetsScanned: scanned, findings: findings)
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }
}

extension PortableLibraryPackage {
    /// Lists originals whose bytes disagree with their stored extension. Read-only.
    func scanOriginalFileTypes(
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> PortablePackageOriginalTypeReport {
        try PortablePackageOriginalTypeDiagnostic.run(package: self, isCancelled: isCancelled)
    }
}
