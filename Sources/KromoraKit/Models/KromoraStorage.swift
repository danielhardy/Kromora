import Foundation

/// Product-owned Application Support storage.
///
/// The first Kromora launch adopts the pre-rename Lumo directory when it exists. The migration
/// is intentionally conservative: it moves the complete directory only when the new location is
/// absent, and otherwise leaves both locations untouched so an interrupted upgrade cannot erase
/// user data.
enum KromoraStorage {
    static let productDirectoryName = "Kromora"
    private static let legacyDirectoryName = "Lumo"
    private static let migrationLock = NSLock()

    static func applicationSupportRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root(in: base, fileManager: fileManager)
    }

    /// The package location used by the running app's background maintenance trigger. Package
    /// opening is still a separate workflow; when this path is absent, the trigger is a no-op.
    static var defaultPortableLibraryPackageURL: URL {
        applicationSupportRoot().appendingPathComponent("Library.kromoralibrary", isDirectory: true)
    }

    static func root(in base: URL, fileManager: FileManager = .default) -> URL {
        let current = base.appendingPathComponent(productDirectoryName, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        migrationLock.lock()
        defer { migrationLock.unlock() }
        if fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: current.path) {
            try? fileManager.moveItem(at: legacy, to: current)
        }
        return current
    }
}
