import AppKit

/// AppKit-only action for the application settings store. Bookmark persistence and folder
/// validation remain in `KromoraSettings`; Finder presentation stops at this adapter boundary.
extension KromoraSettings {
    @discardableResult
    public func revealUserLookFolder() -> Bool {
        guard let folder = ensureUserLookFolder() else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        return true
    }
}
