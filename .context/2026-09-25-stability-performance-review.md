# Kromora release readiness: stability and performance review

**Reviewed:** 2026-09-25, commit `b879cbc`, initially clean working tree.  
**Priority:** prevent data loss and incorrect output first, then responsiveness and resource use, then usability and maintainability. Implementation effort does not determine the ranking.  
**Recommendation:** resolve the P0 findings and the P1 correctness failures before calling this build shippable.

The architecture has useful foundations: one edit document and render pipeline, Swift 6 isolation, explicit preview generations, separate export rendering resources, bounded renderer caches, package transactions, and a substantial test suite. The most serious remaining problems occur **between these components**. A package lease does not serialize the application's separate writers; disposable indexes are accepted without checking freshness; saved Look bytes do not reach rendering; and an export fallback confuses a genuinely unedited photo with a failed edit load.

This review identified eight reproducible failure mechanisms using disposable fixtures. Two recovery probes lost the prior file. Other probes demonstrated maintenance removing an active transaction's staging, stale membership being overwritten, a stale index being accepted, lease renewal failing after a simulated pause, the wrong document reaching batch export, and replacement export failing. These are concrete reasons to prioritize reliability work over additional editing features.

## 1. Scope, evidence, and limits

Read `CLAUDE.md` and the architecture, storage, engineering, testing, library scale, and Auto performance guides. Traced production paths through package transactions/recovery, leases, imports, indexes, edit persistence, deletion, source loading, previews, rendering/cache boundaries, thumbnails, masks/analysis, export, app shutdown, menus, packaging, and CI. Checked relevant existing tests and their assumptions. This was a source and component review, not a claim that every rendering algorithm or UI interaction has been exhaustively verified.

No product source or existing tests were changed. The report's companion [ReviewProbes.swift](review-evidence-2026-09-25/ReviewProbes.swift) is an isolated review artifact. It links the real `KromoraKit` library, uses temporary directories, and removes its fixtures. Its fake renderer records export requests; it does **not** establish pixel correctness. Recovery probes use the production fault injector and explicitly constructed interruption states; they are not physical power-loss tests.

Evidence labels used below:

- **Reproduced:** observed with an isolated probe against this checkout's compiled library.
- **Source-confirmed:** the implementation and its production callers establish the behavior; the complete user workflow was not replayed.
- **Validation gap / risk:** requires the proposed runtime or hardware exercise before asserting frequency or latency.

Validation environment: arm64 macOS 27.2, build `26B5091g`; Apple Swift 6.4; Xcode 27.0, build `27A5252f`. This is newer than CI's documented Xcode 26 environment and does not establish macOS 14 compatibility by itself.

### Checks performed

| Check | Result and interpretation |
|---|---|
| `swift build` | Passed. Product build succeeds in the local Debug environment. |
| Focused `swift test --no-parallel --filter 'PortablePackageTransactionTests\|LibraryQueryControllerTests\|PortableLibrarySessionTests\|PackageEditProjectionTests\|ExportCutoverTests'` | **Blocked by test compilation**, before selected tests executed. `FakePreviewAdmissionDestination` lacks `admissionScheduleOriginalPreview()`. See F15. |
| Isolated failure probes | Eight failure mechanisms reproduced; results below. |
| Synthetic query/source diagnostics | Executed against Debug product code; see section 5. These are component measurements, not UI latency. |
| Full suite, packaged app, real camera RAW corpus, Instruments, real sleep/wake, physical interruption | Not completed in this pass. Required follow-up is specified in section 6. |

The first test attempt was stopped by compiler-cache sandbox access. Retrying with the required access exposed the actual test conformance error. The latter is the relevant repository finding; the initial permissions error is not a product defect.

## 2. Prioritized findings

**P0:** credible canonical-data loss; release blocker. **P1:** incorrect output, unreliable saving, major responsiveness/resource problem, or missing release evidence; resolve before broad release. **P2:** important follow-up for predictability, recovery, and maintainability. Priority applies to the consequence, not the implementation cost.

| ID | Priority | Finding | Evidence |
|---|---|---|---|
| F01 | P0 | Separate package writers can interfere; maintenance recovers live transactions and imports overwrite stale shards | Reproduced mechanisms + production call paths |
| F02 | P0 | Replaying an interrupted rollback can delete the restored prior file | Reproduced |
| F03 | P0 | Recovery after package relocation loses backups because journal paths are absolute | Reproduced |
| F04 | P1 | A structurally valid but stale local index is accepted as current | Reproduced |
| F05 | P1 | Package-embedded Looks are not resolved during normal editing/export | Source-confirmed |
| F06 | P1 | Batch export applies the active document to unopened unedited or unreadable photos | Reproduced normal unedited case |
| F07 | P1 | An unchanged writer loses save ability after lease expiry, including sleep-sized pauses | Reproduced time simulation |
| F08 | P1 | Startup validates package files before recovering interruptions that may have removed those files | Source-confirmed |
| F09 | P1 | Failed edit loads become editable neutral documents without an explicit recovery decision | Source-confirmed |
| F10 | P1 | Open Images, culling, and deletion perform durable filesystem work on the UI actor | Source-confirmed |
| F11 | P1 | Full-file hashing occurs in UI source construction; cache identity also repeatedly reads disk | Source-confirmed + component timing |
| F12 | P1 | Every page query filters/sorts the entire library; mutations reconstruct the entire index | Source-confirmed + component timing |
| F13 | P1 | Browsing and editing retain objects, thumbnails, and histories across the full session | Source-confirmed |
| F14 | P1 | Import scans every existing record and commit rereads complete staged originals | Source-confirmed |
| F15 | P1 | The test target currently does not compile | Observed compiler failure |
| F16 | P1 | Multiple export commands can overlap and invalidate task/progress ownership | Source-confirmed |
| F17 | P2 | Confirmed replacement in the single-export panel cannot replace the existing file | Reproduced write behavior |
| F18 | P1 | Failed rating/flag writes leave unsaved success-looking UI state without a retry queue | Source-confirmed |
| F19 | P2 | Frequent full revisions and expensive cache hits create unnecessary persistence work | Source-confirmed |
| F20 | P2 | Several disposable caches have no storage budget; cache failures can obstruct deletion | Source-confirmed; memory peaks need profiling |
| F21 | P1 | Required CI does not establish real RAW, minimum-OS, long-session, or performance readiness | Validation gap |
| F22 | P2 | Export/delete labels and recovery affordances do not match actual behavior | Source-confirmed; usability testing needed |
| F23 | P2 | Ownership contracts and tests need to follow the actual production composition | Maintainability recommendation tied to defects |

