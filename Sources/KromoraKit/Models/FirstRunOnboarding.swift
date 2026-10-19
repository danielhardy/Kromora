import Foundation

/// The persisted first-run welcome state. ContentView presents the welcome when it is unset.
enum FirstRunOnboarding {
    static let hasSeenWelcomeKey = "hasSeenWelcome"

    /// Makes the welcome appear the next time the main window opens. It touches no other state, so
    /// library contents, edits, and other Settings values are unchanged and nothing is re-imported.
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: hasSeenWelcomeKey)
    }

    /// Whether the main window should present the welcome on appearance.
    static func shouldPresentWelcome(in defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: hasSeenWelcomeKey)
    }

    /// Persists completion; ContentView calls this when the welcome sheet is dismissed.
    static func markWelcomeSeen(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasSeenWelcomeKey)
    }
}
