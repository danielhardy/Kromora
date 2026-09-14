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

    /// Names for user-visible destinations. These are deliberately outside Application Support:
    /// files produced by an explicit user action must be easy to find, copy, and back up.
    static let defaultExportDirectoryName = "Kromora Exports"
    static let defaultUserLookDirectoryName = "Kromora Looks"

    static func applicationSupportRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root(in: base, fileManager: fileManager)
    }

    /// The disposable device-local cache boundary. Individual cache owners choose a child
    /// directory, but none of them should independently invent an Application Support path.
    static func cachesRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(productDirectoryName, isDirectory: true)
    }

    /// Application Support location for new projections. This deliberately does not call
    /// `root(in:)`: opening a portable package must not migrate or otherwise touch a legacy
    /// folder-backed library as a side effect of creating its disposable index.
    static func projectionRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(productDirectoryName, isDirectory: true)
    }

    static func cacheDirectory(
        named name: String, fileManager: FileManager = .default
    ) -> URL {
        cachesRoot(fileManager: fileManager).appendingPathComponent(name, isDirectory: true)
    }

    /// The local query/index projection. Unlike render and analysis caches it is kept in
    /// Application Support because it is useful across launches, but it is never package truth.
    static func indexURL(
        for libraryID: UUID, fileManager: FileManager = .default
    ) -> URL {
        projectionRoot(fileManager: fileManager)
            .appendingPathComponent("Indexes", isDirectory: true)
            .appendingPathComponent(libraryID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("LibraryIndex.store")
    }

    static func picturesDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Pictures", isDirectory: true
            )
    }

    static func defaultExportDirectory(fileManager: FileManager = .default) -> URL {
        picturesDirectory(fileManager: fileManager)
            .appendingPathComponent(defaultExportDirectoryName, isDirectory: true)
    }

    static func defaultUserLookDirectory(fileManager: FileManager = .default) -> URL {
        picturesDirectory(fileManager: fileManager)
            .appendingPathComponent(defaultUserLookDirectoryName, isDirectory: true)
    }

    static func packageDerivedDirectory(
        named name: String, under packageURL: URL
    ) -> URL {
        packageURL.standardizedFileURL
            .appendingPathComponent("Derived", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    static let portableLibraryPackageName = "Kromora Library.kromoralibrary"

    /// The one user-visible library package. Application Support remains the home for rebuildable
    /// projections and device-local caches; it is never a second library.
    static var defaultPortableLibraryPackageURL: URL {
        let pictures = picturesDirectory()
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
