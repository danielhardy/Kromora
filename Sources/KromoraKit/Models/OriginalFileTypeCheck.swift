import Foundation

/// Detects an imported original whose filename extension disagrees with its bytes, such as an
/// edited JPEG rendition stored under a RAW filename (KRMA-1031). Detection is by magic bytes and
/// deliberately conservative: it only reports a mismatch when the bytes are positively identified.
enum OriginalFileTypeCheck {
    enum Container: Equatable, Sendable {
        case jpeg, png
        /// ISO base media (HEIC/AVIF/CR3 share it); `isCanonRAW` is the `crx ` brand.
        case isoBase(isCanonRAW: Bool)
        /// TIFF byte-order header: TIFF itself and most RAW formats (ARW, DNG, NEF, CR2, ...).
        case tiffBased
        case otherRAW
        case unknown
    }

    static func container(of data: Data) -> Container {
        let head = [UInt8](data.prefix(16))
        guard head.count >= 4 else { return .unknown }
        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return .jpeg }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if head.starts(with: [0x49, 0x49, 0x2A, 0x00]) || head.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
            || head.starts(with: [0x49, 0x49, 0x55, 0x00]) || head.starts(with: [0x49, 0x49, 0x52, 0x4F])
            || head.starts(with: [0x49, 0x49, 0x52, 0x53]) {
            return .tiffBased
        }
        if head.count >= 12, head[4...7].elementsEqual([0x66, 0x74, 0x79, 0x70]) {
            return .isoBase(isCanonRAW: head[8...11].elementsEqual(Array("crx ".utf8)))
        }
        if head.starts(with: Array("FUJIFILMCCD-RAW".utf8)) || head.starts(with: Array("FOVb".utf8)) {
            return .otherRAW
        }
        return .unknown
    }

    /// A user-facing reason when `name`'s extension cannot describe `data`, else nil.
    static func mismatchReason(name: String, data: Data) -> String? {
        guard let mismatch = mismatch(name: name, data: data) else { return nil }
        if mismatch.isRAWName {
            return "\(name) holds \(mismatch.detected) image data, not RAW. Photos supplied an edited or "
                + "rendered copy instead of the original, so it was not imported."
        }
        return "\(name) holds \(mismatch.detected) data that does not match its file extension."
    }

    struct Mismatch: Equatable, Sendable {
        /// The positively identified format: "JPEG", "PNG", "HEIF", or "TIFF".
        let detected: String
        /// The extension claims RAW, so the bytes are a non-RAW rendition.
        let isRAWName: Bool
    }

    /// Whether classifying `name` needs more than the leading bytes: TIFF is a RAW container too,
    /// so a RAW-named TIFF-header file is only confirmed by ImageIO over the whole file.
    static func needsFullData(name: String, head: Data) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ImageDecoder.rawExtensions.contains(ext) && container(of: head) == .tiffBased
    }

    /// The positively identified incompatibility between `name`'s extension and `data`, else nil.
    /// `data` may be only the leading bytes unless `needsFullData(name:head:)` is true.
    static func mismatch(name: String, data: Data) -> Mismatch? {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        let container = container(of: data)
        let isRAWName = ImageDecoder.rawExtensions.contains(ext)

        // TIFF is only a container: ordinary TIFF photos and camera RAWs share the same byte-order
        // header. Confirm TIFF-based files with the same ImageIO/CIRAWFilter path used by the
        // editor before accepting a RAW extension.
        if isRAWName, container == .tiffBased, ImageSource.kind(forData: data) != .raw {
            return Mismatch(detected: "TIFF", isRAWName: true)
        }

        let detected: String
        switch container {
        case .jpeg: detected = "JPEG"
        case .png: detected = "PNG"
        case .isoBase(let isCanonRAW): detected = isCanonRAW ? "" : "HEIF"
        case .tiffBased, .otherRAW, .unknown: detected = ""
        }
        guard !detected.isEmpty else { return nil }

        if isRAWName { return Mismatch(detected: detected, isRAWName: true) }
        let expected: [String: Set<String>] = [
            "JPEG": ["jpg", "jpeg"], "PNG": ["png"], "HEIF": ["heic", "heif"],
        ]
        if let allowed = expected[detected], !allowed.contains(ext) {
            return Mismatch(detected: detected, isRAWName: false)
        }
        return nil
    }

    /// A user-facing reason when the file at `url` holds bytes its extension cannot describe, else
    /// nil. Reads only the leading bytes unless a TIFF-header RAW name needs the whole file.
    /// Unreadable files return nil so the ordinary import path reports the read failure.
    static func mismatchReason(forFileAt url: URL) -> String? {
        let name = url.lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16) else { return nil }
        let data: Data
        if needsFullData(name: name, head: head) {
            guard let whole = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            data = whole
        } else {
            data = head
        }
        return mismatchReason(name: name, data: data)
    }
}
