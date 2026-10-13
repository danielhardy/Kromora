import AppKit

/// A long-running operation that quitting would cancel.
struct TerminationActivity: Equatable, Sendable {
    enum Kind: Sendable { case export, importing }

    let kind: Kind
    /// Short noun phrase for the confirmation alert, such as "export of 12 photos".
    let description: String
}

/// Derives the operations a quit would cancel from plain activity values, so the policy is
/// testable without coordinators or AppKit.
struct TerminationGuard: Equatable, Sendable {
    /// Items in the current batch export. Zero or nil means no batch is running.
    var batchExportTotal: Int?
    /// Total of an in-flight Photos import.
    var photosImportTotal: Int?
    /// Total of an in-flight package import (folder, removable media, Photos drop).
    var packageImportTotal: Int?

    var activities: [TerminationActivity] {
        var result: [TerminationActivity] = []
        if let total = batchExportTotal, total > 0 {
            result.append(TerminationActivity(kind: .export, description: "export of \(Self.photos(total))"))
        }
        if let total = photosImportTotal {
            result.append(TerminationActivity(kind: .importing, description: "Photos import of \(Self.photos(total))"))
        }
        if let total = packageImportTotal {
            result.append(TerminationActivity(kind: .importing, description: "import of \(Self.photos(total))"))
        }
        return result
    }

    static func photos(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }

    static func message(for activities: [TerminationActivity]) -> String {
        let list = activities.map(\.description).joined(separator: " and ")
        return "Quit and cancel \(list)?"
    }
}

/// Seam for the quit confirmation so tests can answer it without an NSAlert.
@MainActor
protocol QuitConfirmationPresenting {
    /// Returns true when the user chose to quit and cancel the running work.
    func confirmQuit(message: String) -> Bool
}

struct AppKitQuitConfirmation: QuitConfirmationPresenting {
    func confirmQuit(message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Work already finished is kept. Anything still running stops."
        alert.alertStyle = .warning
        // Cancel is first so it is the default button.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

extension TerminationGuard {
    /// True when quitting may proceed: nothing is running, or the user confirmed.
    @MainActor
    func shouldQuit(presenter: some QuitConfirmationPresenting) -> Bool {
        let active = activities
        guard !active.isEmpty else { return true }
        return presenter.confirmQuit(message: Self.message(for: active))
    }
}