### F01 — Serialize package mutations across the entire application

**Impact:** lost catalog changes, dropped edit pointers, failed saves, or recovery deleting another operation's working files. This is the most important architectural fix.

The single process lease only proves that the process owns the package. It does not prevent simultaneous transactions within that process:

- [`EditDocumentStore.swift`](../Sources/KromoraKit/Models/EditDocumentStore.swift), `save` at line 260, appends revisions from its own actor.
- [`PortableLibrarySession.swift`](../Sources/KromoraKit/Models/PortableLibrarySession.swift), `updateLibraryState` at line 875 and removal at line 860, mutate from `MainActor`.
- Imports and maintenance execute through detached package-I/O scheduler jobs. [`ImageWorkScheduler.swift`](../Sources/KromoraKit/Models/ImageWorkScheduler.swift), lines 73–80, limits this lane to one worker, but edit saves and culling bypass it.
- [`PortablePackageMaintenance.swift`](../Sources/KromoraKit/Models/PortablePackageMaintenance.swift), `run` at line 504, calls `PortablePackageTransaction.recover` even when passed the live session's lease. Recovery treats **every uncommitted journal as abandoned** and removes staging.
- Maintenance's second asset-record read around line 624 is a check followed by a later write, not an atomic compare-and-commit. An edit can still commit after that check.
- [`PortablePackageImport.swift`](../Sources/KromoraKit/Models/PortablePackageImport.swift), catalog at line 256 and shard publication around line 443, retains complete shard snapshots across an import. A later import into a shard can overwrite intervening rating, flag, or tombstone changes even when the individual commits themselves do not overlap.

**Reproduction:** stage a live transaction, run maintenance with the same lease, then commit the live transaction. The commit fails because maintenance removed its staging file. Separately, change membership after constructing the import catalog, then import using that catalog: the affected shard has one entry instead of the expected two. The second fixture controls the interleaving at the storage boundary; it is not a real user import/culling stress run.

**Recommended fix:** introduce one package writer authority, ideally an actor, for all canonical mutations. It must own the read–plan–commit sequence, revision allocation, membership state, and maintenance. Source copying/hashing may run outside it; the commit must merge against current state inside it. Restrict recovery to exclusive startup/recovery mode before live jobs are admitted. Readers must see committed state, including during target replacement. Do not rely on scheduler configuration or repeated reads as a correctness lock.

**Acceptance:** deterministic barriers around live edit save + maintenance, import + culling, import + removal, and two edits to one asset. Require monotonic revisions, all pointers reachable, no resurrected tombstones, no lost ratings, and no recovery of a transaction whose owner is active. Run the **real composition**, not just several jobs manually put on one scheduler lane.

### F02 — Make recovery itself interruption-safe and repeatable

**Impact:** a second crash, I/O error, or failed cleanup during recovery can destroy the last good copy.

In [`PortablePackageTransaction.swift`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift), `rollback` at line 997 moves a backup back into place. The journal still describes the file as published. On replay, if the backup is now absent and the target exists, the branch around line 1012 removes that target. That target may be the **old file just restored by the previous rollback**.

**Reproduction:** fail after publication, then construct the exact filesystem state after the backup has been restored but before journal cleanup. Call `recover` again. Expected contents: `old`. Actual result: the target is missing.

**Recommended fix:** journal rollback progress durably, or use a recovery design that retains an immutable prior copy until completion is durably recorded. Distinguish “backup consumed because restoration succeeded” from “prior backup missing.” Recovery must not infer that an existing target is disposable from the old publication flag alone. Validate restored content using recorded identities/checksums. Treat failure to remove the journal as a state that can safely be replayed.

**Acceptance:** interrupt recovery before and after every restore/remove/rename and journal update, not merely forward commit. Relaunch and repeat recovery several times. The final state must remain the prior committed state, with no missing or duplicate originals, records, membership, or revision pointers.

### F03 — Keep every recovery path relative and contained

**Impact:** moving an interrupted package can lose its prior files during repair, violating the core portability contract.

[`PortablePackageTransaction.swift`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift), lines 817–835 and 924, writes absolute `backupPath` values into journals. Rollback reconstructs them using `URL(fileURLWithPath:)` at lines 1005 and 1025. After a package rename or relocation, backups are still physically inside its moved staging directory, but rollback looks under the original root. For a published replacement, it can delete the new target and then clean up the moved staging directory containing the only old copy.

**Reproduction:** fail immediately after publishing a replacement, release the test lease, rename the package root, and recover at the new location. Expected `old`; actual target missing.

**Recommended fix:** store validated package-relative backup/removal/staging paths and resolve them under the current root. Provide a safe compatibility path for existing absolute-path journals. Validate the complete journal before making any changes: package identity, transaction identity, all paths, and permissible staging locations. Recovery paths currently bypass some of the containment discipline in `PackagePath`; malformed recovery metadata must not name arbitrary external files.

**Acceptance:** recover after rename, copy to another directory, restore onto another volume, and copy to another Mac. Include interrupted deletions and maintenance moves. If an old journal cannot be safely interpreted, preserve both copies and present a repair error instead of deleting evidence.

### F04 — Version the disposable index against canonical package state

**Impact:** missing imports, reappearing removed photos, stale ratings, or a restored library appearing to have newer contents than it actually has.

[`LibraryQueryController.swift`](../Sources/KromoraKit/Models/LibraryQueryController.swift), `validated(for:)` at line 228, checks the library UUID and entry structure. It has no catalog generation, shard checksum, or commit token. [`PortableLibrarySession.swift`](../Sources/KromoraKit/Models/PortableLibrarySession.swift), lines 187–192, therefore takes an old valid index as the warm startup result. Index writes are best effort and shutdown cancels the pending index job around line 288.

**Reproduction:** construct an index, change canonical membership, and validate the old index. The package has one asset; the accepted index still has zero. The code permits the same result after a crash between package commit and index persistence. A restored or diverged copy with the same library UUID is another important case.

**Recommended fix:** commit a canonical catalog generation or digest with membership mutations, persist that token in the index, and reject mismatches. Handle package copies with the same UUID explicitly. Coalesced index writes must publish only the current generation; cancellation is safe only because reopening can prove staleness. Keep rebuild asynchronous and reconcile the partial first page with mutations admitted during rebuild.

