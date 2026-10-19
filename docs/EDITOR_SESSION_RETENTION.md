# Editor-session retention policy

Decision record for KRMA-1059, implemented by KRMA-1060; the 16 GB soak is KRMA-1064.

## Implemented (KRMA-1060)

`EditorDocumentCoordinator` holds one entry per photo (`session`, `revision`, cached document cost,
recency tick); the `sessionRevisions` side dictionary is gone. `maximumResidentSessions` (32) and
`maximumResidentSessionBytes` (192 MiB) are init parameters. `pinnedAssetIDs` and `isDirty` are
closures wired by `AppViewModel` (active asset plus `SourceSessionCoordinator.activeRequest`;
`EditPersistenceCoordinator.isDirty`). `evictIfNeeded()` runs after `saveActiveDocument` queues
persistence, after `beginLoad`, after an inactive paste is queued, and from `onDurableWrite`; it
is not run at shutdown. `peakResidentSessions` and `evictionDeferrals` are the observability
counters. `EditClipboardCoordinator.pasteEdits` loads the durable document for a non-resident
destination before applying and skips and reports a photo whose saved edit cannot be read.
Cost lives in `EditDocument.estimatedRetentionBytes`. Tests: `EditorSessionEvictionTests`,
`EditClipboardCoordinatorTests`, and the plateau case in `EditorSessionRetentionProbeTests`.

Not covered by an automated test: full `AppViewModel` navigation-while-saving and
begin-load-then-paste scenarios (7 and 8) rely on the pin closures above and the existing
`StoredEditAdoptionTests` fences rather than a new end-to-end test.

## Problem

`EditorDocumentCoordinator.sessions` (`[PhotoAssetID: PhotoEditSession]`) and `sessionRevisions`
(`[PhotoAssetID: UInt64]`) gain an entry for every photo that is opened, edited, or pasted to, and
nothing removes one except library deletion (`removeSessions`). Each `PhotoEditSession` holds a full
`EditDocument` and an `EditHistory` of up to `EditHistory.maximumDepth` (100) undo entries, so the
per-photo cost is bounded and the per-process cost is not.

## Evidence

`Tests/KromoraKitTests/EditorSessionRetentionProbeTests.swift` is window-independent and uses
generated documents: 6 brush-mask layers (12 strokes of 400 samples) plus 40 retouch spots (64
samples) per document, each history entry carrying a distinct payload so copy-on-write cannot hide
the cost. Byte figures are **estimates of value payload** (JSON-encoded size plus
`MemoryLayout<BrushSample>.stride` per sample). They are not RSS and not a device-wide guarantee.

| Edited photos | Sessions retained | History entries (depth 10) | Estimated worst-case bytes |
| ---: | ---: | ---: | ---: |
| 5 | 5 | 50 | ≈ 135 MB |
| 20 | 20 | 200 | ≈ 540 MB |
| 80 | 80 | 800 | ≈ 2.16 GB |

One heavy document ≈ 2.45 MB; one photo at the full 100-entry history ≈ 248 MB. The fixture is a
deliberate stress recipe: a typical tone-only document is a few KB, and history entries that differ
only in tone share the large arrays through copy-on-write, so the real figure sits between a few MB
and the table. The shape is the finding: retention is linear in edited-photo count with no
ceiling. No memory failure was reproduced.

## Why this is not a plain LRU

A session is correctness state, not only a cache:

| Reader or writer | Dependency on a session |
| --- | --- |
| `beginLoad` (`AppViewModel`) | `session(for:)` restores the document and undo stack; `hadInMemorySession` and `revision(for:)` are captured into `SourceSessionCoordinator.Request`. |
| `StoredEditAdoptionCoordinator` (early and late) | A resident session, or a revision that moved since the request, makes in-memory state win over the disk read. |
| `adoptStoredDocumentValues` / `adoptStoredEdits` | Create a session from a durable read (fresh undo stack). |
| `saveActiveDocument` | `commit` runs immediately before `persistence.enqueue`. |
| `EditClipboardCoordinator.pasteEdits` | `apply(_:to:)` for inactive targets; `session(for:)?.document ?? EditDocument()` is the paste base. |
| `adoptRestoredEditRevision` | `adoptHistoryPosition` rebuilds the active session from a durable revision. |
| `buildBatchRequest` (export) | Live session document wins over disk for non-active photos; a missing one means "export the durable record". |
| Admission, edited thumbnails, idle frame warmer | `admissionDocument`, `editedThumbnailDocument(Revision)`, `inMemoryDocument` read sessions as the newest document. |
| Library deletion | `removeEditorSessions` drops sessions. |
| `EditPersistenceCoordinator` | `pending[assetID]` is the dirty set; a write ack removes the entry only if it still equals the acknowledged snapshot (`pending[assetID] == snapshot`), so an old ack never clears a newer queued edit. |

Evicting a dirty session loses unsaved work. Evicting a session while a source request holds its
revision can let a stale durable read overwrite a newer edit. The policy below removes both hazards
by construction.

## Policy

