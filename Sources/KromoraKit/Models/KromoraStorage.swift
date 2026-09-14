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

    static let portableLibraryPackageName = "Kromora Library.kromoralibrary"

    /// The one user-visible library package. Application Support remains the home for rebuildable
    /// projections and device-local caches; it is never a second library.
    static var defaultPortableLibraryPackageURL: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Pictures", isDirectory: true
            )
        return pictures.appendingPathComponent(portableLibraryPackageName, isDirectory: true)
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