**Acceptance:** kill after canonical commit but before index write; cancel a queued write during shutdown; restore an older backup under the same UUID; open a changed copy from another location. Reopening must reproduce canonical membership and culling state without manually deleting the index.

### F05 — Resolve saved Looks from the revision's embedded bytes

**Impact:** a saved edit changes appearance after moving a package, deleting an external Look, or replacing a `.cube` at the same path. Export can silently omit the intended Look.

[`PortablePackageEditSidecar.swift`](../Sources/KromoraKit/Models/PortablePackageEditSidecar.swift) stores `lookReferences` and implements `readEmbeddedLook` at line 384. There is no production rendering caller for that reader. [`EditDocumentStore.swift`](../Sources/KromoraKit/Models/EditDocumentStore.swift), line 233, returns only `sidecar.native.document`. [`AppViewModel.swift`](../Sources/KromoraKit/ViewModels/AppViewModel.swift), `resolvedLUT` at line 3164, resolves only the current Look library or the in-memory derived registry and explicitly prefers the latest external scan.

The embedding side also needs attention: `configureEmbeddedLooks` at line 1331 snapshots all library Look files on the main actor, then asynchronously installs the byte dictionary. A save needs an explicit guarantee that its selected Look bytes have arrived. Session-derived Looks are not in that library snapshot.

**Recommended fix:** resolve a durable edit's Look by the content hash embedded with that revision. Return or separately load its render dependencies with the document. Pin those bytes for preview, thumbnails, Auto, comparison, and export. Selecting a changed external Look should be an explicit edit. Embed session-derived Looks when used, and fail saving an unresolved required dependency with an actionable status rather than recording a supposedly self-contained revision without it.

**Acceptance:** edit with a custom Look, close, delete the external file, relocate the package, reopen with a fresh profile, and compare rendered output. Also replace the external file at the same path and save a derived Look before it exists on disk. Test actual image output, not just successful `readEmbeddedLook` calls.

### F06 — Separate batch export's per-photo document from “apply this document to all”

**Impact:** exporting a selection can produce incorrect exposure, crop, masks, or color without reporting failure.

[`AppViewModel.swift`](../Sources/KromoraKit/ViewModels/AppViewModel.swift), `makeBatchExportRequest` at line 3764, supplies nil document snapshots for never-opened photos and passes the active document as the fallback. [`ExportCoordinator.swift`](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), `resolvedDocument` at line 660, returns that fallback whenever `EditDocumentStore.load` reports `found == false`. That includes both a healthy revision-zero photo and an unreadable saved record.

**Reproduction:** active photo has exposure +2; another selected package photo has no saved edits and has never been opened. The fake renderer receives +2 for the second photo, and export reports one success. Expected per-photo exposure: zero.

**Recommended fix:** model the operation's intent explicitly: export each photo's own edits versus apply one template to a batch. For the former, a healthy missing revision means neutral edits; an unreadable revision means an item failure or explicit recovery choice. Carry per-photo resolved Look bytes as part of the snapshot. Do not substitute active-photo state after a load error.

**Acceptance:** mixed selections containing active edited, inactive edited, never-opened neutral, unreadable, newer-schema, and missing-Look photos. Assert the exact request for every item and compare actual exports with each photo's settled preview. Existing same-document batch tests describe the legacy/template contract and do not prove the selected-photo product contract.

### F07 — Make the writer lease survive ordinary suspension safely

**Impact:** saving stops after a laptop sleep or a sufficiently long blocked package operation, even when nobody else has acquired the package.

[`PortablePackageTransaction.swift`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift), lease duration at line 180 and `renew` around line 290, requires the current expiry to still be in the future. `assertOwnership` permanently records session loss after expiry. [`PortableLibrarySession.swift`](../Sources/KromoraKit/Models/PortableLibrarySession.swift), heartbeat at lines 227–273, queues renewals onto the same single-worker lane as long imports and maintenance. `renewAfterWake` invokes the same renewal; it does not recover unchanged ownership.

**Reproduction:** acquire the normal lease, advance injected time by 181 seconds without changing its owner, and renew. Renewal fails as expired. This simulates the lease consequence of suspension; it is not a real sleep/wake test. Per-file renewal during import helps batches, but one slow copy/hash/commit can still exceed the lease window.

**Recommended fix:** use explicit ownership fencing and process/session liveness to distinguish an unchanged suspended writer from a genuinely replaced owner. Serialize renewal with lease transfer/recovery so read-check-replace races cannot overwrite another owner. Give heartbeat execution independence from long bulk I/O and handle wake notifications directly. If ownership really is lost, retain unsaved snapshots and provide a safe reconnect/retry flow.

**Acceptance:** real sleep for several minutes, background suspension, one slow file exceeding the lease duration, wall-clock changes, and takeover by a second process. The original session must either safely continue saving or clearly preserve unsaved edits; two writers must never become valid simultaneously.

### F08 — Recover before assuming the manifest and shards are intact

**Impact:** some journaled interruptions can leave a package that ordinary startup cannot repair.

[`PortableLibrarySession.swift`](../Sources/KromoraKit/Models/PortableLibrarySession.swift), lines 81–95, opens/validates the package before acquiring/recovering its writer lease. [`PortablePackageTransaction.swift`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift), lines 902–934, replaces a target using an old-target-to-backup move followed by a staged-file-to-target move. Between those operations, the target does not exist.

If that target is `manifest.json`, `openForQuery` fails before the lease recovery path runs. The eager open path similarly depends on membership shards. A torn/invalid lock file from interruption during initial lease creation also returns `.invalid` without a normal repair path. These are source-confirmed windows; the existing fault injector fires after larger boundaries and does not reproduce every internal rename gap.

**Recommended fix:** create a small recovery bootstrap that validates root/lease/journal metadata sufficiently to obtain exclusive recovery authority, performs idempotent recovery, and only then opens the canonical manifest and catalog. Preserve malformed recovery evidence and provide a recovery error with next steps. Use atomic replacement where appropriate, while keeping the larger multi-file transaction recoverable.

**Acceptance:** child-process termination between backup rename and target publication, during initial lock payload write, and during initial package creation. Reopening must recover the previous package or provide an explicit repair path without silently creating an empty library.