### Budget (named defaults, owned by `EditorDocumentCoordinator`)

| Constant | Default | Rationale |
| --- | ---: | --- |
| `maximumResidentSessions` | 32 | Covers the filmstrip/prefetch neighbourhood plus recent back-navigation. |
| `maximumResidentSessionBytes` | 192 MiB | Under 2% of a 16 GB machine; bites only for heavy mask/retouch recipes (one worst-case full history alone is ≈ 248 MB). |

Both are constructor parameters so tests inject small values. The budget counts **all** resident
sessions, but only eligible ones are evicted (below), so the resident set can exceed it.

### Accounting

Cost of a session = `(1 + undoCount + redoCount + (isGrouping ? 1 : 0)) × documentCost`. The extra
document is the undo point held by an open gesture group. `documentCost` is a deterministic
value-payload estimate: a fixed 4 KiB shell, `count × MemoryLayout<Element>.stride` for each
variable-length collection recursively in the document and its recipes (including brush strokes,
brush and retouch samples, local layers/components, adjustment nodes, retouch spots, and eye
corrections), plus the UTF-8 byte count of retained strings. Do not encode the document or charge
array capacity. This estimate deliberately takes no copy-on-write discount, but it is not an upper
bound on allocated memory or RSS: allocator and array-capacity overhead are not captured. The 192
MiB limit is an estimated recipe-payload threshold, not a process-memory guarantee. Compute the
estimate when the session is stored (`commit`, `apply`, `adopt*`) and keep it in the entry; never
scan sessions or encode documents on a read. Also refresh the active session's cached cost when
`activeHistory` enters or leaves grouping; count its `groupingStart` document while the group is
open, even before another document commit occurs.

Recency is a monotonic tick stamped on `activate`, `commit`, `apply` and `adopt*`. Plain
`session(for:)` reads (thumbnails, admission, export) do not touch recency, so background readers
cannot keep a stale session alive.

### Pinning and eviction

A session is **ineligible** (pinned) when any holds:

1. It belongs to the active asset (`activeAssetID`), or to the asset of an outstanding
   `SourceSessionCoordinator.Request` (loading, prepared, or awaiting stored-edit adoption).
2. Its history is grouping (`isGrouping`) — an in-progress gesture.
3. It is dirty: `EditPersistenceCoordinator.isDirty(assetID)` — `pending[assetID] != nil`. That covers
   queued, in-flight, force-pending and failed-save snapshots, because `drain` keeps the entry on
   failure and removes it on success only if it still equals the acknowledged snapshot.
4. An accepted in-flight consumer needs its mutable state. Export and batch paste take **immutable
   value snapshots** at accept time (`BatchItem.document`, the pasted `EditDocument` queued via
   `persistInactiveClipboardDocument`), so they need no pin; the dirty rule already covers paste.

Mutation methods do not evict inline. Run eviction after the caller has registered any accepted
edit snapshot with persistence, after source-request pinning is established in `beginLoad`, and on
every write acknowledgement (`persistence.onDurableWrite`) after pending/dirty state is updated.
This order is required for inactive paste: `EditorDocumentCoordinator.apply` updates the session
before `persistInactiveClipboardDocument` queues its forced write. The first eviction pass must
come after that enqueue, so the dirty pin is already visible. Eviction removes eligible sessions
in ascending recency until both budgets hold or none remain eligible, and never touches
`nextRevision`.

### Over-budget behavior

If dirty, active, grouping or request-pinned sessions alone exceed the budget, the coordinator stays
over budget. It never drops, truncates, or persists-and-drops an unsaved value, and never trims an
active or pinned history to hit a number. The overshoot is bounded by the dirty set (itself bounded
by write throughput; a persistently failing write already surfaces `persistenceFailureMessage`) and
is recorded in an observability counter (`peakResidentSessions`, `evictionDeferrals`). The next
acknowledgement re-runs eviction, which is how the set shrinks after the pressure clears.

### Undo contract (user-visible)

- The **active photo's** undo and redo, including an open gesture group, are never evicted or
  trimmed. The existing 100-entry per-photo cap is unchanged.
- An **inactive** photo's in-memory undo stack survives only while its session is resident. After a
  clean inactive session is evicted, reopening the photo starts a fresh undo stack at its saved
  state — exactly what happens today after a relaunch or for a photo never opened this launch
  (`adoptStoredDocument`). This limit is intentional.
- Nothing is lost on eviction: the saved edit is the current durable revision, and the durable
  revision list/snapshots (`EditHistoryCoordinator`, the history panel) remain the recovery path.
  Reopening does **not** seed undo from durable revisions; `adoptHistoryPosition` does that only on
  an explicit restore.
- Eviction never changes what a photo looks like, exports, or saves.

### Revision fencing after eviction

`nextRevision` is a single monotonic counter that is never reset or reused. Move the per-asset
revision into the resident session entry and delete the `sessionRevisions` side dictionary.
`revision(for:)` returns the resident entry's revision, else `0`.

This is sound because eviction is only legal for assets with no outstanding request (pin 1):

