import Foundation

/// Names Kromora as the editor that produced an export. Written to TIFF `Software` and
/// `xmp:CreatorTool`; it never credits the photographer.
struct ExportAttribution: Equatable {
    let editorIdentity: String

    /// "Kromora 1.2 (45)" from the bundle's marketing version and build number. A missing value
    /// (an unbundled development run) is omitted rather than invented.
    init(infoDictionary: [String: Any]) {
        let version = Self.value(for: "CFBundleShortVersionString", in: infoDictionary)
        let build = Self.value(for: "CFBundleVersion", in: infoDictionary)
        var identity = "Kromora"
        if let version { identity += " \(version)" }
        if let build { identity += version == nil ? " build \(build)" : " (\(build))" }
        editorIdentity = identity
    }

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    private static func value(for key: String, in infoDictionary: [String: Any]) -> String? {
        guard let value = infoDictionary[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