### F09 — Do not silently turn an unreadable saved edit into a new neutral baseline

**Impact:** damaged or newer-version edits can be replaced by a fresh neutral-derived revision after the user touches a slider. The user may believe the old edit has been recovered when it has only been bypassed.

[`EditDocumentStore.swift`](../Sources/KromoraKit/Models/EditDocumentStore.swift), `load` at line 208, returns a neutral document with `found: false` for errors. [`AppViewModel.swift`](../Sources/KromoraKit/ViewModels/AppViewModel.swift), `adoptStoredEdits` at line 1989, adopts that document when the session is pristine, regardless of the actionable status, and only then sets the status message. Normal edit persistence remains available.

The document decoder does correctly reject a newer document version; this finding concerns what the application does **after** that rejection. Immutable prior revisions offer some recovery, but automatic compaction retains a limited set and no user decision establishes a replacement baseline.

**Recommended fix:** expose a typed load result: pristine, loaded, recoverable failure, or unsupported version. Preserve the prior document/revision and freeze destructive persistence until the user chooses repair, a validated earlier revision, or an explicit new version. Make this same contract govern export, thumbnails, and prefetch so each consumer does not invent a different fallback.

**Acceptance:** missing XMP, corrupt native JSON, unavailable package volume, newer edit schema, and transient read failure during publication. Merely opening/navigating must not enqueue a replacement. Recovery decisions must be visible and reversible.

### F10 — Remove durable filesystem work from the UI actor

**Impact:** beachballs during normal import/culling, delayed input, and apparent hangs on large or slow volumes.

Concrete paths:

- [`AppViewModel.swift`](../Sources/KromoraKit/ViewModels/AppViewModel.swift), `openImages` at line 2062, intentionally calls the synchronous importer. `openImageDialog` calls it in production. Copying, hashing, full syncs, commits, and synchronous index persistence therefore run on `MainActor`.
- [`PortableLibrarySession.swift`](../Sources/KromoraKit/Models/PortableLibrarySession.swift), `updateLibraryState` at line 875, renews the lease, reads/writes a shard, commits a transaction, and reconstructs the index synchronously for each rating/flag.
- [`LibraryDeletionCoordinator.swift`](../Sources/KromoraKit/ViewModels/LibraryDeletionCoordinator.swift), line 77, calls synchronous package removal from its main-actor loop.
- `openSourceFolder` at line 2513 discovers its file list synchronously before admitting the worker.

**Recommended fix:** use asynchronous workflows for every production import entry point and canonical mutation. Publish progress, an operation identity, cancellation, and a durable result. Adapt tests to the asynchronous publication contract instead of making the UI synchronous to satisfy immediate assertions. Keep only small state publications on the main actor. This should use F01's writer boundary, so performance and correctness improve together.

**Acceptance:** use a slow external volume, hundreds of RAWs, multi-photo removal, and rapid rating keys while measuring main-thread stalls. UI input, cancel, and window movement must remain responsive. Verify cancellation preserves already committed imports.

### F11 — Remove repeated source I/O and hashing from render admission

**Impact:** RAW grid scrolling, thumbnail completion, preview admission, and export initiation can stall before GPU work even starts.

[`ImageSource.swift`](../Sources/KromoraKit/Models/ImageSource.swift), `makePortableIdentity` around line 190, reads and hashes the full file even when a portable identity was supplied. Without one, it hashes the same file again to derive the fallback asset ID. [`PortablePhotoIdentity.swift`](../Sources/KromoraKit/Models/PortablePhotoIdentity.swift), line 72, implements this with whole-file `Data(contentsOf:)`.

These initializers run in main-actor paths, including [`EditedThumbnailCoordinator.swift`](../Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift), lines 149 and 270. Even the stale-thumbnail completion check reconstructs the source. [`ExportCoordinator.swift`](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), `sourceAccess` around line 635, reconstructs a source without passing `item.portableIdentity`.

`ImageSource.cacheIdentity` also calls `PhotoSourceFingerprint.file` on each access. [`PhotoAsset.swift`](../Sources/KromoraKit/Models/PhotoAsset.swift), line 152, opens the file and reads/hashes its first and last 64 KiB. Many renderer revision/cache checks access this property. Once a signature changes, the immutable captured signature is not updated, so repeated accesses can continue performing full-file rehashes.

**Recommended fix:** use the package's committed source hash for managed immutable originals. Resolve an identity once per source admission off the main actor, then pass it through preparation, preview, masks, thumbnails, and export. Detect external changes using a deliberate invalidation policy; recompute once and publish a new source generation. Keep cryptographic verification available at import/scrub boundaries. Do not replace strong identity with path-only keys.

Also precompute immutable LUT fingerprints: `CubeLUT.cacheFingerprint` hashes the complete table each time, and renderer cache keys request it repeatedly. A 65³ RGBA Float32 table is about 4.2 MiB; its content hash should be computed when the table is created.

**Acceptance:** instrument bytes read and hash invocations during a warm slider drag and thumbnail publication. An unchanged managed source should incur zero source reads for identity checks in that hot path. A replaced original must trigger exactly one new generation and invalidate all dependent results.

### F12 — Make paging cost proportional to a page

**Impact:** UI stalls grow with total catalog size even when only 500 items are displayed.

[`LibraryQueryController.swift`](../Sources/KromoraKit/Models/LibraryQueryController.swift), `page` at line 538, filters and sorts every entry for every page. `entry(for:)` at line 202 is linear. `applying` at line 137 rebuilds a dictionary and validates/sorts a new full projection. [`PortableLibrarySession.swift`](../Sources/KromoraKit/Models/PortableLibrarySession.swift), `applyIndexDelta` at line 399, performs that reconstruction on the main actor.

[`LibraryBrowsingCoordinator.swift`](../Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift), `openPortableAsset`, scans pages to find an off-window asset. Each page repeats the full query, creating potentially many full sorts. It also has a hard stop above 200,000 page positions.

**Recommended fix:** maintain UUID lookup and ordered query results keyed by catalog generation + filter + sort. Page by slicing a stable result; update changed entries incrementally. Move nontrivial query work off the main actor and reject stale query publications. At larger scales, an indexed local database is appropriate if it remains disposable and respects the Apple-only dependency constraint. Add an ID-to-query-position lookup rather than searching every page.