- A request captures `(editSessionRevision, hadInMemorySession)` at `beginLoad`; its asset is pinned
  until the request resolves, so the value it compares against cannot be retired underneath it.
- A request begun *after* eviction captures `(0, false)`, which correctly means "disk is
  authoritative"; any edit or paste made while it is in flight creates a session with revision
  `> 0`, so `changedInMemory` is true and the stored read cannot overwrite it.
- Retiring a session cannot revive an old value: a clean session's document equals the durable
  record by definition, so the cold read returns the same document.

Write acknowledgement: edit N is enqueued, edit N+1 is enqueued during N's `store.save`; `pending`
now holds N+1, so the ack of N leaves `isDirty` true and N+1 stays pinned. Its own ack clears it and
triggers eviction. Eviction must therefore be driven by `isDirty`, never by "an ack arrived".

## Required seam in KRMA-1060: paste base for a non-resident photo

`EditClipboardCoordinator.pasteEdits` builds an inactive target's document as
`clipboard.applying(to: editor.session(for:)?.document ?? EditDocument(), …)` and then queues a full
`store.save`. For a photo with saved edits but no resident session (never opened this launch today;
any evicted photo after KRMA-1060) a category-limited paste is applied to a neutral document and
overwrites the saved edit in the other categories. Eviction widens this, so KRMA-1060 must resolve
the base from the durable record (`EditDocumentStore.load`) when no session is resident, before
applying, and must not substitute a neutral or active-photo fallback if that read fails (skip the
photo and report it).

## Integration points for KRMA-1060

- `EditorDocumentCoordinator`: inject the budget; store `(session, revision, cost, tick)` in one
  entry; track the active asset so grouping-start cost can be charged to its pinned session; refresh
  that cost on `beginGrouping`/`endGrouping`; add `isEvictable` inputs
  (`pinnedAssetIDs: () -> Set<PhotoAssetID>`, `isDirty: (PhotoAssetID) -> Bool`) as closures so the
  coordinator stays value-only; add `evictIfNeeded()`; keep `removeSession(s)` for deletion.
- `EditPersistenceCoordinator`: add `func isDirty(_ assetID: PhotoAssetID) -> Bool`.
- `AppViewModel`: wire the closures; call `editorDocument.evictIfNeeded()` from
  `persistence.onDurableWrite` and after `beginLoad`; supply the request-pinned asset set from
  `sourceSession`.
- `EditClipboardCoordinator`: durable paste base as above.
- Export, thumbnails, admission, warmer: no change — they already treat a missing session as "use
  the durable record", which is the evicted-clean case.

## Deterministic test scenarios for KRMA-1060

Inject `maximumResidentSessions = 3` and a small byte budget; use fake persistence/store seams as in
`CoordinatorBoundaryTests` and `EditPersistenceIntegrationTests`.

1. **Plateau:** open and edit 20 photos with all writes acknowledged; resident count and estimated
   bytes never exceed the budget after eviction; the probe's generated heavy documents trip the byte
   budget before the count budget.
2. **Active undo continuity:** the active photo stays resident past the budget, `canUndo`/`undo`
   work, and an open `beginGrouping` survives eviction passes with its grouping-start document
   reflected in the estimated byte total.
3. **Cold reopen parity:** evict a clean photo, reopen through `SourceSessionCoordinator`; the
   document equals the durable record, `hadInMemorySession` is false, undo is empty, and export of the
   evicted photo uses the durable document identically to the pre-eviction live one.
4. **Dirty pinning:** gate `store.save`; the photo is not evicted while queued or in flight, and is
   evicted after the ack.
5. **Write failure and retry:** a failing save keeps the session resident and over budget with the
   failure status; a later successful retry makes it evictable.
6. **Old ack, new edit:** enqueue N, enqueue N+1 while N's save is gated, release N's ack; assert
   still dirty and resident, then release N+1 and assert eviction.
7. **Navigation while saving:** switch away from a photo with a pending write; it stays pinned until
   acknowledged, and its late ack cannot publish into the new active photo.
8. **Source-adoption fence:** begin a load for an evicted photo, apply a paste to it before the stored
   read lands; `changedInMemory` is true and the stored document is not adopted. A load that
   began before eviction cannot see its asset evicted.
9. **Batch paste:** paste to N > budget inactive photos including non-resident ones; every
   destination persists base-plus-pasted values (durable base for non-resident). Gate the writes
   and assert each updated session remains resident from persistence enqueue until its write
   acknowledges; a failed write remains pinned. A failed durable-base read skips and reports that
   photo.
10. **Deletion and shutdown:** deleting a resident photo removes its session; shutdown with dirty
    resident sessions flushes them and evicts nothing.
11. **Revision monotonicity:** after evict and reopen, new revisions are strictly greater than every
    earlier one for any asset.

## Out of scope

Rendered-image, thumbnail and diagnostic-ring budgets (KRMA-999, KRMA-1007), Share Copy memory
(KRMA-1048), and real 16 GB qualification (KRMA-1064). No change to the 100-entry history cap.
