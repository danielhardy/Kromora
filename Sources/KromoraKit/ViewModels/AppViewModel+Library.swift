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

    /// The first window after the library opens, published once its query ordering is available.
    func publishLaunchWindow() {
        libraryBrowsingCoordinator.publishIndexUpdate(.init(
            kind: .reload,
            apply: { [weak self] in
                guard let self else { return }
                try self.reloadPortableWindow(pageIndex: 0)
                if self.collection.isActive { self.navigation.move(to: .grid) }
                self.collection.beginThumbnailDemand()
            },
            onFailure: { [weak self] error in
                self?.presentError(
                    "Kromora could not read the library package: \(error.localizedDescription)")
            }
        ))
    }

    /// `reloadPortableCollection` after an import published a new index generation: the ordering
    /// is prepared off the main actor before the window is read.
    func reloadPortableCollectionPrepared() async throws {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        try await libraryBrowsingCoordinator.reloadPortableCollectionPrepared()
        logFrameLookupSummaries([.gridOriginal, .gridEdited, .filmstrip, .launchHint])
    }

    /// The Photos bridge has a synchronous refresh callback, so queue its reload behind off-main
    /// ordering preparation for the index generation committed by `finishImportBatch()`.
    func publishPhotosImportCollectionReload() {
        libraryBrowsingCoordinator.publishReloadedWindow(
            apply: { [weak self] in try self?.reloadPortableWindow(pageIndex: 0) },
            onFailure: { [weak self] error in
                self?.presentError(
                    "Kromora could not refresh the library after Photos import: "
                        + error.localizedDescription
                )
            }
        )
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
        // The new index generation starts without a cached ordering: the coordinator prepares the
        // destination query off the main actor, keeping the published window up, before reading.
        libraryBrowsingCoordinator.publishIndexUpdate(.init(
            kind: .reload,
            apply: { [weak self] in try self?.reloadPortableWindow(pageIndex: 0) },
            onFailure: { [weak self] error in
                self?.presentError(
                    "Could not read the library package: \(error.localizedDescription)")
            }
        ))
    }
}
