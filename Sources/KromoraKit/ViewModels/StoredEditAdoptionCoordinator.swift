import Foundation

/// Main-actor owner of the *rules* for adopting stored edits while a photo loads.
///
/// The stored document read races with source preparation and the speculative first render. This
/// coordinator owns the per-source bookkeeping (which source revision has been reconciled, and
/// whether the panel already adopted the stored document early) and decides what each stage should
/// do. It never touches the document: `AppViewModel` stays the sole owner of the published
/// `EditDocument` and applies the returned outcomes. It holds no back-reference to the view model.
@MainActor
final class StoredEditAdoptionCoordinator {

    /// Inputs the root reads from live state when a stored document arrives.
    struct Context: Equatable {
        /// Source revision of the request that produced the stored result.
        var requestSourceRevision: UInt64
        /// The root's current source revision.
        var currentSourceRevision: UInt64
        /// The session already existed in memory before this load began.
        var hadInMemorySession: Bool
        /// The in-memory edit revision differs from the one captured when the load began.
        var changedInMemory: Bool
        /// The stored document differs from the document currently published.
        var storedDocumentDiffers: Bool
        /// A first render was already scheduled for the current source revision.
        var speculativeRenderScheduled: Bool
    }

    /// Stage one: the stored document reached the panel before source preparation finished.
    enum EarlyOutcome: Equatable {
        /// Reconciliation already ran, or an in-memory session / mutation owns the document.
        case skip
        /// Write the stored document into the panel state.
        case adopt
    }

    /// Follow-up work after the late (source-dependent) reconciliation.
    enum PreviewFollowUp: Equatable {
        /// An adopted document differs from the speculative render; queue the corrective preview
        /// behind it (LUMO-317).
        case correctivePreview
        /// A stored frame held the first render back until the edit was known.
        case resumeDeferredSettledPreview
        /// Re-admit an already-presented final frame (histogram and canonical frame write) if it
        /// still matches the document on screen.
        case reconcilePresentedFrame
    }

    /// Stage two result.
    struct LateOutcome: Equatable {
        /// The stored document is the one on screen after this stage.
        var shouldAdopt: Bool
        /// The panel was already given the stored document by stage one.
        var adoptedEarly: Bool
        /// The adopted document differs from what was published before adoption.
        var documentChanged: Bool
        var followUp: PreviewFollowUp
    }

    /// Source revision whose stored document has been reconciled. Supporting work (histogram,
    /// edited thumbnails) is admitted only once this matches the active source.
    private(set) var resolvedSourceRevision: UInt64?

    /// Set when the stored document reached the panel before source preparation finished
    /// (KRMA-755). `documentChanged` records whether a speculative render with a different
    /// document had already been scheduled, i.e. whether the late reconciliation still owes a
    /// corrective render.
    private var earlyAdoption: (sourceRevision: UInt64, documentChanged: Bool)?

    func isResolved(for sourceRevision: UInt64) -> Bool {
        resolvedSourceRevision == sourceRevision
    }

    /// A new photo load starts: nothing is reconciled yet.
    func reset() {
        resolvedSourceRevision = nil
    }

    /// Stage one. Only a still-pristine, never-seen session may adopt disk state; a mutation made
    /// while loading owns the document. A `.adopt` result records the early adoption.
    func decideEarlyAdoption(_ context: Context) -> EarlyOutcome {
        guard resolvedSourceRevision != context.currentSourceRevision else { return .skip }
        guard !context.hadInMemorySession, !context.changedInMemory else { return .skip }
        resolvedSourceRevision = context.requestSourceRevision
        // A first render scheduled before this point used the identity document and needs the
        // corrective render; one scheduled after it already uses the stored document.
        earlyAdoption = (
            context.requestSourceRevision,
            context.storedDocumentDiffers && context.speculativeRenderScheduled
        )
        return .adopt
    }

    /// Stage two. Consumes any early-adoption record and marks the source reconciled.
    func decideLateAdoption(_ context: Context, hasDeferredSettledPreview: Bool) -> LateOutcome {
        let adoptedEarly = earlyAdoption?.sourceRevision == context.requestSourceRevision
        let earlyDocumentChanged = adoptedEarly ? (earlyAdoption?.documentChanged ?? false) : false
        earlyAdoption = nil
        // A pre-existing session or a mutation made while preparation was in flight owns the
        // current document. Only a still-pristine, never-seen session may adopt disk state.
        let shouldAdopt = adoptedEarly || (!context.hadInMemorySession && !context.changedInMemory)
        var documentChanged = false
        if shouldAdopt {
            // After an early adoption the panel already has the stored document; an edit made
            // since then owns the document and has scheduled its own render.
            documentChanged =
                adoptedEarly
                ? earlyDocumentChanged && !context.changedInMemory
                : context.storedDocumentDiffers
        }
        resolvedSourceRevision = context.currentSourceRevision
        // In-memory sessions and edits made while loading remain authoritative and must not be
        // replaced by a corrective render.
        let followUp: PreviewFollowUp
        if shouldAdopt, documentChanged {
            followUp = .correctivePreview
        } else if hasDeferredSettledPreview {
            followUp = .resumeDeferredSettledPreview
        } else {
            followUp = .reconcilePresentedFrame
        }
        return LateOutcome(
            shouldAdopt: shouldAdopt, adoptedEarly: adoptedEarly,
            documentChanged: documentChanged, followUp: followUp)
    }
}
