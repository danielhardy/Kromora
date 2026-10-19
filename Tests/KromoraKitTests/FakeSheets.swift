import AppKit

@testable import KromoraKit

/// Scripted `SheetPresenting`: tests set the answer each sheet returns (`nil`/`false` = cancel) and
/// read back the panels as `configure` left them.
@MainActor
final class FakeSheets: SheetPresenting {
    var saveURL: URL?
    var openURLs: [URL]?
    var confirmResult = true
    /// Answers for export Step 1, consumed in order; `true` (Continue) once exhausted.
    var setupResults: [Bool] = []
    /// Runs inside the folder step with its panel, standing in for the user's clicks.
    var openHandler: ((NSOpenPanel) -> [URL]?)?
    private(set) var setupCalls = 0
    private(set) var lastSetupAccessory: ExportSetupAccessoryView?
    private(set) var lastSetupTitle: String?
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
        if let openHandler { return openHandler(panel) }
        return openURLs
    }

    func confirmExportSetup(title: String, message: String, accessory: NSView) async -> Bool {
        setupCalls += 1
        lastSetupTitle = title
        lastSetupAccessory = accessory as? ExportSetupAccessoryView
        return setupResults.isEmpty ? true : setupResults.removeFirst()
    }

    func confirm(
        message: String, informativeText: String, style: NSAlert.Style, buttons: [String]
    ) async -> Bool {
        confirmCalls += 1
        lastConfirmButtons = buttons
        return confirmResult
    }
}
