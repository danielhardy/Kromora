import Foundation

/// The value-based result of classifying a dropped file URL.
public enum FileDropAction: Equatable, Sendable {
    case openImage(URL)
    case openFolder(URL)
    case invalid(URL)
}

/// Classifies dropped URLs without performing the resulting application action.
@MainActor
public struct FileDropActionPolicy {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func action(for url: URL) -> FileDropAction {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .invalid(url)
        }
        return isDirectory.boolValue ? .openFolder(url) : .openImage(url)
    }
}
