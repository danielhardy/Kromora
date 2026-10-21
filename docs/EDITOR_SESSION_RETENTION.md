# Editor-session retention

`EditorDocumentCoordinator` keeps one in-memory editing session per photo (the current
`EditDocument` plus bounded undo/redo). A session is correctness state, not only a cache: restoring
a photo, adopting a stored edit, pasting, export, thumbnails, and persistence all read it as the
newest document. This guide defines how many sessions stay resident and which ones may be dropped.

## Budget

| Constant | Default | Meaning |
| --- | ---: | --- |
| `maximumResidentSessions` | 32 | Covers the filmstrip and prefetch neighbourhood plus recent back-navigation. |
| `maximumResidentSessionBytes` | 192 MiB | Estimated recipe-payload threshold, not a process-memory guarantee. |

Both are initializer parameters so tests inject small values. The budget counts every resident
session, but only eligible sessions are evicted, so the resident set can exceed it.

The cost of a session is `(1 + undoCount + redoCount + (isGrouping ? 1 : 0)) × documentCost`; the
extra document is the undo point held by an open gesture group. `EditDocument.estimatedRetentionBytes`
is a deterministic value-payload estimate (a fixed 4 KiB shell, plus element stride for every
variable-length collection in the document and its recipes, plus UTF-8 bytes of retained strings).
It is computed when a session is stored (`commit`, `apply`, `adopt*`) and cached on the entry; reads
never scan sessions or encode documents. It takes no copy-on-write discount and does not capture
allocator or array-capacity overhead.

Recency is a monotonic tick stamped on `activate`, `commit`, `apply`, and `adopt*`. Plain
`session(for:)` reads (thumbnails, admission, export) do not touch recency, so background readers
cannot keep a stale session alive.

## Pinning and eviction

A session is pinned, and never evicted, when any of these holds:

1. It belongs to the active asset or to an outstanding `SourceSessionCoordinator.Request`
   (loading, prepared, or awaiting stored-edit adoption).
2. Its history is grouping (an in-progress gesture).
3. It is dirty: `EditPersistenceCoordinator.isDirty(assetID)`. That covers queued, in-flight,
   force-pending, and failed-save snapshots. A write acknowledgement clears an entry only if it still
   equals the acknowledged snapshot, so an old acknowledgement never clears a newer queued edit.

Export and batch paste take immutable value snapshots when accepted, so they need no pin.

`evictIfNeeded()` removes pinned-free sessions in ascending recency until both budgets hold or none
remain eligible. It runs after `saveActiveDocument` queues persistence, after `beginLoad`, after an
inactive paste is queued, and from `onDurableWrite`. It does not run at shutdown, and it never
touches `nextRevision`, so revisions stay strictly increasing across evict and reopen. Eviction is
driven by `isDirty`, never by "an acknowledgement arrived".

If pinned sessions alone exceed the budget, the coordinator stays over budget. It never drops,
truncates, or persists-and-drops an unsaved value. `peakResidentSessions` and `evictionDeferrals`
record the overshoot, and the next acknowledgement re-runs eviction.

## Undo contract

- The active photo's undo and redo, including an open gesture group, are never evicted or trimmed.
  The per-photo history cap is `EditHistory.maximumDepth` (100).
- An inactive photo's in-memory undo stack survives only while its session is resident. After a
  clean inactive session is evicted, reopening the photo starts a fresh undo stack at its saved
  state, as after a relaunch.
- Nothing is lost on eviction: the saved edit is the current durable revision, and the durable
  revision list and snapshots remain the recovery path. Reopening does not seed undo from durable
  revisions.
- Eviction never changes what a photo looks like, exports, or saves.

## Pasting to a non-resident photo

`EditClipboardCoordinator.pasteEdits` resolves the paste base for a non-resident destination from
the durable record (`EditDocumentStore.load`) before applying. If that read fails, it skips the
photo and reports it; it never substitutes a neutral or active-photo document, which would overwrite
the saved edit in the categories the paste does not touch.

## Verification

- `EditorSessionEvictionTests` cover the budget, pinning, dirty and acknowledgement ordering,
  failed-write retry, cold-reopen parity, and revision monotonicity.
- `EditClipboardCoordinatorTests` cover the durable paste base and skipped-photo reporting.
- `EditorSessionRetentionProbeTests` is window-independent. It measures estimated retained bytes for
  generated heavy documents (6 brush-mask layers plus 40 retouch spots, each history entry with a
  distinct payload) and asserts the resident set plateaus. Its byte figures estimate value payload;
  they are not RSS. One such document is about 2.45 MB, so the 192 MiB limit bites for heavy
  mask and retouch recipes and rarely for tone-only edits.
- Navigation while saving and begin-load-then-paste rely on the pin closures wired by
  `AppViewModel` and the `StoredEditAdoptionTests` fences rather than an end-to-end test.
