import AppKit

/// The seam for window-attached save/open panels and confirmations. Coordinators describe the
/// panel through `configure` and await the result, so tests can accept or cancel without AppKit.
/// `configure` runs on the real panel just before it is shown; fakes need not call it.
@MainActor
protocol SheetPresenting {
    /// The chosen save URL, or `nil` when the user cancelled.
    func chooseSaveURL(configure: (NSSavePanel) -> Void) async -> URL?
    /// The chosen URLs, or `nil` when the user cancelled.
    func chooseOpenURLs(configure: (NSOpenPanel) -> Void) async -> [URL]?
    /// `true` when the user chose the first (default) button.
    func confirm(
        message: String, informativeText: String, style: NSAlert.Style, buttons: [String]
    ) async -> Bool
}

/// Production implementation: attaches to the key (else main) window as a sheet, and uses
/// a free-standing alert window when none exists, without entering a nested modal run loop.
@MainActor
struct AppKitSheetPresenter: SheetPresenting {
    private var hostWindow: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow }

    func chooseSaveURL(configure: (NSSavePanel) -> Void) async -> URL? {
        let panel = NSSavePanel()
        configure(panel)
        let response = await present(panel)
        return response == .OK ? panel.url : nil
    }

    func chooseOpenURLs(configure: (NSOpenPanel) -> Void) async -> [URL]? {
        let panel = NSOpenPanel()
        configure(panel)
        let response = await present(panel)
        return response == .OK ? panel.urls : nil
    }

    func confirm(
        message: String, informativeText: String, style: NSAlert.Style, buttons: [String]
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        if let window = hostWindow {
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        // No window to attach to (a quit after the last window closed): show the alert's own window
        // without a nested run loop and route the buttons through `AlertButtonResponder`.
        NSApp.activate()
        return await withCheckedContinuation { continuation in
            let responder = AlertButtonResponder()
            responder.onChoose = { index in
                alert.window.orderOut(nil)
                responder.onChoose = nil
                continuation.resume(returning: index == 0)
            }
            for (index, button) in alert.buttons.enumerated() {
                button.tag = index
                button.target = responder
                button.action = #selector(AlertButtonResponder.choose(_:))
            }
            // Buttons hold their target weakly; `onChoose` captures the responder until it fires.
            alert.layout()
            alert.window.center()
            alert.window.makeKeyAndOrderFront(nil)
        }
    }

    private func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = hostWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
    }
}

/// Target for the buttons of an alert shown without a host window.
@MainActor
private final class AlertButtonResponder: NSObject {
    var onChoose: ((Int) -> Void)?

    @objc func choose(_ sender: NSButton) { onChoose?(sender.tag) }
}
