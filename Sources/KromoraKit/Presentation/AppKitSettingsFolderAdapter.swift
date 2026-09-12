import AppKit

/// The application-shell seam for revealing a URL in Finder or another workspace browser.
@MainActor
public protocol WorkspaceRevealing {
    @discardableResult
    func reveal(_ urls: [URL]) -> Bool
}

/// Production AppKit implementation of ``WorkspaceRevealing``.
@MainActor
public final class AppKitWorkspaceRevealer: WorkspaceRevealing {
    public init() {}

    @discardableResult
    public func reveal(_ urls: [URL]) -> Bool {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        return true
    }
}

/// AppKit-only action for the application settings store. Bookmark persistence and folder
/// validation remain in `KromoraSettings`; Finder presentation stops at this adapter boundary.
extension KromoraSettings {
    @discardableResult
    public func revealUserLookFolder(
        using workspace: any WorkspaceRevealing = AppKitWorkspaceRevealer()
    ) -> Bool {
        guard let folder = ensureUserLookFolder() else { return false }
        return workspace.reveal([folder])
    }
}
