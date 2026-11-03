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

        /// The warning to show; nil when the Look resolves (or nothing changed).
        var message: String? {
            if case .missing(let message) = self { return message }
            return nil
        }
    }

    /// Keyboard audition result.
    enum NavigationOutcome: Equatable {
        case select(CubeLUT)
        case clear
        case none
    }

    private let library: LUTLibrary
    /// Source of each photo's saved-revision Look. Nil where no package store is in play.
    private let store: EditDocumentStore?

    /// LUTs a document can reference that no folder scan produces — a freshly derived LUT, and the
    /// file it becomes once saved.
    private var derivedRegistry = DerivedLUTRegistry()

    /// Report one missing-reference transition at a time.
    private var lastReportedMissingLUT: LUTID?

    init(library: LUTLibrary, store: EditDocumentStore? = nil) {
        self.library = library
        self.store = store
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

    /// Resolve a document's Look for a photo whose saved revision may pin exact bytes.
    ///
    /// A revision with embedded bytes is reproduced from them. If those bytes cannot be loaded, only
    /// a library Look with the same content hash may stand in: a same-path replacement or a starter
    /// Look retired in favour of a successor is a different grade, and presenting it as the saved
    /// one would be a silent substitution. Without `stored`, or for a Look the photo no longer
    /// uses, this is the ordinary library resolution.
    func resolve(_ id: LUTID?, stored: StoredLook?) -> CubeLUT? {
        guard let id else { return nil }
        guard let stored, stored.lutID == id else { return resolve(id) }
        switch stored {
        case .embedded(let look):
            return look
        case .unavailable(_, let contentHash):
            guard let candidate = resolve(id), candidate.contentHash == contentHash else { return nil }
            return candidate
        }
    }

    /// The Look the photo's current saved revision was written with, if it embeds one.
    func storedLook(for reference: EditSourceReference?) -> StoredLook? {
        reference.flatMap { store?.storedLooks.storedLook(for: $0.portableAssetID) }
    }

    /// Resolve a document's Look for the photo at `reference`. The photo's saved revision wins over
    /// the browser, so its embedded, hash-verified bytes reproduce the saved render even when the
    /// external file moved, vanished or was replaced in place.
    func resolve(_ id: LUTID?, for reference: EditSourceReference?) -> CubeLUT? {
        resolve(id, stored: storedLook(for: reference))
    }

    /// True when choosing `look` re-selects the Look the photo already uses but with different bytes
    /// than its saved revision embeds (the external file changed since). That choice is deliberate,
    /// so it replaces the embedded bytes; the document itself does not change.
    func replacesStoredBytes(with look: CubeLUT, for reference: EditSourceReference) -> Bool {
        guard let stored = storedLook(for: reference) else { return false }
        return stored.lutID == look.lutID && stored.contentHash != look.contentHash
    }

    /// Makes `look` the photo's stored Look; its next save embeds the look's bytes.
    func adopt(_ look: CubeLUT, for reference: EditSourceReference) async {
        await store?.adoptLook(look, for: reference)
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
    func refreshStatus(for id: LUTID?, reference: EditSourceReference? = nil) -> StatusUpdate {
        let stored = storedLook(for: reference)
        guard let id else {
            lastReportedMissingLUT = nil
            return .cleared
        }
        // Embedded bytes need no scan, so they settle the question immediately.
        if case .embedded? = stored, stored?.lutID == id {
            lastReportedMissingLUT = nil
            return .cleared
        }
        guard !library.isScanning else { return .unchanged }
        guard resolve(id, stored: stored) == nil else {
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
    /// Look in browser order (My Looks, then Starter) so Up from the first Look can clear the grade.
    func navigate(
        _ direction: LookNavigation.Direction,
        from current: CubeLUT?,
        currentID: LUTID?
    ) -> NavigationOutcome {
        let looks = library.browserOrderedLooks
        let currentIndex = current.flatMap { looks.firstIndex(of: $0) }
        let nextIndex = LookNavigation.adjacentIndex(
            currentIndex: currentIndex, count: looks.count, direction: direction)
        if let nextIndex { return .select(looks[nextIndex]) }
        return currentID != nil ? .clear : .none
    }
}
