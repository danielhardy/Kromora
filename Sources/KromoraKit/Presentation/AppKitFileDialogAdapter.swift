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
    ) async -> [URL]?
    func chooseFolder(
        title: String,
        prompt: String,
        startingAt directoryURL: URL?,
        canCreateDirectories: Bool
    ) async -> URL?
}

public extension FileDialogProviding {
    func chooseImages(startingAt directoryURL: URL?) async -> [URL]? {
        await chooseFiles(
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
    private let sheets: any SheetPresenting

    public init() { sheets = AppKitSheetPresenter() }

    init(sheets: any SheetPresenting) { self.sheets = sheets }

    public func chooseFiles(
        title: String,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        startingAt directoryURL: URL?
    ) async -> [URL]? {
        await sheets.chooseOpenURLs { panel in
            panel.title = title
            panel.allowedContentTypes = allowedContentTypes
            panel.allowsMultipleSelection = allowsMultipleSelection
            panel.directoryURL = directoryURL
        }
    }

    public func chooseFolder(
        title: String,
        prompt: String,
        startingAt directoryURL: URL?,
        canCreateDirectories: Bool
    ) async -> URL? {
        await sheets.chooseOpenURLs { panel in
            panel.title = title
            panel.prompt = prompt
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = canCreateDirectories
            panel.allowsMultipleSelection = false
            panel.directoryURL = directoryURL
        }?.first
    }
}

/// Launch-time confirmation before breaking an expired portable-library writer lease.
///
/// The library opens synchronously inside ``AppViewModel/init``, so the question is asked first,
/// through the sheet seam, and the answer is handed to the open as a ``ResolvedLeaseRecoveryConfirmer``.
@MainActor
struct PortablePackageLeaseRecoveryPrompt {
    let sheets: any SheetPresenting

    /// `nil` when opening needs no decision (no lock, a live lease, or a conclusively dead local
    /// writer). Otherwise whether the user chose to take over the expired lease.
    func decision(for packageURL: URL, now: Date = Date()) async -> ResolvedLeaseRecoveryConfirmer? {
        guard let info = PortablePackageLease.existingInfo(at: packageURL.standardizedFileURL),
              info.expiresAt <= now, info.localWriterState != .dead
        else { return nil }
        let accepted = await sheets.confirm(
            message: "Take over this library?",
            informativeText:
                "The previous Kromora session on \(info.deviceName) did not close cleanly, so the writer lock expired.\n\n"
                + "Kromora will recover any interrupted writes, then open \(packageURL.lastPathComponent).",
            style: .warning,
            buttons: ["Take Over Library", "Not Now"]
        )
        return ResolvedLeaseRecoveryConfirmer(allowBreak: accepted)
    }
}

/// A lease-recovery answer that was already collected asynchronously.
struct ResolvedLeaseRecoveryConfirmer: PortablePackageLeaseRecoveryConfirming {
    let allowBreak: Bool

    func confirmBreakExpiredWriterLease(
        packageURL: URL,
        info: PortablePackageLeaseInfo
    ) -> Bool {
        allowBreak
    }
}

/// Answers the open's synchronous lease question; see ``PortablePackageLeaseRecoveryPrompt``.
@MainActor
protocol PortablePackageLeaseRecoveryConfirming {
    func confirmBreakExpiredWriterLease(
        packageURL: URL,
        info: PortablePackageLeaseInfo
    ) -> Bool
}
