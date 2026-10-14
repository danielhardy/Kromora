import Foundation

/// Which `.kromoralibrary` package the next launch opens.
///
/// The choice is a security-scoped bookmark in `UserDefaults`; absence means the default package in
/// Pictures. Nothing here opens, moves, creates or deletes a package: choosing another location
/// leaves the default one untouched, and a bookmark that no longer resolves falls back to the default
/// with a notice rather than touching the old path.
struct ActiveLibrarySelection {
    static let bookmarkKey = "Kromora.settings.activeLibraryBookmark"

    enum ChoiceError: Error, Equatable, LocalizedError {
        case notALibrary(name: String)
        case bookmarkFailed(name: String)

        var errorDescription: String? {
            switch self {
            case .notALibrary(let name):
                return "\u{201C}\(name)\u{201D} is not a Kromora library package."
            case .bookmarkFailed(let name):
                return "Kromora could not save access to \u{201C}\(name)\u{201D}. Choose the library again to grant permission."
            }
        }
    }

    /// What a launch opens. `access` is held for the session so the package stays reachable.
    struct Resolution {
        let url: URL
        let access: SecurityScopedResourceAccess?
        /// Set when a stored choice could not be used and the default was substituted.
        let notice: String?
    }

    let preferences: UserDefaults
    let defaultURL: URL

    init(
        preferences: UserDefaults,
        defaultURL: URL = KromoraStorage.defaultPortableLibraryPackageURL
    ) {
        self.preferences = preferences
        self.defaultURL = defaultURL
    }

    var hasChoice: Bool { preferences.data(forKey: Self.bookmarkKey) != nil }

    /// The chosen package location without starting access, for display. `nil` when using the default.
    var chosenURL: URL? {
        guard let data = preferences.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data, options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The package's own structural validation (manifest and membership shards), not an extension check.
    static func validate(_ url: URL) throws {
        do {
            _ = try PortableLibraryPackage.open(at: url)
        } catch {
            throw ChoiceError.notALibrary(name: url.lastPathComponent)
        }
    }

    /// Validates `url` and stores it as the library for the next launch. `url` must carry access
    /// already started by the panel; it is released here once the bookmark exists. An invalid folder
    /// changes nothing.
    func choose(_ url: URL, access: SecurityScopedResourceAccess) throws {
        defer { access.release() }
        try Self.validate(url)
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        ) else {
            throw ChoiceError.bookmarkFailed(name: url.lastPathComponent)
        }
        preferences.set(data, forKey: Self.bookmarkKey)
    }

    func useDefault() {
        preferences.removeObject(forKey: Self.bookmarkKey)
    }

    /// The package this launch opens. A stored choice that is stale, unresolvable, unreachable or no
    /// longer a directory yields the default plus a one-time notice; the bookmark is cleared so the
    /// notice does not repeat, and the old path is never modified.
    func resolve() -> Resolution {
        guard let data = preferences.data(forKey: Self.bookmarkKey) else {
            return Resolution(url: defaultURL, access: nil, notice: nil)
        }
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data, options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &stale),
           let access = SecurityScopedResourceAccess.startAccessing(url)
        {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                if stale,
                   let fresh = try? url.bookmarkData(
                       options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                {
                    preferences.set(fresh, forKey: Self.bookmarkKey)
                }
                return Resolution(url: url, access: access, notice: nil)
            }
            access.release()
        }
        useDefault()
        return Resolution(
            url: defaultURL, access: nil,
            notice: "Kromora could not open the library you chose, so it opened the default library "
                + "instead. The chosen library was not changed. You can choose it again in Settings.")
    }
}

extension KromoraSettings {
    var activeLibrary: ActiveLibrarySelection { ActiveLibrarySelection(preferences: preferences) }
}
