import Foundation

/// Session-dependent behavior that `bindPortableLibrary` installs once the package is open.
extension AppViewModel {
    /// Starts opening the package of a `defersLibraryOpen` model off the main actor. `takeOver`
    /// answers the expired-lease question once the open is under way.
    @discardableResult
    func beginOpeningLibrary(
        takeOver: @escaping @MainActor () async -> Bool = { false }
    ) -> Task<Void, Never>? {
        guard portableLibrary == nil, !isShuttingDown else { return nil }
        return libraryOpen.start(at: portablePackageURL, takeOver: takeOver) { [weak self] opened in
            guard let self else {
                opened.releaseUnbound()
                return .failed("The library closed before it finished opening.")
            }
            return await self.bindOpenedPackage(opened)
        }
    }

    /// Opens the package and waits for it to bind or fail.
    func openLibrary(takeOver: Bool = false) async {
        await beginOpeningLibrary(takeOver: { takeOver })?.value
    }

    /// Builds the session on the main actor, binds the store, then the session wiring. Owns the
    /// lease: every failure path releases it.
    private func bindOpenedPackage(_ opened: OpenedPackage) async -> LibraryOpenState {
        guard !isShuttingDown else {
            opened.releaseUnbound()
            return .idle
        }
        do {
            let session = try PortableLibrarySession(
                opened: opened, scheduler: workScheduler, asynchronousIndexLoading: true)
            guard await editStore.bind(package: session.package, lease: session.lease) else {
                await session.shutdown()
                return .failed("The edit store is already bound to a library.")
            }
            bindPortableLibrary(session, recoveredPreviousWriter: opened.recoveredPreviousWriter)
            return .ready
        } catch {
            return .failed(
                "Kromora could not open its library package at \(portablePackageURL.path): "
                    + error.localizedDescription)
        }
    }

    func libraryOpenStateDidChange(_ state: LibraryOpenState) {
        switch state {
        case .opening:
            statusMessage = "Opening library…"
        case .failed:
            reportPortableLibraryUnavailable()
        case .ready:
            if statusMessage == "Opening library…" { statusMessage = "" }
        case .idle:
            break
        }
    }

    func handlePortableIndexLoadingState(_ state: LibraryIndexLoadingState) {
        guard !isShuttingDown else { return }
        if let error = state.errorMessage {
            presentError("Could not open the library index: \(error)")
            return
        }
        if state.isComplete {
            if statusMessage.hasPrefix("Opening library index")
                || statusMessage.hasPrefix("Rebuilding library index") {
                statusMessage = ""
            }
            if portableLibrary?.didRepairIndexOnOpen == true {
                statusMessage = "Rebuilt the library index from package membership."
            }
        } else {
            statusMessage =
                "Rebuilding library index… \(state.shardsRead) of \(state.totalShards) sections"
        }
        do {
            try reloadPortableWindow(pageIndex: 0)
        } catch {
            presentError("Could not read the library package: \(error.localizedDescription)")
        }
    }
}
