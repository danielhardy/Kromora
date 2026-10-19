import Foundation

/// The persisted first-run welcome state. ContentView presents the welcome when it is unset.
enum FirstRunOnboarding {
    static let hasSeenWelcomeKey = "hasSeenWelcome"

    /// Makes the welcome appear the next time the main window opens. It touches no other state, so
    /// library contents, edits, and other Settings values are unchanged and nothing is re-imported.
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: hasSeenWelcomeKey)
    }
}
