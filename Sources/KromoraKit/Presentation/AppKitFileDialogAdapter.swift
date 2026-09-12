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
