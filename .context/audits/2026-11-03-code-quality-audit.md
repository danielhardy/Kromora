# Kromora code quality, stability, and performance audit — 2026-11-03

Historical assessment of `main` at `b7e46d5c01dcc8057f48c8872e069801e3e30af9`.
The working tree was clean at the start. This audit adds this report and disposable-probe
evidence under this directory; it changes no application code, shipping resources, tests,
configuration, or issue records. `.context/audits/` did not exist in this checkout. The format
follows the existing [October 19 review](../2026-10-19-release-readiness-review.md).

## Assessment

Kromora has a credible native engineering foundation. The shared rendering pipeline, package-owned
data, explicit resource ownership, Swift 6 checking, and focused regression tests are substantial
strengths. The code is well beyond a collection of disconnected feature demos.

It does **not yet establish the exceptionally stable, consistently performant product this audit
was asked to assess**. Two reproduced defects can change what a saved photo looks like after
reopening. Other reproduced defects undermine advertised concurrency, shutdown, memory, and
analysis-quality contracts. These deserve priority over adding features or rearranging files.
I would hold a public release for findings 01 and 02, and resolve the resource/lifecycle defects
03–06 before claiming long-session stability.

The principal maintainability concern is accumulated orchestration and partially overlapping
contracts. The code often describes the right invariant, but a nearby path implements only part
of it: cancel versus actually finish, embed a Look versus resolve it, bound current documents
versus account for their history. More abstractions alone will not fix that. Fewer authorities,
explicit operation lifetimes, and tests of those boundaries will.

| Dimension | Assessment | Most useful next improvement |
| --- | --- | --- |
| Stability and data integrity | Strong underlying transaction design; important application-level races remain | Preserve the durable current edit across asynchronous snapshot operations and restore package-owned Looks |
| Interactive performance | Good GPU/context reuse, progressive presentation, and admission policies; several hidden sources of main-actor work remain | Eliminate no-op full-index rebuilds, linear ID searches, and locks that make the UI wait for background work |
| Memory and storage | Several budgets exist, but they do not cover all retained or still-running work | Account for actual retained histories, keep cancelled work charged until completion, and bound analysis/mask storage |
| Maintainability | Useful value types and coordinator boundaries; too much lifecycle wiring and historical commentary remain | Make ownership and command effects explicit, remove redundant caching, and reduce dormant shipping surface |
| Verification | Good focused tests and meaningful pixel/identity checks; coverage does not yet exercise several cross-boundary sequences | Add small failure-driven sequence tests and qualify the signed candidate on the macOS 26 deployment floor |

This is a broad, risk-based review, not a claim to have proved every path correct. Source counts
are useful context, not quality scores: `KromoraKit` contains 291 Swift files and 97,099 lines
including comments; the test directory contains 323 Swift files and 98,377 lines. A textual count
finds 3,041 `func test` declarations, which is not a discovered-test or executed-test count.

## Evidence and limits

- Read the repository instructions, architecture/storage/testing guides, prior review, and code
  spanning package transactions, indexing, import, editing/history, analysis/masks, rendering,
  thumbnails, presentation, export, and lifecycle.
- Verified Apple/Swift primary references online on November 3, 2026. Recommendations below
  preserve **macOS 26+, Apple Silicon, Swift 6, and Apple frameworks only**. A new API being
  available in the build SDK does not make a macOS 27-only API appropriate for this product.
- Baseline Debug build passed with Apple Swift 6.4 and Xcode 27.0 on arm64 macOS 27.2. The first
  ordinary build attempt hit sandbox-denied compiler-cache paths. Redirecting caches into `/tmp`
  and disabling SwiftPM's nested sandbox allowed the build; this was an execution-environment
  restriction, not a product compile failure. The successful warm build is not a clean warning-gate run.
- **72 focused baseline tests passed**, with zero failures, across `ImageWorkSchedulerTests`,
  `EditDocumentRetentionCostTests`, `EditHistoryCoordinatorTests`, `PhotoAnalysisCoordinatorTests`,
  `EditDocumentStoreTests`, `LookSelectionCoordinatorTests`, and `RetouchWorkflowCoordinatorTests`.
- Added standalone probes linked against the freshly built production `KromoraKit.o`, using
  `@testable import`. They reproduced findings 01–06. Snapshot and Look probes exercise the real
  package/store implementations; cancellation probes inject deliberately non-cooperative operations.
  This distinguishes missing behavioral coverage from a general failure to build or pass tests.
- No full test lane, Release timing benchmark, real-window capture, Instruments trace, Photos
  authorization flow, licensed RAW evaluation, or signed-app qualification was run. Existing
  numbers in [TESTING.md](../../docs/TESTING.md) remain dated evidence for their recorded methods.
  No new frame-rate, peak-RSS, camera-quality, or macOS 26 runtime claim is made here.

Probe source, exact outputs, and reproduction commands are retained in the
[evidence directory](evidence/2026-11-03/README.md).

