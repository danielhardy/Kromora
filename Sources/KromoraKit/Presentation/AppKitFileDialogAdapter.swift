import AppKit
import UniformTypeIdentifiers

/// The application-shell seam for native file dialogs. Feature views and view models can request
/// a selection without constructing an AppKit panel, which keeps cancel behavior panel-free in
/// tests.
@MainActor
public protocol FileDialogProviding {
    func chooseFiles(
        title: String,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        startingAt directoryURL: URL?
    ) -> [URL]?
    func chooseFolder(
        title: String,
        prompt: String,
        startingAt directoryURL: URL?,
        canCreateDirectories: Bool
    ) -> URL?
}

public extension FileDialogProviding {
    func chooseImages(startingAt directoryURL: URL?) -> [URL]? {
        chooseFiles(
            title: "Open Image",
            allowedContentTypes: ImageDecoder.supportedTypes,
            allowsMultipleSelection: true,
            startingAt: directoryURL
        )
    }
}

/// Production AppKit implementation of ``FileDialogProviding``.
@MainActor
public final class AppKitFileDialog: FileDialogProviding {
    public init() {}

    public func chooseFiles(
        title: String,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        startingAt directoryURL: URL?
    ) -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }

    public func chooseFolder(
        title: String,
        prompt: String,
        startingAt directoryURL: URL?,
        canCreateDirectories: Bool
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

/// Launch-time confirmation before breaking an expired portable-library writer lease.
@MainActor
protocol PortablePackageLeaseRecoveryConfirming {
    func confirmBreakExpiredWriterLease(
        packageURL: URL,
        info: PortablePackageLeaseInfo
    ) -> Bool
}

/// Production AppKit prompt used when a previous session left an expired `manifest.lock`.
@MainActor
struct AppKitPortablePackageLeaseRecoveryConfirmer: PortablePackageLeaseRecoveryConfirming {
    func confirmBreakExpiredWriterLease(
        packageURL: URL,
        info: PortablePackageLeaseInfo
    ) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Take over this library?"
        alert.informativeText =
            "The previous Kromora session on \(info.deviceName) did not close cleanly, so the writer lock expired.\n\n"
            + "Kromora will recover any interrupted writes, then open \(packageURL.lastPathComponent)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Take Over Library")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
