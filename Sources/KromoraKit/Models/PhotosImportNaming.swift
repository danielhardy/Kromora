import Foundation

/// Names for Photos picker items. The real original filename always wins. When PhotoKit cannot
/// supply one (no authorization, limited access, an asset without a resource), the name is derived
/// from the asset's capture date, or from the batch's import time when even that is unavailable.
/// A per-batch UUID keeps fallback names distinct across imports, and items with the same timestamp
/// inside one batch get a deterministic ordinal-order " 2", " 3" suffix (KRMA-1030). A per-library
/// counter was rejected: it needs durable state and would shift names when the library changes.
enum PhotosImportNaming {
    static func fallbackName(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "Photo %04d-%02d-%02d %02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    /// Resolves one name per selection, in input order, and stamps it onto the selection so the
    /// review sheet, the import, and the library agree even when only a subset is imported.
    @MainActor
    static func resolve(
        _ selections: [PhotosImportSelection],
        provider: any PhotosImportProviding,
        batchDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        batchID: UUID = UUID()
    ) -> [PhotosImportSelection] {
        var used = Set<String>()
        let batchSuffix = batchID.uuidString
        return selections.map { selection in
            var resolved = selection
            let originalName = selection.name ?? provider.originalFilename(for: selection)
            let base: String
            if let originalName {
                base = originalName
            } else {
                let fallbackDate = provider.captureDate(for: selection) ?? batchDate
                base = "\(fallbackName(for: fallbackDate, calendar: calendar)) \(batchSuffix)"
            }
            var candidate = base
            var suffix = 2
            while !used.insert(candidate.lowercased()).inserted {
                candidate = disambiguated(base, suffix: suffix)
                suffix += 1
            }
            resolved.name = candidate
            return resolved
        }
    }

    private static func disambiguated(_ name: String, suffix: Int) -> String {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else { return "\(name) \(suffix)" }
        let stem = (name as NSString).deletingPathExtension
        return "\(stem) \(suffix).\(ext)"
    }
}