Priority means: **P1** fix before public release; **P2** material correctness, resource, or
performance work; **P3** smaller simplification or robustness improvement. “Code-confirmed”
establishes the implementation behavior, not its measured frequency or runtime cost.

## Findings

Tickets for findings 01–15 were created on 2026-11-03 as KRMA-1155 through KRMA-1169 (finding N maps to KRMA-(1154+N)). Findings 16 and S01–S14 have no tickets yet.

### 01. P1 — Saving a named snapshot can replace a newer durable edit without changing the live editor

**Ticket:** KRMA-1155

**Reproduced with the real history coordinator and package edit store.**

[`saveSnapshot`](../../Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift#L163) captures the
document, then awaits a persistence flush, then saves that captured value. The package's
[`commitEditRevision`](../../Sources/KromoraKit/Models/PortablePackageEditSidecar.swift#L476) makes
the new snapshot the current edit. There is no document-revision fence covering edits made during
the wait, and saving the snapshot does not adopt its document into the live editor.

The probe starts at exposure `0.1`, requests a snapshot, pauses its flush, saves a newer exposure
`0.9`, then lets the snapshot finish. Result:

```text
snapshot: liveExposure=0.9 durableExposure=0.1 loadReady=true
```

The latest edit remains an earlier revision in this fixture, so this is not a claim that all
recovery copies were destroyed. It is a current-state regression: the visible editor and durable
head disagree, while reads report success. Reopening can show the older image.

**Improve:** give named-snapshot creation an explicit package operation that preserves the current
edit when saving a captured earlier state. Alternatively, serialize and fence the command so it
cannot install an older captured value over a newer edit. Merely moving the document read to
after one `await` leaves other interleavings to consider. Preserve the intended captured snapshot
without implicitly navigating history.

**Verify:** gate both the flush and snapshot write; edit before and during each; navigate A → B → A;
then reopen the package. The named snapshot must contain its intended value, the current edit must
retain the newest accepted value, and UI/current-pointer state must agree. Include shutdown while
the command waits.

### 02. P1 — Embedded Looks are written but not used to reproduce package edits

**Ticket:** KRMA-1156

**Reproduced through production persistence and Look resolution; runtime call paths also traced.**

The package has a checked [`readEmbeddedLook`](../../Sources/KromoraKit/Models/PortablePackageEditSidecar.swift#L957)
boundary, but application resolution does not call it. [`LookSelectionCoordinator.resolve`](../../Sources/KromoraKit/ViewModels/LookSelectionCoordinator.swift#L57)
searches the external Look library and the in-memory derived registry. Store reads expose a
signature from the saved reference, not a table that the renderer can use.

The probe saves a valid external cube with embedded bytes, removes the external file, constructs
a fresh store and resolver, and loads the saved edit:

```text
looks: embeddedBytesMatch=true freshLoadReady=true runtimeResolverFoundLook=false
looks: embeddedReferencesAfterOrdinaryEdit=0
```

The second line follows an ordinary exposure edit saved by the fresh store. Its
[`sourceLookBytes`](../../Sources/KromoraKit/Models/EditDocumentStore.swift#L475) uses only the
currently supplied external-byte dictionary, so the next revision drops the embedded reference
despite keeping the document's LUT ID. Earlier revision blobs remain in the fixture; they simply
are not the current revision's reproducible dependency.

Consequences include an ungraded live preview or a failed per-asset export after moving a package
to a Mac without the external file. Export currently fails the unresolved item rather than
silently exporting without the Look, which is the safer behavior. A cached frame can conceal the
problem until an edit requires a new render. A replaced or retired external Look can also resolve
to different bytes when revisiting an old revision.

This conflicts with the package contract that moving/deleting an external cube must not invalidate
the saved edit. Preserving bytes is only half of that contract.

**Improve:** resolve saved revision dependencies through a shared, content-addressed package Look
loader, used by editor, thumbnails, history, and export. Carry existing verified references into
ordinary saves when the selected Look has not changed. Keep explicit user audition/rescan behavior
separate from reproducing a saved revision, and document how intentional external replacements
become new edits. Do not substitute the nearest starter Look while claiming exact reproduction.

**Verify:** copy the package into an isolated profile without its external LUT folder; reopen,
edit, restore snapshots, and export. Compare rendered pixels and referenced hashes with the
original session. Repeat with an external file replaced at the same path and with a retired
starter ID. New saves must retain all dependencies needed for their own edit.

### 03. P2 — Cancellation releases concurrency slots and shutdown ownership before work finishes

**Ticket:** KRMA-1157

**Reproduced with cancellation-oblivious injected work.**

[`ImageWorkScheduler.cancel`](../../Sources/KromoraKit/Models/ImageWorkScheduler.swift#L421)
retains cancelled package-I/O work until it finishes, but immediately removes running thumbnail,
editor, and frame-read jobs. Their underlying operation can still be inside ImageIO, a GPU wait,
or another non-cooperative call. Replacement work starts against the newly freed slot. A later
[`cancelAllAndWait`](../../Sources/KromoraKit/Models/ImageWorkScheduler.swift#L411) cannot await
tasks that were already removed.

With the thumbnail limit configured to one, the probe starts and cancels eight gated operations:

```text
scheduler: configured=1 peakActual=8 runningReported=0 actualAfterShutdownBarrier=8
```

This proves the accounting/barrier defect, not an eight-decoder measurement in the real grid.
The real thumbnail provider does perform synchronous ImageIO work after an asynchronous hop, so
the non-cooperative case is relevant to production. Fast scrolling and repeated supersession can
increase transient memory and CPU beyond the advertised limits.

**Improve:** retain physical work ownership until the operation exits. Separate the caller's
prompt cancellation notification from the resource slot and teardown handle. Keep obsolete jobs
in a draining set if logical IDs must be replaced immediately; count that set against physical
worker limits. Preserve exactly-once continuation notification.

**Verify:** cancel running jobs before calling a teardown barrier, repeatedly reuse the same job
ID, and inject a non-cooperative operation in every lane. Measure actual entered/exited operation
counts independently of scheduler dictionaries. The configured physical limit and the completed
shutdown barrier must both hold.

### 04. P2 — Retouch source-pick tasks can complete against another photo or after shutdown

**Ticket:** KRMA-1158

**Reproduced with a gated destination.**

The dust-analysis lanes own their tasks, but source picks launched from
[`endGesture`](../../Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift#L179) and
[`nextSource`](../../Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift#L417) do not.
[`shutdown`](../../Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift#L385) drains only
the analysis lanes. The gesture task calls `destination.endUndoGrouping()` after its awaited pick,
without a source/session token. The root's picker checks source and spot geometry, but does not
fence the entire operation by shutdown and invocation generation.

The probe begins a spot on A, gates its pick, switches the destination to B, shuts down the
coordinator, and releases the pick:

```text
retouch: undoGroupEndsAtShutdown=0 undoGroupEndsAfterShutdown=["B"]
```

The demonstrated effect is a late undo-group callback into B after shutdown; it is not a reproduced
cross-photo pixel write. The root also permits ordinary document mutation/persistence without a
central shutdown guard, so these late callbacks should not be treated as harmless bookkeeping.
Several concurrent “next source” requests also lack a newest-invocation-wins fence.

**Improve:** own and drain all source-pick tasks, bind them to asset/source/session and operation
generation, and make group completion apply only to the group that operation opened. Reject
new document commands after shutdown admission closes. Avoid keeping the destination alive through
an untracked task.

**Verify:** delayed pick → navigation → new gesture; rapid next-source requests completing out of
order; deletion; and shutdown. No old operation may close the new photo's group, publish a source,
or enqueue a save after the barrier.

### 05. P2 — Session byte accounting can badly underestimate retained undo history

**Ticket:** KRMA-1159

**Reproduced using the production per-document cost estimator.**

[`Entry.cost`](../../Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift#L30) multiplies
the **current document's** estimated cost by the number of current/undo/redo documents. Older
documents can be much larger. Removing a heavy mask makes the current document small while the
large previous document is still retained for Undo.

The probe commits a brush-heavy document, removes the mask, makes the session inactive, and
requests eviction under a one-megabyte byte budget:

```text
retention: byteBudget=1000000 reported=8192 sumOfRetainedDocumentEstimates=3208581 retainedSessions=1
```

The 3.2 MB figure sums the same production estimator across the documents actually retained; it is
not RSS. The 100,000-sample fixture is a generated model payload, not a timed pointer gesture.
Copy-on-write can reduce actual allocations, but cannot justify charging a large retained value
as though it had disappeared.

**Improve:** account for each history entry and any open group using cached per-entry costs,
updated when entries move between undo/redo stacks. Keep active/dirty/pinned exceptions explicit;
those intentional exceptions do not explain this inactive clean-session miss. Use saturating
arithmetic for aggregate estimates.

**Verify:** large → small → Undo → Redo, histories mixing different payload sizes, and group
cancellation. Assert eligibility/eviction against the sum of retained value estimates, then measure
a long-session Release RSS plateau separately.

### 06. P2 — The persistent analysis cache ignores the requested analysis level

**Ticket:** KRMA-1160

**Reproduced by seeding a valid global-only result, then requesting detailed analysis.**

[`analyze`](../../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift#L108)
includes `level` in the in-flight key, but constructs its disk-cache key from source identity and
analysis version alone. Any matching cached analysis returns immediately. The
[`stage registry`](../../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift#L471)
actually differs between fast, standard, and detailed requests; detailed asks for additional kinds
and preview-quality masks.

```text
analysis: detailedRequestReturnedGlobalOnly=true requestedMaskStages=0
```

A standard Auto analysis can therefore satisfy a later detailed masking request without running
its additional stages. A result persisted after optional stage failures can also prevent later
requests from retrying those stages. The probe establishes skipped work, not a particular bad
photographic decision.

**Improve:** persist explicit stage/quality coverage and reuse a result only when it satisfies the
requested contract; compute and merge missing stages. A level in the cache key is a simpler initial
fix, but the current levels are not strictly nested, and partial-failure retry needs its own rule.
Use bounded retry/backoff rather than retrying unsupported masks on every request.

**Verify:** fast → detailed, standard → detailed, detailed → standard, relaunch, concurrent levels,
and one transient stage failure followed by success. Inspect requested provider stages, not just
whether a result object returned.

### 07. P2 — Ordinary edit acknowledgements rebuild the entire library index even when nothing changed

**Ticket:** KRMA-1161

**Code-confirmed; end-user latency not measured in this audit.**

[`stagePresentedAspectRatio`](../../Sources/KromoraKit/Models/PortablePackageEditSidecar.swift#L552)
returns the membership entry even when its presented ratio did not change. The store forwards it
to [`applyCommittedMembership`](../../Sources/KromoraKit/Models/PortableLibrarySession.swift#L1898),
which unconditionally calls [`applyIndexDelta`](../../Sources/KromoraKit/Models/PortableLibrarySession.swift#L939).

For every such save, `LibraryIndexProjection.applying` builds a dictionary from all entries,
validates paths/duplicates, sorts the complete array, constructs a new query controller and ID
set, advances the generation, discards the ordered-query cache, and schedules a full JSON index
write. This path runs its in-memory work on the main actor. A tone-only edit thus has a library-size
cost even though its browsing summary is unchanged.

**Improve:** compare the incoming membership value with the current indexed value and return on
equality before rebuilding or advancing generations. Forward a delta only for actual summary
changes. Coalesce real deltas, and move expensive snapshot construction off the main actor with a
generation fence. Preserve the transaction's atomic geometry guarantee.

**Verify:** repeated tone edits must cause zero index-generation/order-cache/projection-write
changes when summaries are equal; crop and culling changes must still publish correctly. Profile
the same sequence at 10,000 and 100,000 assets in Release. This is a higher-value first step than
introducing a new database or cache layer.

### 08. P2 — Index-side ID lookup remains linear and becomes quadratic in batch work

**Ticket:** KRMA-1162

**Code-confirmed algorithmic cost.**

[`LibraryIndexProjection.entry(for:)`](../../Sources/KromoraKit/Models/LibraryQueryController.swift#L224)
uses `entries.first`. [`browsingAssets(forIDs:)`](../../Sources/KromoraKit/Models/PortableLibrarySession.swift#L1510)
repeats that full scan for each requested ID. Launch hints, selection validation, source resolution,
and idle-warm candidate hydration reuse these paths. Walking many IDs over the library therefore
does O(N²) lookup work even when page ordering is cached.

**Improve:** keep one immutable ID → index map per projection/controller generation, shared by
lookups and selection validation. Keep the ordered array for stable paging. Use that map when
locating a page containing a known asset rather than constructing and scanning successive pages.
Avoid rebuilding a full map at every viewport callback.

**Verify:** a batch of K known IDs should do O(K) lookups after one O(N) generation build. Cover
deletion, source replacement, copies, query changes, and duplicate-ID rejection. Benchmark active
open and a complete warm-planning pass at realistic library sizes.

### 09. P2 — Query sorting can occupy the main actor or block it behind a background planner

**Ticket:** KRMA-1163

**Code-confirmed execution/locking path; profile needed to quantify hitches.**

[`orderedEntries`](../../Sources/KromoraKit/Models/LibraryQueryController.swift#L712) filters and
sorts the entire projection on a cache miss. The synchronous browsing/query setters invoke that
work from `PortableLibrarySession` on the main actor. The cache is usefully bounded to one query;
it is not an unbounded query-result cache.

Its [`entries(for:build:)`](../../Sources/KromoraKit/Models/LibraryQueryController.swift#L618)
holds an unfair lock for the whole build. Copies share that cache, including the controller passed
to the background idle-warm planner. A foreground query can therefore wait on background sorting
even when its own CPU work was supposedly moved off-main.

**Improve:** prepare query order from an immutable projection off-main, then install a result
tagged with query and index generation. Keep mutex critical sections short; do not sort while
holding a lock that UI callers acquire. Keep selection publication coherent while preparation is
in flight. A bounded completed-result cache is useful; blocking the main actor to construct it is
the part to remove.

**Verify:** reverse-completing query requests, an idle planner overlapping a sort change, and index
updates during preparation. Use the SwiftUI instrument and main-thread traces on Release builds;
Apple recommends measuring both expensive updates and their causes before changing view structure.
([Apple's SwiftUI performance session](https://developer.apple.com/videos/play/wwdc2025/306/))

### 10. P2 — The off-caller digest helper can still synchronously wait for hashing on the UI actor

**Ticket:** KRMA-1164

**Code-confirmed lock dependency; no wall-clock measurement claimed.**

[`DurableEditIdentityMemo.Entry.resolve`](../../Sources/KromoraKit/Models/DurableEditIdentity.swift#L25)
computes JSON and SHA-256 while holding the entry mutex. `cachedDigest` reads that same entry through
the blocking `cached` accessor. [`digestOffCaller`](../../Sources/KromoraKit/Models/DurableEditIdentity.swift#L84)
calls `cachedDigest` before hopping to its `@concurrent` worker.

If another consumer is computing that document's digest, a main-actor “cache check” waits for the
hash to finish. Moving the miss computation off-main has not removed that wait. Equality checks
over large distinct document values also happen under the memo's shared-state lock.

**Improve:** distinguish a completed cached digest from an in-flight asynchronous computation.
Let consumers await shared work without blocking an executor thread; expose a nonblocking
completed-value lookup. Keep lookup bookkeeping short, and retain the existing deterministic
durable hash format.

**Verify:** gate a digest computation, ask for the same document from the main actor, and prove a
main-actor heartbeat continues while it waits. Include different large recipes and cancellation of
one of several consumers. Apple specifically identifies synchronous waits as a responsiveness
risk. ([Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness))

### 11. P2 — History refreshes need an invocation fence and a coherent read snapshot

**Ticket:** KRMA-1165

**Code-confirmed missing fences; not reproduced against a running UI.**

[`refresh`](../../Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift#L118) reads history and
current revision in two separate awaited calls. Publication checks only whether the source reference
still matches and shutdown has not begun. Two refreshes of the same photo can publish out of order;
A → B → A also makes an old A operation pass that check. A restore/save between the two reads can
produce a history/current-pointer pair from different logical moments.

**Improve:** add a refresh generation invalidated on source changes and new refreshes. Return
history plus its selected revision from one store snapshot, so the coordinator publishes one
coherent value. Serialize or revision-fence conflicting restore/snapshot commands rather than
letting completion order define intent. Preserve accepted-write draining during shutdown.

**Verify:** older successful and failed reads finishing after newer ones, A → B → A, and refresh
overlapping restore/save. Assert the exact history/current-pointer pair and newest command intent.

### 12. P2 — Facet counts can become stale after import/backfill and after cancelled query tasks

**Ticket:** KRMA-1166

**Code-confirmed view dependency and publication path.**

[`LibraryFacetSidebar`](../../Sources/KromoraKit/Views/LibraryFacetSidebar.swift#L75) refreshes
counts with `.task(id: query)`. Imports and metadata backfills change the index while leaving the
query equal, so they do not restart this task. Also, the task unconditionally assigns its result
after awaiting the off-main computation. Cancellation of an older query task does not by itself
stop that computation from returning and publishing old counts.

**Improve:** key the work to query plus a published index generation, and check cancellation and
the captured identity before assigning. Coalesce rapid index changes. Publish one coherent count
snapshot rather than recomputing counts in view getters.

**Verify:** import while the sidebar remains open, metadata backfill completing without a filter
change, and old/new count requests completing in reverse order. Bounds and unavailable metadata
messages must update along with categorical counts.

### 13. P2 — Analysis and mask disk caches have no application budget, and deletion repeatedly scans them

**Ticket:** KRMA-1167

**Code-confirmed resource policy and cleanup algorithm.**

`PhotoAnalysisCache` and `MaskStore` create per-key files with no byte/age/entry retention policy.
The OS caches directory is an appropriate location, but eventual OS cleanup is not a predictable
application resource budget. Source, provider, and analysis-version changes leave prior variants.
A 60-million-pixel Float32 mask alone is approximately 240 MB before read/copy/transient costs.

Both [`PhotoAnalysisCache.remove`](../../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift#L163)
and [`MaskStore.remove`](../../Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift#L117) enumerate
the entire cache and decode JSON to identify one asset's records. Multi-photo deletion repeats
that process per asset. Legacy mask metadata can still contain an inline float array, making a
nominal metadata scan much more expensive.

**Improve:** organize disposable entries by asset or maintain a rebuildable ownership index; delete
a batch with one bounded traversal. Add byte/age caps and background stale-version/orphan cleanup
that yields to visible work. Evaluate tiled or more compact mask persistence only with a quality
comparison; do not quantize blindly. Bound large binary reads before allocating and avoid redundant
full-payload copies where profiling confirms a peak-memory benefit.

**Verify:** repeated export-quality masking across many photos/versions, interrupted two-file
writes, corrupt legacy entries, and deletion of a large selection. Record disk plateau, actual
operation counts, cleanup latency, and peak RSS. Never evict saved recipes or canonical originals.

### 14. P2 — Photos delivery reopens a completed file as Data instead of importing the file resource

**Ticket:** KRMA-1168

**Code-confirmed; PhotoKit execution and peak memory not measured.**

[`ExportCoordinator`](../../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L756) streams
encoding into a file, then reads that file into `Data` on its main-actor path for Photos delivery.
[`PhotoKitDelivery`](../../Sources/KromoraKit/Models/PhotosDelivery.swift#L90) passes the data to
PhotoKit. `.mappedIfSafe` can help with initial residency, but does not guarantee zero copies or
cheap downstream access, and the synchronous open/read still belongs to the UI call path.

**Improve:** extend the delivery boundary to accept the already committed file URL and use
`PHAssetCreationRequest.addResource(with:fileURL:options:)`. Retain the URL/security grant until
the change transaction settles; retain the user's exported file (`shouldMoveFile` must not remove
it). Keep the data overload only where a caller actually owns in-memory bytes.
([Apple's asset-creation API](https://developer.apple.com/documentation/photos/phassetcreationrequest),
[file ownership option](https://developer.apple.com/documentation/photos/phassetresourcecreationoptions/shouldmovefile))

**Verify:** large TIFF/PNG delivery, denied/limited authorization, optional album failure,
cancellation, and source/destination scope lifetime. Confirm that a Photos failure leaves the
completed disk export intact and accurately counted.

### 15. P2 — Missing required image kernels can silently omit saved edits

**Ticket:** KRMA-1169

**Code-confirmed failure behavior; no damaged shipping bundle was exercised.**

[`CIKernelLibrary`](../../Sources/KromoraKit/Support/CIKernelLibrary.swift) returns optional
kernels. Several rendering helpers fall back to the input/current image when a required operation
cannot be built; for example, mask inversion/combination in
[`LocalMaskRenderer`](../../Sources/KromoraKit/Models/LocalMaskRenderer.swift#L133). The parity and
resource-freshness tests are valuable safeguards, but do not make every runtime kernel or command
failure impossible.

An unavailable decorative overlay can reasonably degrade. An unavailable kernel needed to
reproduce a saved local adjustment cannot become a successful export with that adjustment omitted.

**Improve:** validate required rendering capabilities once, preserve the underlying load error,
and propagate an actionable render/export failure for a requested edit that cannot execute.
Distinguish optional presentation effects from pixel-producing document operations. Avoid
crashing the app to report a recoverable rendering failure.

**Verify:** inject a missing/unloadable required kernel and a failed GPU completion. The affected
render must fail visibly, preserve the document, and avoid committing an incorrectly rendered
export. Keep existing neutral/no-op and unsupported-capability behavior intact.

### 16. P2 — Release performance and photographic-quality claims need executed candidate evidence

**Verification gap, not a new measured renderer regression.**

The required CI lanes provide useful deterministic evidence. The workflow's UI smoke can explicitly
defer when WindowServer is unavailable, and the build/test runner uses a newer OS than the macOS 26
deployment floor. A green status is therefore not evidence that the shipping sandbox/Photos/UI
path ran on the minimum supported system. The current documentation acknowledges this distinction.

The [retouch guide](../../docs/RETOUCH.md) likewise distinguishes tiny synthetic shipping floors,
camera-scale generated diagnostics, and human acceptance. Some of its measurements are historical;
they must not be presented as a fresh failure rate or as proof of current real-photo quality.
Auto's generated corpus and candidate guards are useful, but cannot independently establish
pleasing results on diverse photographs.

**Improve:** make one concise release record for the exact signed candidate: macOS 26 and the
current OS; warm/cold large-library navigation; rapid edit/export overlap; long mask/retouch
sessions; sleep/wake; full disk/read-only/removable storage; Photos authorization; save, quit,
relaunch, and package copy. Record executed, failed, and deferred checks separately. Use a small
licensed local photo set with visually reviewed 100% crops and fixed acceptance criteria. Any
retouch failure that motivated a fix needs a new visual verdict, not just a closed code task.

Run display-bound capture only during supervised release qualification, following the repository's
existing limit. Tie each slow frame to CPU, GPU, I/O, or SwiftUI evidence before optimizing. Apple's
performance tooling emphasizes this causal approach.
([SwiftUI Instruments workflow](https://developer.apple.com/videos/play/wwdc2025/306/))

## Simplification and smaller improvements

These are actionable opportunities, not reasons to defer the reproduced defects. The benefit and
verification should stay proportional to the change.

| ID / priority | Evidence and opportunity | Improvement and completion criterion |
| --- | --- | --- |
| S01 / P3 | [`EditDocumentStore.load`](../../Sources/KromoraKit/Models/EditDocumentStore.swift#L316) reads and decodes the native/XMP pair before deciding whether its decoded-document cache hit is valid. The 128-entry cache still retains variable-size documents. | Consider removing the redundant decoded-value cache: retain required package validation and return the document already decoded. Alternatively, demonstrate which expensive work a safe hit actually avoids and give that cache a byte budget. Compare read work and memory; do not bypass corruption detection merely to improve a hit counter. |
| S02 / P2 | `AppViewModel.swift` is 5,114 lines; `MaskingWorkspace.swift` is 2,364; `PortableLibrarySession.swift` is 2,214. Existing extractions helped, but root-owned mutation, callbacks, shutdown, and several protocol façades still require broad knowledge for a local change. | Use findings 01–04 to clarify one command/lifetime boundary at a time. Prefer a narrow typed session/operation context and explicit result over more callback forwards. Keep the active document single-owned. Separate source files by a real responsibility, not to satisfy a line-count ceiling. Verify with behavior tests and a shorter ownership explanation. |
| S03 / P3 | [`PortableLibraryBackup`](../../Sources/KromoraKit/Models/PortableLibraryBackup.swift) and [`PortableLibraryRestore`](../../Sources/KromoraKit/Models/PortableLibraryRestore.swift) remain compiled, tested model surface for a feature explicitly described as unwired. | Inventory their production callers and shared helpers. Move standalone support work into a separate internal tool target or remove deferred feature-only code if the feature remains out of scope. Preserve any storage validation/transaction code genuinely used by shipping workflows. Completion is a smaller shipped dependency graph, not simply fewer files. |
| S04 / P2, measure first | [`Thumbnails.swift`](../../Sources/KromoraKit/Models/Thumbnails.swift#L154) always asks ImageIO to create a thumbnail from image data, while its header claims an embedded-preview path. Existing cold-import measurements document substantial RAW decode memory. | First correct the misleading comment. Evaluate an explicit embedded-preview-first tier with sufficient size, orientation, and quality checks, followed by the current decode only when needed. Treat different pixels as a cache/signature policy change. Compare cold-window latency, peak RSS, and appearance on representative RAWs; do not infer an ImageIO implementation guarantee from the flag alone. ([ImageIO option](https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailfromimagealways)) |
| S05 / P3 | [`LibraryGridView`](../../Sources/KromoraKit/Views/LibraryGridView.swift#L70) rebuilds models for all loaded rows as coarse scroll state changes; row bodies also read the shared selection and copy each row slice. | Profile update causes first. Cache stable row descriptors by entries/layout generation and narrow selection dependencies if a measured cost warrants it. Preserve stable IDs and the full declared `LazyVStack` structure: reintroducing scroll-driven child replacement would undo the documented constraint-pass crash fix. |
| S06 / P3 | [`ImageCollection.applyThumbnail`](../../Sources/KromoraKit/Models/ImageCollection.swift#L1477) re-signals edited demand for every visible ID on every original-thumbnail arrival. | Coalesce one pending refill per turn or refill only newly admissible demand. Prove the same final pixels and no starvation when the viewport exceeds queue capacity; count callback/render admissions before timing. |
| S07 / P3 | [`LatestPreviewFrameStore.touch`](../../Sources/KromoraKit/Models/LatestPreviewFrameStore.swift#L394) changes filesystem mtime on every cache hit; warm-write accounting repeatedly encodes complete envelopes just to count their bytes. | Keep recency updates in memory and persist them coalesced when justified. Cache a pending frame's encoded size or encoded envelope once. Compare filesystem operations and allocation counts; do not change exact-frame identity or crash-safe replacement semantics. |
| S08 / P3 | Cache write failures are swallowed in [`LatestPreviewFrameStore.write`](../../Sources/KromoraKit/Models/LatestPreviewFrameStore.swift#L347). Repeated failures can look like mysterious cold rendering to diagnostics. | Keep failures nonfatal, but record bounded, rate-limited failure counters/reasons and retry outcomes. Avoid an alert for every disposable-cache miss. Make a full/read-only cache diagnosable without exposing source paths in routine logs. |
| S09 / P3 | [`Package.swift`](../../Package.swift#L83) indexes the first result of a split that omits empty fields. A bare `#` comment produces an empty result and can trap the manifest parser; a comment containing three numbers can be mistaken for data. Existing starter resources do not contain bare-`#` lines. | Preserve empty prefixes when removing comments, avoid forced indexing/conversion, and add a tiny validator check for comment-only and trailing-comment lines. Keep the existing fail-closed resource gate. The runtime parser already handles comments more carefully; avoid expanding two divergent parsers. |
| S10 / P3 | [`LocalMaskRenderer.image`](../../Sources/KromoraKit/Models/LocalMaskRenderer.swift#L68) converts extents to `Int` before checking that they are finite and positive. | Validate finiteness, positivity, representability, and relevant allocation products before integer conversion. This is local robustness at an internal seam, not a reproduced user-triggered crash. Verify malformed/extreme geometry returns failure without trapping. |
| S11 / P3 | Static canonical-preview helpers in [`RenderEngineResources`](../../Sources/KromoraKit/Models/RenderEngineResources.swift#L106) create contexts with the nonlinear delivery color space. The production retained context correctly uses extended linear P3. | Align helpers with the engine's linear working-space factory or make their limited test-only use explicit. Exercise a nontrivial filter graph in helper/production parity tests. Do not remove intentional sRGB analysis/reference contexts, which have a separate documented contract. |
| S12 / P3 | Historical “Step N,” ticket narratives, old type names, and retired spec references remain in foundational source comments, including `Thumbnails`, `ExportCoordinator`, and `PhotoAnalysis`. | Keep the invariant and its reason beside the code; move implementation history to the existing dated review/decision records. Update comments that promise behavior the code does not implement. Readability and accurate ownership matter more than adding commentary volume. |
| S13 / P3 | [`LibraryBrowsingCoordinator`](../../Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift#L373) silently ignores several reload failures; canonical and disposable failures need different treatment. | Keep ordinary optional-cache misses quiet, but retain the last usable window and report a failed user-requested query/reload through a bounded status/error path. Inject a reload failure and verify selection/query/UI coherence. Avoid a broad replacement of every `try?`. |
| S14 / P3 | [`RetouchCanvasOverlay`](../../Sources/KromoraKit/Views/RetouchCanvasOverlay.swift#L16) draws pins/handles in a Canvas and gives the surface a label; the drawing does not by itself expose each editable spot as an accessible control. | Audit VoiceOver and Full Keyboard Access for selecting, moving, deleting, and choosing a source for a spot. Provide an accessible spot list/custom actions where the canvas cannot express those operations. Preserve native slider and responder-chain behavior already implemented. This is an interaction-completeness review, not a claim that all existing controls are inaccessible. ([Apple custom-control guidance](https://developer.apple.com/documentation/AppKit/accessibility-for-appkit)) |

## Swift and Apple guidance applied

The relevant best practices are about execution and ownership, not replacing working code with the
newest syntax:

- **Keep UI work small and avoid synchronous waits.** Findings 07–10 are concrete reasons to
  inspect main-actor time. Moving code into `Task {}` does not itself move it off an actor.
  ([Apple responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness))
- **Treat cancellation as cooperative.** Keep a task/resource owned until its real operation
  finishes; a generation fence protects publication, while a barrier protects lifetime. Both are
  needed. Swift's concurrency model provides cancellation checks and handlers rather than forcibly
  stopping arbitrary framework calls.
  ([The Swift Programming Language: Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/))
- **Be deliberate about executor semantics.** This package uses Swift 6 mode with a 6.2 tools
  manifest and explicit `@concurrent` workers. Swift 6 mode alone does not imply that
  `NonisolatedNonsendingByDefault` is enabled. Audit actual settings and worker call paths before
  changing concurrency defaults; avoid a blanket MainActor-default migration.
  ([Swift's feature documentation](https://docs.swift.org/latest/documentation/diagnostics/nonisolated-nonsending-by-default/),
  [Swift 6.2 release notes](https://www.swift.org/blog/swift-6.2-released/))
- **Profile SwiftUI dependencies and preserve view identity.** Use the SwiftUI instrument's
  expensive-update and cause/effect views before changing grid layout or observation. Smaller
  dependency scope is useful when it eliminates real work; arbitrary view extraction is not a
  performance result.
  ([Apple's Instruments session](https://developer.apple.com/videos/play/wwdc2025/306/))
- **Retain Core Image contexts and control image size/data movement.** The current engine already
  does much of this correctly. Prioritize unnecessary CPU copies, decodes, and duplicate work;
  do not add texture pooling or rewrite kernels without an attributable measured bottleneck.
  Apple's older Core Image guide remains a reference for context reuse, not the authority for
  modern Swift isolation or new deployment availability.
  ([Core Image performance guidance](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html))

## Recommended order of work

1. **Protect saved appearance:** fix 01 and 02 with package-level reproductions, including
   relaunch and isolated-profile export. They are release blockers regardless of frame rate.
2. **Make lifetime/resource promises true:** fix 03–06. Preserve one owner per operation and
   account for physical work and retained values, including after cancellation.
3. **Remove avoidable library work:** start with 07 and 08; they have clear operation-count
   outcomes and relatively small designs. Then address 09 and 10 with a Release main-thread trace.
4. **Tighten coherence and diagnostics:** 11–15, starting with small sequence tests for history and
   facet publication, and a bounded cache policy. Apply S01/S06/S07 alongside their owning changes
   when they reduce work without adding another state authority.
5. **Qualify the product:** execute 16 on the signed candidate and the macOS 26 baseline. Record
   actual p50/p95/p99 interaction latency, peak memory, cache/disk growth, and visual acceptance
   using the repository's established methods; do not label deferred checks as passes.

The highest-value simplification is to eliminate duplicated authority and unnecessary work while
keeping the useful constraints already in place: one canonical package, one document owner, a
shared render order, explicit async publication fences, and native platform controls.