**Acceptance:** measure first query separately from repeated page access, selection lookup, rating mutation, and locating an off-window asset at 1k/10k/100k. Verify work counts as well as wall time: unchanged subsequent pages must not sort the entire collection again. Retain deterministic ordering and stable UUID selection.

### F13 — Bound the entire browsing/editing working set

**Impact:** memory and per-scroll CPU grow throughout a long shoot review, despite bounded low-level caches.

[`ImageCollection.swift`](../Sources/KromoraKit/Models/ImageCollection.swift), `appendPortableWindow` at line 336, appends pages without evicting old ones. Each item retains its original thumbnail and potentially a separate edited thumbnail. `releaseThumbnail` at line 472 removes demand and cancels unfinished work; it does not release a completed image. Evicting `PlatformThumbnailProvider`'s 32 MiB cache cannot free images still retained by items.

[`EditorDocumentCoordinator.swift`](../Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift), lines 22–24, keeps unbounded session and revision dictionaries. Each session may own an [`EditHistory`](../Sources/KromoraKit/Models/EditHistory.swift) with 100 undo and 100 redo snapshots. The per-photo depth limit does not bound memory across thousands of photos, particularly brush-heavy documents.

The mosaic view also maps all loaded entries and derives visibility over accumulated rows. SwiftUI's lazy row hosting bounds hosted views, not these retained model arrays and raster references.

**Recommended fix:** implement a real window with evictable pages and a bounded thumbnail working set. Preserve selection globally by UUID; derive batch actions from that authority, not only loaded items. Bound inactive edit-session/history memory by bytes and recency, retaining dirty sessions until durable. Account for original plus edited images and all renderer instances in a process-level memory policy.

**Acceptance:** scroll forward and backward through 10k+ photos, edit hundreds with masks, and trigger memory pressure. After warming, resident memory must reach a plateau rather than scale with every photo ever visited. Test return navigation, undo semantics after eviction, hidden selection, and selected export across page eviction.

### F14 — Make ingestion incremental and keep its memory bounded through commit

**Impact:** adding one photo becomes slower as the catalog grows; a corrupt unrelated record can block ingestion; large originals create avoidable transient memory and I/O.

[`PortablePackageImport.swift`](../Sources/KromoraKit/Models/PortablePackageImport.swift), `PortablePackageImportCatalog.init` at line 260, opens all membership shards and all live asset records to build duplicate hashes. An unreadable record throws and prevents construction of the catalog. The existing scale documentation explicitly excludes record-backed import from its generated fixture.

Staging supports chunked copy/hash, but [`PortablePackageTransaction.swift`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift), lines 797–811, validates each staged file using `Data(contentsOf:)`, allocating and hashing the entire original again. The same file already passed a streaming hash in staging. Every file also creates a durable journal and multiple synchronization points. Large single files can hold the only package worker long enough to affect F07.

**Recommended fix:** maintain a content-hash projection incrementally with canonical change generations, or include the necessary immutable hash in a suitable catalog summary. Rebuild it asynchronously and report damaged records individually. Use the existing chunked hashing approach during commit verification; do not weaken checksums. Measure and reduce redundant passes/sync work through safe transaction batching and better journal design. Maintain per-item outcomes and cancellation boundaries.

**Acceptance:** import one file into real 1k/10k/100k packages with records; include one unrelated damaged record. Measure time before first progress, source/staging bytes read, peak RSS, and cancellation delay with large RAW/TIFF inputs and slow media. Metadata-only scale fixtures cannot validate this path.

### F15 — Restore a compilable test gate

**Impact:** the intended regression suite provides no executable protection for this revision until it builds.

Observed compiler error at [`PreviewAdmissionCoordinatorTests.swift`](../Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift), line 184: `FakePreviewAdmissionDestination` does not conform to `PreviewAdmissionDestination`. The protocol requires `admissionScheduleOriginalPreview()` in [`PreviewAdmissionCoordinator.swift`](../Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift), line 35. The fake lacks it. Filtering tests does not avoid compilation of this file.

**Recommended fix:** update the fake to record the required behavior and assert that behavior in the relevant comparison-preview tests. Re-run warning gate, deterministic and serial lanes. Verify on the supported CI toolchain as well as the local one; the missing source method is directly visible, but this review only executed the local toolchain.

**Acceptance:** clean compilation of all tests and recorded lane results for the release commit. Do not use stale `--skip-build` binaries as evidence for this checkout. This review deliberately leaves the test source unchanged because the task is an evaluation.

### F16 — Give exports explicit admission and operation ownership

**Impact:** repeated menu commands can run multiple full-resolution exports, make progress lie, and leave work outside shutdown/cancellation ownership.

[`MenuCommands.swift`](../Sources/KromoraKit/Views/MenuCommands.swift), lines 121–125, always posts export commands. [`ExportCoordinator.swift`](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), `performExport` at line 243 and batch dialog at line 318, do not reject or queue an operation when already exporting. They overwrite `singleTask` or `batchTask`. An older completion clears shared state and can clear a newer task handle. The dedicated export engine prevents direct display-actor monopoly, but does not make this task ownership safe.

**Recommended fix:** use one explicit export queue or reject a second start while an operation is active. Give each operation an ID; only its own completion may clear its state. Track all admitted work through shutdown. If single and batch exports may overlap by design, give them separate progress and a combined resource budget.

**Acceptance:** rapid repeated Cmd-S, selected export while single export is running, two batches, cancel then immediately restart, and quit during overlap. Assert exact work counts, consistent progress, ownership of every task, and bounded raster memory.

### F17 — Honor the single-export replacement choice

**Impact:** saving to an existing output fails even after the save panel permits replacement.

[`ExportCoordinator.swift`](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), `write` at line 596, always uses `moveItem` to commit the temporary output and deliberately refuses existing destinations. This is a useful batch collision policy but is also applied to single export after `NSSavePanel`.

**Reproduction:** export to a pre-existing target using the single-export API. The original stays safe, but the operation reports an item-already-exists failure instead of replacing it.

**Recommended fix:** carry an explicit destination policy from the panel. Use a safe atomic replace when replacement was chosen; preserve create-new semantics for batch naming. Keep the old output intact if encoding/writing/replacement fails. Retry a fresh name for a batch collision that appears after reservation where appropriate.

**Acceptance:** replace confirmed, replacement declined, write failure, disk full, and another process creating a batch destination. Verify file contents and completion reporting, including cancellation immediately after commit.

