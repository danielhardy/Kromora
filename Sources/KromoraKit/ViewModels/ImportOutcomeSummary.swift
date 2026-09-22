import Foundation

/// The value shared by every library import entry point. Counts are deliberately disjoint:
/// `duplicates` are existing assets admitted by idempotency, `skipped` are inputs that were not
/// attempted (including preflight failures and the tail of a cancelled operation), and `failed`
/// are package/provider failures with an actionable reason.
struct ImportOutcomeSummary: Equatable, Sendable {
    let total: Int
    let imported: Int
    let duplicates: Int
    let skipped: Int
    let failed: Int
    let failureReasons: [String]
    let cancelled: Bool

    init(
        total: Int,
        imported: Int = 0,
        duplicates: Int = 0,
        skipped: Int = 0,
        failed: Int = 0,
        failureReasons: [String] = [],
        cancelled: Bool = false
    ) {
        self.total = max(0, total)
        self.imported = max(0, imported)
        self.duplicates = max(0, duplicates)
        self.skipped = max(0, skipped)
        self.failed = max(0, failed)
        self.failureReasons = failureReasons
        self.cancelled = cancelled
    }

    init(
        result: PortablePackageImportResult,
        total: Int,
        preflightSkipped: Int = 0,
        extraFailureReasons: [String] = []
    ) {
        let imported = result.imported.count
        let duplicates = result.duplicates.count
        let failed = result.failures.count
        let reserved = max(0, preflightSkipped)
        let unattempted = max(0, total - reserved - imported - duplicates - failed)
        let reasons = result.failures.map { failure in
            "(failure.source.name): (failure.reason)"
        } + extraFailureReasons
        self.init(
            total: total,
            imported: imported,
            duplicates: duplicates,
            skipped: reserved + unattempted,
            failed: failed,
            failureReasons: reasons,
            cancelled: result.cancelled
        )
    }

    static func failure(total: Int, reason: String, cancelled: Bool = false)
        -> ImportOutcomeSummary
    {
        let safeTotal = max(0, total)
        return ImportOutcomeSummary(
            total: safeTotal,
            skipped: max(0, safeTotal - 1),
            failed: safeTotal == 0 ? 0 : 1,
            failureReasons: reason.isEmpty ? [] : [reason],
            cancelled: cancelled
        )
    }

    func adding(_ other: ImportOutcomeSummary) -> ImportOutcomeSummary {
        ImportOutcomeSummary(
            total: total + other.total,
            imported: imported + other.imported,
            duplicates: duplicates + other.duplicates,
            skipped: skipped + other.skipped,
            failed: failed + other.failed,
            failureReasons: failureReasons + other.failureReasons,
            cancelled: cancelled || other.cancelled
        )
    }

    func status(prefix: String) -> String {
        let state = cancelled ? "cancelled" : "complete"
        var message = "\(prefix) \(state) — \(imported) imported, "
            + "\(duplicates) duplicate\(duplicates == 1 ? "" : "s"), "
            + "\(skipped) skipped, \(failed) failed"
        if !failureReasons.isEmpty {
            message += ": " + failureReasons.joined(separator: "; ")
        }
        return message
    }
}
