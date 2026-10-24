import Foundation

/// Decides when Kromora may ask the system to show its App Store review sheet.
///
/// This stores engagement state, never the outcome: the app cannot learn whether the person rated
/// or whether the system suppressed the sheet, so only "we called the API" is persisted.
struct ReviewPromptPolicy {
    static let keyPrefix = "Kromora.reviewPrompt."
    static let finishCountKey = keyPrefix + "finishCount"
    static let launchCountKey = keyPrefix + "launchCount"
    static let firstFinishLaunchKey = keyPrefix + "firstFinishLaunch"
    static let lastRequestKey = keyPrefix + "lastRequest"

    /// Spaces attempts across the system's three-per-365-days ceiling.
    static let minimumRequestInterval: TimeInterval = 120 * 24 * 60 * 60
    static let requiredFinishes = 2

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Counts this process as one launch. Call once per process.
    func recordLaunch() {
        defaults.set(launchCount + 1, forKey: Self.launchCountKey)
    }

    /// Whether a finished batch counts toward the prompt.
    static func qualifies(_ outcome: ExportCoordinator.BatchOutcome) -> Bool {
        outcome.exported > 0 && outcome.failed == 0 && !outcome.cancelled
            && outcome.photosFailed == 0 && outcome.editedExportCount > 0
    }

    /// Records one qualifying finish and reports whether the API may be called now, ignoring
    /// whether the app is quiet (see `ReviewPromptPresenting` callers for those gates).
    func recordQualifyingFinish() -> Bool {
        let count = defaults.integer(forKey: Self.finishCountKey) + 1
        defaults.set(count, forKey: Self.finishCountKey)
        if count == 1 { defaults.set(launchCount, forKey: Self.firstFinishLaunchKey) }
        guard count >= Self.requiredFinishes,
              launchCount > defaults.integer(forKey: Self.firstFinishLaunchKey)
        else { return false }
        if let last = defaults.object(forKey: Self.lastRequestKey) as? Date,
           now().timeIntervalSince(last) < Self.minimumRequestInterval {
            return false
        }
        return true
    }

    /// Persists that the API was called.
    func recordRequest() {
        defaults.set(now(), forKey: Self.lastRequestKey)
    }

    private var launchCount: Int { defaults.integer(forKey: Self.launchCountKey) }
}