### F18 — Make rating/flag failures durable and truthful

**Impact:** culling decisions can disappear on relaunch while the current UI still displays them as applied.

[`LibraryBrowsingCoordinator.swift`](../Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift), lines 219–269, changes `ImageCollection` first, then attempts the package write. On failure it shows an error but neither rolls back the optimistic state nor retains a durable retry request. The caller subsequently writes success text such as “Rated … stars,” replacing the status text from the error. Unlike edits, culling changes are not part of the termination persistence queue.

**Recommended fix:** route culling through the writer and a pending mutation model. Either publish only after commit or explicitly mark optimistic values pending/failed, retaining retries until saved. Coalesce repeated rating changes for one UUID. Make undo participate in the same durability rules and include pending culling in quit handling.

**Acceptance:** fail the shard write once, remove the volume, expire/replace the lease, undo while a write is pending, then retry/relaunch. The user must be able to distinguish saved, pending, and failed values, and no success banner should overwrite a save failure.

### F19 — Reduce edit-save amplification and expensive “cache hits”

**Impact:** busy storage, growing revision directories, slow navigation, and increasing save latency on mask-heavy photos.

[`EditPersistenceCoordinator.swift`](../Sources/KromoraKit/ViewModels/EditPersistenceCoordinator.swift), lines 19 and 79–108, checkpoints every 250 ms and serially drains pending assets. Every persisted snapshot becomes a complete native JSON revision plus a base64 document in XMP. [`PortablePackageEditSidecar.swift`](../Sources/KromoraKit/Models/PortablePackageEditSidecar.swift), line 307, scans both revision directories to allocate each next revision. [`EditDocumentStore.swift`](../Sources/KromoraKit/Models/EditDocumentStore.swift), lines 218–233, reads/decodes the complete sidecar pair **before** checking its decoded-document cache.

These policies favor defensive verification but repeat substantial work. Many edits can produce many full revisions per gesture; large brush definitions amplify the cost. Maintenance then scans records to compact them. A failed first pending asset also stops the current drain, leaving other assets pending until another edit or flush retries.

**Recommended fix:** separate short-lived crash protection from retained user revisions, with a bounded dirty journal or equivalent recovery record. Coalesce slider work and commit a retained revision at meaningful gesture boundaries while meeting an explicit maximum unsaved interval. Let the serialized writer allocate monotonic revisions. Validate immutable sidecars on first load and on a trustworthy generation change; use background scrubbing for integrity without reparsing XMP on every healthy cache hit. Add backoff and fair handling of unrelated dirty assets after a failure.

**Acceptance:** instrument bytes written, sync calls, revisions created, main-thread time, and save backlog during a 10-second slider drag and large brush session. Repeat after thousands of revisions. Crash recovery must preserve the promised recent-edit window even after reducing amplification.

### F20 — Budget disposable storage and decouple cleanup from canonical actions

**Impact:** disk growth, repeated directory scans, large transient mask allocations, or inability to remove a photo because its disposable cache cannot be cleaned.

[`MaskStore.swift`](../Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift), [`PhotoAnalysisCache.swift`](../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift), and [`CurrentEditMeasurement.swift`](../Sources/KromoraKit/Models/PhotoAnalysis/CurrentEditMeasurement.swift), cache at line 1332, have no corresponding byte/age eviction policy. In contrast, `PreviewDiskCache` already has a 1 GB cap. Per-asset removal scans/decodes the cache directory; deleting many photos repeats that work. `LibraryDeletionCoordinator.delete` treats cache-removal failure as a reason to skip canonical removal.

Mask pixels use binary Float32 sidecars, which is a substantial improvement over inline JSON. Nevertheless, a 60 MP Float32 mask is about 240 MB; loading creates both `Data` and a Float array, and normalization/storage can add transient allocations. Several masks and concurrent export/analysis increase peak memory beyond renderer cache counters. This is a resource-risk calculation, not a measured OOM in this review.

**Recommended fix:** use per-asset cache organization or indexed ownership, byte/age budgets, batched deletion, and lazy cleanup. Canonical removal should not depend on deleting rebuildable caches. Distinguish cancellation from cache I/O failure. Add process-wide admission for large mask/analysis/export buffers and profile tiling or mapped storage where it helps. Expose cache size/purge controls without confusing them with originals or edits.

**Acceptance:** read-only/missing/full cache directories, 60–100 MP masks, many selected deletions, and sustained multi-photo Auto/export. Cache failure should degrade performance or provide a clear feature error, never imply that canonical content was lost or removed when it was not.

### F21 — Turn release performance and recovery evidence into required checks

**Impact:** a green standard CI run currently does not prove the product's central RAW workflow is stable or responsive on its supported machines.

[`scripts/ci-tests.sh`](../scripts/ci-tests.sh) keeps real RAW and performance methods optional. [CI](../.github/workflows/ci.yml) runs on macOS 26 only. The smoke job treats exit code 2 (no accessible WindowServer) as successful deferral. The package job does not exercise the direct-distribution configuration through an explicit environment setting. These are reasonable PR-cost choices, but insufficient as the final release gate.

[Library scale evidence](../docs/LIBRARY_SCALE_REGRESSION.md) explicitly uses packages without originals or asset records and does not measure actual rendered grid frame times. Its scheduler test serializes the test writers through the scheduler, which does not establish F01's real app composition. [Auto performance evidence](../docs/AUTO_PERFORMANCE.md) is a dated Debug baseline using synthetic images and excludes decode from its typical target. Those limits are documented correctly; a release decision must retain them.

**Recommended fix:** keep fast PR gates, then require a repeatable release-candidate lane with licensed camera fixtures, the packaged sandboxed app, a logged-in UI session, macOS 14 runtime coverage, the currently supported OS, and representative lower-memory hardware. Test each shipping architecture and distribution configuration. Record commit, toolchain, hardware, corpus, cold/warm state, and artifact paths.

**Acceptance:** section 6's release matrix is green for the exact candidate, with explicit outcomes for skipped/unavailable environments. A deferred UI run must remain a release task, not count as a passed UI test.

### F22 — Align product language and recovery controls with actual behavior

The highest-value usability work at this stage is helping users understand whether work is saved, what an export contains, and how to recover a removed photo.

