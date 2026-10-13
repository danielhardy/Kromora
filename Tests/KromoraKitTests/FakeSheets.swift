import AppKit

@testable import KromoraKit

/// Scripted `SheetPresenting`: tests set the answer each sheet returns (`nil`/`false` = cancel) and
/// read back the panels as `configure` left them.
@MainActor
final class FakeSheets: SheetPresenting {
    var saveURL: URL?
    var openURLs: [URL]?
    var confirmResult = true
    private(set) var saveCalls = 0
    private(set) var openCalls = 0
    private(set) var confirmCalls = 0
    private(set) var lastSavePanel: NSSavePanel?
    private(set) var lastOpenPanel: NSOpenPanel?
    private(set) var lastConfirmButtons: [String] = []

    func chooseSaveURL(configure: (NSSavePanel) -> Void) async -> URL? {
        saveCalls += 1
        let panel = NSSavePanel()
        configure(panel)
        lastSavePanel = panel
        return saveURL
    }

    func chooseOpenURLs(configure: (NSOpenPanel) -> Void) async -> [URL]? {
        openCalls += 1
        let panel = NSOpenPanel()
        configure(panel)
        lastOpenPanel = panel
        return openURLs
    }

    func confirm(
        message: String, informativeText: String, style: NSAlert.Style, buttons: [String]
    ) async -> Bool {
        confirmCalls += 1
        lastConfirmButtons = buttons
        return confirmResult
    }
}
