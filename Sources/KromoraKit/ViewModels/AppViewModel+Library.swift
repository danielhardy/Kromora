import Foundation

/// Session-dependent behavior that `bindPortableLibrary` installs once the package is open.
extension AppViewModel {
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