- **“Export Originals…” renders edits.** [`MenuCommands.swift`](../Sources/KromoraKit/Views/MenuCommands.swift), line 124, invokes selected full-resolution rendered export. Rename to “Export Selected…”/“Export Edited Photos…” unless implementing a true original-byte copy path. Users may reasonably interpret “originals” as unchanged RAWs.
- **Deletion guidance names the wrong destination.** [`LibraryGridView.swift`](../Sources/KromoraKit/Views/LibraryGridView.swift), line 40, tells VoiceOver users that managed originals move to macOS Trash. [`PortablePackageTrash.swift`](../Sources/KromoraKit/Models/PortablePackageTrash.swift) moves them into package quarantine. Show the actual location and provide restore/reclaim controls with separate semantics.
- **Recovery primitives need application workflows.** Backup, restore, validation, and quarantine restoration are substantial model implementations, but a search of the view/coordinator paths did not find user-facing backup/restore/quarantine commands. Add “Verify Library,” “Back Up,” and “Restore Removed Photos” workflows after the underlying correctness fixes. They need consistent writer/persistence coordination.
- **Concurrent work competes for one status line.** [`StatusBar.swift`](../Sources/KromoraKit/Views/StatusBar.swift) selects Photos import before export before Auto. A simultaneous export can lose its visible cancel control, and per-item failures are overwritten by progress messages. Provide an activity list and a retained completion/failure summary with retry/reveal actions.
- **Make save state persistent and scoped.** Show saved/pending/failed state per affected photo or operation, with a recovery action. A transient sentence that another workflow overwrites is insufficient for saving confidence.
- **Exercise accessibility on real controls.** Native sliders and existing labels are useful foundations. Verify grid keyboard range selection, scroll/page changes, focus after errors, mask manipulation, and progress announcements with VoiceOver. Fix the concrete inaccurate hints first; this pass did not perform an accessibility session.

### F23 — Simplify ownership contracts before expanding features

The key maintainability problem is duplicated authority and ambiguous contracts, not merely file size. Nonetheless, `AppViewModel.swift` is about 4,300 lines and `RenderEngine.swift` about 2,531, so tracing the real composition is expensive.

Recommended boundaries, in consequence order:

1. **One canonical package writer and recovery authority** with committed snapshots for readers. Remove synchronous UI mutation bypasses.
2. **One typed edit-load contract** shared by editor, export, thumbnail, and prefetch. Include render dependencies and explicit failure state.
3. **One selection authority independent of loaded pages.** The package query model and collection mirror currently require manual synchronization; F13's eviction work must not make actions depend on visible objects.
4. **One operation model for admission, progress, cancellation, durable completion, and errors.** Export's task overwrites and culling's missing retry state are examples of the cost of inconsistent lifecycle policies.
5. **One observable resource ledger** across display/export/analysis engines, masks, thumbnails, histories, and disk caches. Per-cache limits do not bound total process use.
6. **Production-composition integration tests.** Existing lower-level coverage is valuable, but isolated fake/scheduler tests must be supplemented by the assembled app collaborators, especially for save/maintenance/import overlap.
7. **Current documentation and comments.** Several comments still describe retired folder/trash behavior, refer to old steps/tickets, or claim all package paths are relative. Keep current invariants beside the owner and move historical transcripts out of source comments. Fix guidance that overstates a guarantee as part of the corresponding behavior change.

Extract cohesive owners after establishing those contracts. Avoid a broad file-splitting exercise that preserves the same competing write paths under new names.

## 3. Reproduction results

The companion probe intentionally reports observed results instead of asserting success, so it can be used as a before/after diagnostic. A zero process exit code does not mean these behaviors are correct.

| Probe | Expected | Observed |
|---|---|---|
| Relocate interrupted replacement, then recover | Prior `old` contents | Target **missing** |
| Replay after prior backup restoration but before journal cleanup | Prior `old` contents retained | Target **missing** |
| Validate pre-mutation index after adding canonical membership | Reject/rebuild old index | Accepted index count **0**, canonical count **1** |
| Run maintenance while a live transaction is staged | Live transaction protected | Subsequent commit fails: staged file missing |
| Import with catalog snapshot after membership changed | Preserve change and add imported entry | Affected shard has **1** entry, expected **2** |
| Renew unchanged lease after 181-second simulated pause | Safe continuation or recoverable reconnect | Expired lease error |
| Export unopened neutral photo while active exposure is +2 | Export request exposure **0** | Export request exposure **+2**, counted successful |
| Single export to existing destination | Replace when caller/panel authorizes it | File-already-exists failure |

To rerun with the Xcode-backed build layout used here:

```sh
swift build
swiftc -parse-as-library -swift-version 6 \
  -module-cache-path /tmp/kromora-review-module-cache \
  -I .build/out/Products/Debug -L .build/out/Products/Debug -lKromoraKit \
  .context/review-evidence-2026-09-25/ReviewProbes.swift \
  -o /tmp/kromora-review-probes
/tmp/kromora-review-probes
```

Other SwiftPM versions use a different products directory; point `-I` and `-L` at the directory containing this checkout's built `KromoraKit.swiftmodule` and `libKromoraKit.a`. The probes create no persistent user library and do not launch the application. The synthetic stale-catalog fixture is designed to demonstrate overwrite behavior and does not contain a complete photo corpus.

## 4. Existing strengths to preserve

- Explicit preview/source/revision publication fences, cancellation seams, and separated preview coordinators are the right defense against late frames. Keep them while removing expensive identity reads.
- Export has a dedicated renderer and serial batch loop. Preserve display responsiveness and bounded full-resolution work when introducing operation admission.
- There is one shared rendering pipeline for preview/export, with scale and quality policies. Performance fixes should retain geometry, color, and mask parity.
- Original thumbnails already use embedded previews through ImageIO. The improvement needed is correct lifetime/admission and eliminating full-file hashing around that fast path.
- `CubeLUT` parsing has size, file, line, and metadata limits; edit decoding rejects newer document versions; package paths have containment validation. Extend these protections to recovery and error handling instead of assuming all input boundaries are equally protected.
- Edit snapshots are retained after write failure and normal quit offers retry/cancel/discard. Extend this approach to culling and lease reconnection.
- Backup/restore validation distinguishes canonical failures from rebuildable gaps. Keep that distinction in UI and release tests.
- Existing signposts, cache counters, generated fixtures, and separate CI lanes are valuable. They make the proposed measurements practical.

## 5. Performance evidence and proposed budgets

### Measurements from this pass

