import Foundation

/// Main-actor owner of Look *resolution* and selection decisions.
///
/// It owns the derived-LUT registry and the one-shot missing-reference report, and it decides what a
/// selection or keyboard audition should do. It never mutates the edit document: `AppViewModel`
/// stays the sole owner of the published `EditDocument` and applies each returned outcome through
/// its own `updateDocument` seam. The coordinator holds the `LUTLibrary` it resolves against, not a
/// back-reference to the view model.
@MainActor
final class LookSelectionCoordinator {

    /// What a Look selection by stable ID should do to the document and status line.
    enum SelectionOutcome: Equatable {
        /// Explicit None row.
        case clear
        /// Resolved Look to write into the document.
        case select(CubeLUT)
        /// The library is still scanning; keep the stored ID and tell the user to retry.
        case loading(message: String)
        /// Finished scan, no match. Keep the stored ID and re-evaluate the resolution status.
        case unresolved
    }

    /// Change to the inspector-visible resolution warning.
    enum StatusUpdate: Equatable {
        case unchanged
        case cleared
        case missing(message: String)
    }

    /// Keyboard audition result.
    enum NavigationOutcome: Equatable {
        case select(CubeLUT)
        case clear
        case none
    }

    private let library: LUTLibrary

    /// LUTs a document can reference that no folder scan produces — a freshly derived LUT, and the
    /// file it becomes once saved.
    private var derivedRegistry = DerivedLUTRegistry()

    /// Report one missing-reference transition at a time.
    private var lastReportedMissingLUT: LUTID?

    init(library: LUTLibrary) {
        self.library = library
    }

    // MARK: Resolution

    /// Resolve a document's LUT reference: prefer the latest library scan, then the in-memory
    /// registry. The library must win for file-backed IDs: the registry retains saved derived LUTs
    /// so they work outside the library folder, but must not mask a replacement found by a scan.
    func resolve(_ id: LUTID?) -> CubeLUT? {
        guard let id else { return nil }
        if let scanned = library.allLUTs.first(matching: id) { return scanned }
        return derivedRegistry.lut(for: id)
    }

    /// A derived LUT is in no library, so nothing but the registry can resolve it later. Remember
    /// every one rather than replacing the last: a document made now must still resolve after the
    /// user derives again.
    func register(_ look: CubeLUT) {
        derivedRegistry.register(look)
    }

    /// Number of registered derived/saved LUTs. Internal for tests.
    var registeredCount: Int { derivedRegistry.count }

    // MARK: Status

    /// Forget the last reported missing reference, e.g. when a different photo becomes active.
    func resetReportedStatus() {
        lastReportedMissingLUT = nil
    }

    /// Evaluate the active document's Look reference. Waiting for scan completion avoids a false
    /// warning while the library is still assembling; the document retains the unresolved ID.
    func refreshStatus(for id: LUTID?) -> StatusUpdate {
        guard let id else {
            lastReportedMissingLUT = nil
            return .cleared
        }
        guard !library.isScanning else { return .unchanged }
        guard resolve(id) == nil else {
            lastReportedMissingLUT = nil
            return .cleared
        }
        guard lastReportedMissingLUT != id else { return .unchanged }

        let name = id.isDerived ? "derived look" : URL(fileURLWithPath: id.raw).lastPathComponent
        lastReportedMissingLUT = id
        return .missing(message: "Look “\(name)” is unavailable; the stored reference was kept.")
    }

    // MARK: Selection

    /// Decide what selecting a Look by its stable document ID means. The browser binds to IDs
    /// rather than resolved LUT values so the explicit None row and a missing file stay distinct.
    func selection(for id: LUTID?) -> SelectionOutcome {
        guard let id else { return .clear }
        guard let look = resolve(id) else {
            if library.isScanning {
                return .loading(
                    message: "Look is still loading. Try selecting it again when scanning finishes.")
            }
            return .unresolved
        }
        return .select(look)
    }

    /// Audition the adjacent Look, treating the explicit None row as the slot before the first
    /// library Look so Up from the first Look can clear the grade.
    func navigate(
        _ direction: LookNavigation.Direction,
        from current: CubeLUT?,
        currentID: LUTID?
    ) -> NavigationOutcome {
        let looks = library.allLUTs
        let currentIndex = current.flatMap { looks.firstIndex(of: $0) }
        let nextIndex = LookNavigation.adjacentIndex(
            currentIndex: currentIndex, count: looks.count, direction: direction)
        if let nextIndex { return .select(looks[nextIndex]) }
        return currentID != nil ? .clear : .none
    }
}