The probe constructs in-memory index entries with random UUIDs and reverse-numbered filenames, then makes ten page requests at each scale. Timing includes the full `page` call and excludes fixture/index construction. All calls use the same unchanged query. These values are **Debug component diagnostics on one machine**, without a renderer, real package I/O, or hosted SwiftUI views. They demonstrate repeated-query scaling; they are not shipping latency claims or statistically meaningful tail percentiles.

| Entries | Ten calls: median | Maximum | Returned items across calls |
|---:|---:|---:|---:|
| 1,000 | 43.46 ms | 44.83 ms | 1,000 |
| 10,000 | 391.98 ms | 394.93 ms | 5,000 |
| 100,000 | 5,032.60 ms | 5,074.48 ms | 5,000 |

At 1k, later requests are past the end, but still pay for the full sort. This is itself useful evidence for F12. Dataset/order, build mode, and hardware differ from the checked-in scale baseline; do not describe these differences as a measured regression against that baseline.

A separate generated **32 MiB** file probe took **23.40 ms** to construct one `ImageSource` without an existing identity and **99.93 ms** for 1,000 repeated fingerprint accesses. This is warm local I/O with synthetic bytes, not RAW decode or external-drive performance. Code inspection establishes the whole-file reads and repeated sampled reads; the timing illustrates that identity is not a free value operation.

### Suggested release targets to establish and measure

These are proposed acceptance budgets, not results already achieved. Set a named reference Mac and corpus before adopting them.

| Workflow | Proposed acceptance direction |
|---|---|
| UI actor | No copy, full-file hash, catalog sort, full sync, or mask rasterization in input handlers; investigate any main-thread stall over 50 ms |
| Settled warm paging | Repeated 500-item page retrieval below 16 ms on reference hardware, independent of total catalog size after query preparation |
| Slider feedback | Record input-to-presented-frame p50/p95/p99; initial p95 target below 100 ms, with final-quality settling measured separately |
| Photo navigation | Measure first useful embedded/cached frame and final developed frame separately, cold and warm; initial useful-frame p95 target below 200 ms when a local preview is available |
| Import | UI remains responsive; progress before expensive catalog work; cancellation acknowledged promptly between bounded copy chunks; committed items retained |
| Memory | Stable plateau during long browse/edit sessions; track process RSS, Metal allocations, and transient full-resolution work together |
| Auto | End-to-end user wait, including source preparation, plus stage breakdown; maintain output-quality gates while reducing repeated analysis/render work |
| Export | Correct per-photo bytes first; measure throughput and simultaneous editing latency, peak memory, and cancellation delay |
| Persistence | Bounded dirty interval with visible save state, no lost canonical changes under interruption, and measured write/sync amplification |

Use sufficiently many samples for the percentile being reported. Three samples do not meaningfully characterize p99.9. Preserve individual outliers and traces, especially when they align with filesystem or memory-pressure work.

## 6. Release verification matrix

| Area | Required scenarios | Pass condition |
|---|---|---|
| Transaction integrity | Real edit + maintenance, import + culling/removal; forced barriers and repeated stress | One writer authority; no missing originals, revisions, tombstones, or catalog changes |
| Recovery | Kill between every file/journal step; kill again during recovery; relocate interrupted package | Repeated recovery converges without deleting prior committed data |
| Storage failures | Disk full, denied writes, missing cache folder, unplug/replug managed volume, corrupt lock/journal | Actionable errors; dirty state retained; rebuildable cache failures isolated |
| Index coherence | Crash after canonical commit; canceled index write; older backup/newer copy with same UUID | Automatic stale detection and faithful reconstruction |
| Document portability | External Look deleted/replaced; clean profile; derived Look; newer/corrupt edit revision | Saved render reproduced or explicit recovery error; no active-photo fallback |
| Sleep/ownership | Sleep >3 minutes, long blocked I/O, process suspension, another process takeover | Safe continued saving or recoverable paused state with fencing |
| Export | Mixed edited/neutral selection, missing dependencies, duplicate filenames, authorized replace, repeated starts, cancel/quit | Exact per-photo result; accurate counts; bounded tasks and buffers |
| RAW fidelity | Licensed representative camera files, orientations, WB/highlights, crop/rotation, masks, color space, JPEG/TIFF/PNG | Preview/export parity within declared tolerances; correct metadata/location policy |
| Large-library use | Real 1k/10k/100k packages, forward/back scrolling, search/sort, culling, off-window selection/export | Predictable query cost, correct selection, flat retained working set |
| Long edit session | Hundreds of edited photos, dense brush histories, repeated Auto, concurrent export | No monotonic resource growth; responsive UI; reproducible output |
| Platform/distribution | macOS 14 runtime, current supported runtime, shipping CPU architectures, sandboxed signed package, direct distribution if shipped | Same critical workflows pass; no hidden reliance on unsandboxed `swift run` |
| Accessibility/recovery UX | VoiceOver/keyboard culling, error dialogs, concurrent activities, quarantine restore | Accurate labels, maintained focus, discoverable save/recovery state |

Run Debug for diagnostics and Release for performance, with CPU/GPU/thermal and cold/warm conditions recorded. Use temporary fixture packages for destructive fault injection. Required artifact set: lane results, corpus manifest, peak memory, input-to-present timing, integrity scrub before/after, and traces for outliers.

## 7. Recommended implementation order

1. **Establish trustworthy evidence:** fix F15 so regressions can execute; preserve the eight reproductions as regression scenarios.
2. **Protect canonical data:** F01–F04 and F08. Implement writer ownership, repeatable/portable recovery, and index freshness together because they share commit boundaries.
3. **Protect edit/output meaning:** F05–F07, F09, F16–F18. Pin dependencies, separate load outcomes, handle sleep, and make export/culling operation state truthful.
4. **Remove interactive stalls:** F10–F12 and F14. Fix UI I/O and identity construction before spending time tuning Metal kernels; they can delay work before it reaches the GPU.
5. **Bound sustained resource use:** F13, F19, F20. Measure long-session memory, revision/disk growth, and large-mask peaks across the whole process.
6. **Prove the release and expose recovery:** F21–F23. Run the real-world matrix and align labels, activity reporting, and recovery actions with the corrected contracts.

The broad feature roadmap can continue after these guarantees are established. For this release, the largest gain is making the current editing, culling, import, and export workflows reliably preserve the user's intended result under ordinary long sessions and abnormal interruptions.
