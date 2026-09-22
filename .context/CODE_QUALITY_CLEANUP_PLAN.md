# Code quality cleanup plan — prioritized ticket list

Reviewed 2026-09-21 against committed **`d6e4977`** (`main`). Read-only analysis; no tracked source was
changed. Each `CQ-xx` item below is sized and scoped so it can become one DispatchGraph issue (or a
short, explicitly staged series) executed by an independent agent.

This list **supersedes the open parts of** [`docs/REPOSITORY_IMPROVEMENT_PLAN.md`](../docs/REPOSITORY_IMPROVEMENT_PLAN.md)
(2026-09-12). That plan predates the portable-package cutover. Several of its items are still open
(R1, R2, R4, R6) and are folded in below. R1/R3's `durableDataURL` findings now apply only to the
legacy folder mode, which production no longer uses (see CQ-05).

## How this was produced

- Built `d6e4977` in a throwaway worktree (`scripts/agent-worktree.sh`) with `swift build --build-tests`
  on Xcode 27.0 / Swift 6.4. Result: builds, **35 unique warnings** (listed in CQ-17).
- Static sweeps for unreferenced types, functions, typealiases, and properties. Each sweep counted
  whole-word references across `Sources/` and `Tests/`, and every item in this document was then
  checked by hand. Protocol conformances, AppKit overrides, and SwiftUI entry points were
  excluded as false positives.
- Two throwaway probe tests (run in the worktree and deleted, never on the main tree) confirmed
  CQ-01 empirically.
- **Working-tree note:** the main checkout currently has uncommitted edits to `ContentView.swift`,
  `InfoInspectorView.swift`, and `PreviewView.swift` that **do not compile**
  (`ContentView.swift:397`, `.animation` contextual type). That looks like in-progress KRMA-511–515
  work, not a cleanup item. Agents should start from a clean `main` or coordinate with it,
  because CQ-06 and CQ-14 touch the same views.

## Priority legend

| Priority | Meaning |
| --- | --- |
| **P0** | Confirmed correctness or data-integrity defect in the shipping configuration. Do first. |
| **P1** | Significant performance, stability, or maintenance exposure. Can also be safe, high-leverage dead-code removal. |
| **P2** | Architecture, hygiene, hardening, or documentation work that makes later changes cheaper and safer. |

Size: **S** = one focused PR · **M** = several coordinated files · **L** = staged, multiple PRs.

## Summary

| ID | Title | Pri | Category | Size | Depends on |
| --- | --- | --- | --- | --- | --- |
| CQ-01 | Renew the package writer lease: all writes fail ~3 min after launch | P0 | correctness | S | — |
| CQ-02 | Make import outcome accounting truthful across every import entry point | P0 | correctness | M | CQ-01 |
| CQ-03 | Move package import, hashing, and index refresh off the main actor | P0 | stability/perf | M | CQ-02 |
| CQ-04 | Drive the library UI from paged queries, not full-library materialization | P1 | performance/scale | L | CQ-03 |
| CQ-05 | Remove the legacy folder-backed library mode | P1 | deprecation | L | CQ-02 (and CQ-04 for ImageCollection) |
| CQ-06 | Replace root `objectWillChange` fan-in with Observation | P1 | performance | L | best after CQ-05 |
| CQ-07 | Move preview disk-cache rasterization into the render actor and bound its I/O | P1 | perf/boundary | M | — |
| CQ-08 | Bound brush-mask rasterization (carry-over R4) | P1 | performance | M | — |
| CQ-09 | Migrate deprecated CIKL kernels to Metal and precompile shaders | P1 | stability | M | — |
| CQ-10 | Delete the mask-overlay prototype | P1 | dead code | S | — |
| CQ-11 | Delete unreferenced functions, typealiases, views, and compatibility shims | P1 | dead code | S | — |
| CQ-12 | Separate diagnostics/evaluation code from the shipping Auto path | P2 | dead code/arch | M | — |
| CQ-13 | Extract the Auto workflow and retire the histogram fallback | P2 | architecture | M | CQ-12 |
| CQ-14 | Continue AppViewModel decomposition (import, masking, thumbnails, crop/undo) | P2 | architecture | L | CQ-05 |
| CQ-15 | Split RenderEngine by responsibility and bound its bookkeeping | P2 | arch/stability | M | CQ-07, CQ-08 |
| CQ-16 | Simplify EditDocumentStore to a package-backed cache | P2 | simplification | M | CQ-05 |
| CQ-17 | Reach a zero-warning build and enforce it; reduce test-only production surface | P2 | hygiene | M | CQ-09 |
| CQ-18 | Harden the direct-distribution updater and verify it under App Sandbox | P2 | security | S | — |
| CQ-19 | Centralize package path safety (symlinks, `.`) and shared helpers | P2 | security/dup | S | — |
| CQ-20 | Reconcile documentation with the package-backed product | P2 | docs | S | lands with or after CQ-05 |

## DispatchGraph tickets

Each CQ item is tracked as a backlog ticket with the same scope, priority, size, dependencies,
acceptance criteria, and implementation guidance:

| Plan item | Ticket |
| --- | --- |
| CQ-01 | KRMA-516 |
| CQ-02 | KRMA-517 |
| CQ-03 | KRMA-518 |
| CQ-04 | KRMA-519 |
| CQ-05 | KRMA-520 |
| CQ-06 | KRMA-521 |
| CQ-07 | KRMA-522 |
| CQ-08 | KRMA-523 |
| CQ-09 | KRMA-524 |
| CQ-10 | KRMA-525 |
| CQ-11 | KRMA-526 |
| CQ-12 | KRMA-527 |
| CQ-13 | KRMA-528 |
| CQ-14 | KRMA-529 |
| CQ-15 | KRMA-530 |
| CQ-16 | KRMA-531 |
| CQ-17 | KRMA-532 |
| CQ-18 | KRMA-533 |
| CQ-19 | KRMA-534 |
| CQ-20 | KRMA-535 |

---

## P0 — confirmed defects

### CQ-01 — Renew the package writer lease: all writes fail ~3 minutes after launch

**Evidence (confirmed by probe).** `PortableLibrarySession` acquires a `PortablePackageLease` with
`defaultDuration = 180` s (`PortablePackageTransaction.swift:133`). Only `PortableLibraryRestore`
ever calls `lease.renew()` (`PortableLibraryRestore.swift:172, 214`). There is no heartbeat for the
editing session. Every write goes through `PortablePackageTransaction.begin` → `lease.assertOwnership(at: Date())`,
which throws `.expired` once `expiresAt <= now`. That covers edit revisions, imports, culling state,
and removal from the library.

Two probes against `d6e4977`:

1. Open a session whose lease was acquired 240 s ago, then call `importURLs`. The call "succeeds"
   with `imported=0` and a per-item failure: *"The previous session … did not close cleanly, so the
   package writer lease has expired."*
2. Call `appendEditRevision(…, now: +240 s)` on a freshly opened session. It throws the same error.

Impact: after about three minutes in the app, edit persistence and imports fail. The error text
blames a previous session, which misdirects the user and whoever triages it. For imports, the
failure is swallowed into per-item results (see CQ-02).

**Implementation.**
- Give `PortableLibrarySession` (or `ApplicationShellCoordinator`, which already receives
  `packageLease`) a heartbeat that renews at about duration/3. Run it on the package-I/O lane,
  cancel and await it in `shutdown()`, and don't let renewal block the main actor.
- Also renew opportunistically before long transactions, such as large imports and backups.
- Add a distinct `PortablePackageLeaseError.lostDuringSession` path and user message, kept
  separate from the stale-previous-session takeover message.
- Decide the policy for losing the lease mid-session: another writer took over, the lock file
  was deleted, or the Mac slept past expiry. Recommended: stop writes, keep the dirty snapshots,
  and surface an actionable banner. Never break a lease you don't own.
- Consider sleep/wake: after wake, renew immediately if the lease has not been taken by another
  owner.

**Acceptance.** An injected clock or short test duration shows edits and imports still commit
after more than 2× the lease duration. Shutdown stops the heartbeat with no write after release.
A contended or stolen lease produces the new error rather than silent data loss. Add a regression
test in the fast lane using an injectable duration and clock. Don't use `sleep`.

**Files.** `PortablePackageTransaction.swift` (lease), `PortableLibrarySession.swift`,
`ApplicationShellCoordinator.swift`, `AppViewModel.swift` (shutdown ordering), tests.

---

### CQ-02 — Make import outcome accounting truthful across every import entry point

**Evidence.**
- `PhotosImportCoordinator.append` (`PhotosImportCoordinator.swift:231`) always does
  `imported += 1` after `destination?.insertPhotosImport(...)`, which returns `Void`. The destination
  cannot report failure (carry-over R1).
- In package mode, `AppViewModel.insertPhotosImport` catches import errors and calls
  `recordPhotosImportFailureDestination`. That records the failure into the **legacy collection**
  (`collection.recordDataImportFailure`), not into the coordinator's progress
  (`AppViewModel.swift:~2497–2520`). The user sees "N imported" even when package writes failed,
  which happens every time after CQ-01's expiry.
- `PortablePackageImportResult.failures` and `duplicates` are dropped by the folder
  (`openSourceFolder`), drop, promise-drop, and removable-media paths. `importRemovableMedia` hard-codes
  `skipped: 0` (`AppViewModel.swift:~2676`).
- The nil-data and generic-error branches of the Photos loop call `recordFailure` without an
  operation-identity or cancellation check (carry-over R2). A superseded import can mutate a newer
  import's counts.

**Implementation.**
- Change `PhotosImportDestination.insertPhotosImport` to return an outcome enum:
  `.inserted(assetID)`, `.duplicate(existing)`, `.failed(reason)`. The coordinator counts only
  what the destination reports.
- Add one `ImportOutcomeSummary` value built from `PortablePackageImportResult`, and use it for
  every entry point: Photos, folder, file drop, promise drop, removable media, and `openImage(data:)`.
  Status text and `LibraryMediaWorkflowCoordinator.finishImport` receive the real imported,
  duplicate, and failed counts plus failure reasons.
- Fence every post-`await` mutation in the Photos loop (success, nil, error, finish) with
  `isCurrent(operationID)`.
- Remove the deprecated `PhotosImportCoordinator.init(viewModel:)` and
  `setProgressForCompatibility`. Their only callers are 5 tests (see the build warnings).

**Acceptance.** Injected package write failures, duplicates, and nil transfers produce the
correct counts and messages for each entry point. Late results from import A, whether success,
nil, error, or cancellation, don't change import B. Tests use a fake provider and a package
fixture with a fault injector (`PortablePackageFaultInjector` already exists).

**Files.** `PhotosImportCoordinator.swift`, `AppViewModel.swift` (import section),
`LibraryMediaWorkflowCoordinator.swift`, `PhotosImportTests.swift`.

---

### CQ-03 — Move package import, hashing, and index refresh off the main actor

**Evidence.** `PortableLibrarySession` is `@MainActor`. Its `importURLs`/`importData` run
`package.importSources`, which copies originals, fully hashes them, fsyncs, and commits
transactions, synchronously on the main actor. `refreshIndex()` then re-reads **all membership
shards** and rewrites the whole index JSON. Every production import path calls these inline from
`AppViewModel`: folder import, drop, promises, removable media (for example, a full SD card of RAW
files), and each Photos item when not batched. The UI freezes for the whole copy, with no
progress or cancellation for folder or removable imports.

Related waste:
- `PortablePackageImporter.importAsync` is not asynchronous. It's a synchronous body inside
  `async`, and its sibling `import(…) async` just forwards to it (`PortablePackageImport.swift:303–327`).
- The Photos path computes a full SHA-256 of the payload (`PhotosImportCoordinator`, detached).
  It then writes the payload to a temp file, and the package re-hashes it during import. In
  package mode the first digest is never used.

**Implementation.**
- Introduce a package import worker owned by the session: a `Sendable` service on the existing
  `ImageWorkScheduler` package-I/O lane (`canQueuePackageIO` exists but is unused). It takes a
  list of sources and returns an `AsyncStream` of progress plus a final `PortablePackageImportResult`.
  Cancellation must reach `isCancelled` between files and inside large copies.
- Main-actor code only starts imports, observes progress, and applies the result, meaning the
  collection reload (CQ-04) and opening the first asset.
- Make index maintenance incremental. Apply the membership delta returned by the import
  transaction to the in-memory projection and write it asynchronously and coalesced, instead of
  `LibraryIndexProjection(package:)` over all shards after every import.
- Remove the unused Photos-side digest in package mode, or pass it into the importer as a
  precomputed hash if the importer can trust it.
- Stream Photos payloads directly into package staging instead of writing a separate temp file
  when feasible.

**Acceptance.** Importing 200 × 25 MB generated files keeps main-actor hitches under 50 ms,
measured with the existing signposts. Progress and cancel work for folder and removable imports.
Cancellation leaves no partial asset. Main-thread checker and TSan runs are clean. The existing
single-writer invariant (`maxConcurrentPackageWriters == 1`) still holds.

**Files.** `PortableLibrarySession.swift`, `PortablePackageImport.swift`, `ImageWorkScheduler.swift`,
`LibraryQueryController.swift` (index delta), `AppViewModel.swift`, `PhotosImportCoordinator.swift`.

---

## P1 — performance, stability, and high-leverage removal

### CQ-04 — Drive the library UI from paged queries, not full-library materialization

**Evidence.** The launch path in `AppViewModel.init` (`~1175`) and `reloadPortableCollection()`
(called after every import, deletion, and refresh) both call `portableLibrary.materializedAssets()`.
That walks **every page** and, for each item, calls `package.readAssetRecord(for:)`, which opens
and decodes one JSON file per asset, synchronously on the main actor
(`PortableLibrarySession.swift:178–220`). The result is loaded into `ImageCollection`'s
`[Item]` of `ObservableObject`s.

At the 100,000-asset target this means 100k file reads plus 100k observable objects at launch and
after every mutation. `docs/LIBRARY_SCALE_REGRESSION.md` reports a 1.7 s warm launch at 100k, but
it measures the **paged** `LibraryQueryController` path, which production doesn't use for display.
The benchmark therefore gives false assurance.

Conversely, `LibraryQueryController` (658 lines) implements paging, sort, filter, and UUID
selection, and production uses none of it except to enumerate `.all`. Filtering and selection are
duplicated in `ImageCollection` (`LibraryFilter`, `LibrarySelectionModel`), which leaves two
selection states that can diverge.

**Implementation (staged).**
1. Stop reading asset records during materialization. Everything `PhotoAsset` needs for the grid
   is already in `LibraryIndexEntry.summary`. Derive the source URL from asset ID and shard, and
   resolve the full record lazily only when opening, exporting, or reading edits.
2. Make the grid and filmstrip consume `LibraryQueryController` pages (a windowed data source keyed by
   `PortablePhotoAssetID`). Move filter, sort, and selection to the query controller as the single
   authority, and delete the duplicated projection logic from `ImageCollection`.
3. Keep `ImageCollection` as a thin presentation adapter for thumbnails and visible-window state,
   or replace it outright. Coordinate with CQ-05.
4. Extend the scale benchmark to cover the **production** path: `AppViewModel` launch with a
   generated package, a first grid frame, and one import followed by reload.

**Acceptance.** Launch and reload never open asset records for non-visible items (assert with a
read observer, as the scale fixture already does). The production-path benchmark at 10k/100k is
recorded in `LIBRARY_SCALE_REGRESSION.md`. Only one selection model exists.

**Files.** `PortableLibrarySession.swift`, `LibraryQueryController.swift`, `ImageCollection.swift`,
`LibraryGridView.swift`, `FilmstripView.swift`, `LibrarySelection.swift`, `LibraryFilter.swift`, benchmarks.

---

### CQ-05 — Remove the legacy folder-backed library mode

**Evidence.** Production always runs in package mode. Both public `AppViewModel` initializers pass
`KromoraStorage.defaultPortableLibraryPackageURL` (`AppViewModel.swift:837–858`), and `KromoraApp`
and `ContentView` use them. The non-package branch is reachable only when tests call the internal
init with `portablePackageURL: nil`. Yet the legacy mode remains threaded through the code:

- **AppViewModel:** 15 `if let portableLibrary … else legacy` forks, covering open image, Photos
  insert/finish, `importPhotosData`, folder open, drop, removable media, deletion, and launch
  restore. There are also `portableLibraryFailureIsActive` guards and a legacy
  `EditDocumentStore.makeDefaultStore()` fallback.
- **ImageCollection:** about 900 lines of legacy code between lines ~471 and ~1400: source-folder
  bookmarks, `restoreSourceFolder`/`restoreLibrary`, `loadFromFolder` + `scanURLs`,
  `addFromData`/`addFromURLs`/`addFromMediaVolume`, `durableURL`/`durableDataURL`,
  data-import reservations, `persistsLegacyLibraryState`, and UserDefaults-persisted culling
  state and deleted-ID sets (package mode stores these in the package).
- **Production test hook:** `ImageCollection.shouldRejectProductionLibraryInTests` checks
  `NSClassFromString("XCTestCase")` and `KROMORA_TEST_ISOLATION` inside shipping code.
- **EditDocumentStore:** the standalone on-disk SwiftData store, bookmark/path relinking,
  `usesLegacyIdentityBridge`, and `rebuildProjectionFromLocalStore` (see CQ-16).
- **PreviewDiskCache:** `defaultDirectory()` is described in `STORAGE_POLICY.md` as for
  "legacy/test clients only".
- **Source-folder UI:** `chooseSourceFolder` + `openSourceFolder`. In package mode this already
  means "import this folder". Keep that behavior and drop the persisted-bookmark branch.

**Decision needed before starting.** Confirm that the referenced-folder browsing mode has no
future. ADR-001 and `LIBRARY_PACKAGE_PLAN.md` imply the package is the only product. If
referenced (non-copied) assets are wanted later, they belong in the package's
`storage: .referenced` model, not in this mode.

**Implementation (staged PRs).**
1. Migrate tests. About 54 `loadFromFolder` usages and the `makeTestCollection` helpers move to a
   package fixture helper, such as `makePackageBackedViewModel(assets:)`. This is the largest part
   of the work, so land it first while behavior is unchanged.
2. Make `portablePackageURL` non-optional in the internal init and delete every legacy branch in
   `AppViewModel`. A package open failure stays a fail-closed empty state, as it is today.
3. Delete the legacy sections of `ImageCollection` and the test-detection hook.
4. Remove `PreviewDiskCache.defaultDirectory` and the legacy `EditDocumentStore` paths (with CQ-16).
5. Keep the legacy `EditStore*.store` files untouched on disk per ADR-001 (no deletion or migration).

**Acceptance.** `grep -n "portableLibrary == nil\|if let portableLibrary" AppViewModel.swift`
finds no mode forks. There is no `NSClassFromString("XCTestCase")` in `Sources/`. The fast and
serial lanes are green, the packaged-app smoke test passes, and the net line count drops
substantially (expected 1,500+ lines).

**Files.** `AppViewModel.swift`, `ImageCollection.swift`, `EditDocumentStore.swift`, `EditRecord.swift`,
`PreviewDiskCache.swift`, `KromoraSettings.swift`, `LibraryDeletionCoordinator.swift`, many tests.

---

### CQ-06 — Replace root `objectWillChange` fan-in with Observation

**Evidence.** `AppViewModel.init` (`~1116–1134`) forwards `objectWillChange` from `settings`,
`library`, `collection`, `libraryMediaWorkflow`, `editorDocument`, `photosImportCoordinator`,
`export`, `derive`, and `lookSave` into the root. Each notification spawns a new main-actor `Task`
that calls `self.objectWillChange.send()`. That sends *after* the change on a later hop, so the
"will" semantics are wrong, and it costs one allocation per event. Every view that observes
`AppViewModel` (most of the window) re-evaluates on every thumbnail arrival, metadata update,
scan tick, and export or import progress step. `ImageCollection.Item` is itself an
`ObservableObject` with `@Published thumbnail`. `LUTLibrary.starterLooks`/`myLooks`/`lookCollections`
recompute, re-filter, and re-sort on every access (carry-over R6).

**Implementation.**
- macOS 14 is the deployment floor, so migrate models to `@Observable` (Observation framework)
  incrementally, starting with high-frequency publishers: `ImageCollection`/items,
  `PhotosImportCoordinator`, `ExportCoordinator`, and `CanvasInteractionState`. Views then track
  only the properties they read.
- Remove root forwarding for each child as its consumers migrate. Delete the forwarding loop at
  the end.
- Memoize Look projections per library revision.

**Acceptance.** Instrument body evaluation counts for `ContentView`, the inspector, and the grid.
Thumbnail streaming and progress updates don't re-evaluate the inspector or toolbar. Before and
after navigation and slider p95 on the same host show no regression. No `Task` is created per
change notification.

**Risk.** Mixed `ObservableObject`/`@Observable` during the transition is fine. Don't wrap
`@Observable` types in `@StateObject`. Coordinate with KRMA-512–515, which touch the same views.

---

### CQ-07 — Move preview disk-cache rasterization into the render actor and bound its I/O

**Evidence.**
- `PreviewPresentationCoordinator.writeCanonical` (`:105–120`), a view-model type, captures a
  `CIImage` into `Task.detached`. There it calls `PreviewDiskCache.canonicalRaster`, which
  creates a **new `CIContext` per call** (`PreviewDiskCache.swift:145`), renders at full extent,
  and then downsamples on the CPU through `CGContext`. That breaks the documented rule that
  `CIImage`/`CIContext` stay inside `RenderEngine` (CLAUDE.md), throws away Core Image's caches,
  and spawns one untracked, un-coalesced detached task per settled frame.
- `PreviewDiskCache.write` runs `enforceCap()` after **every** write, which enumerates and stats the
  whole cache directory. `init` runs `enforceCap()` synchronously inside `AppViewModel.init` on the
  main actor.
- A single library deletion calls `previewPresentation.cache.invalidateAll()`
  (`AppViewModel.swift:~2907`), which deletes every cached preview.
- Other ad-hoc contexts: `AppleEnhancementReference.swift:213` (per call), `LookLUTConverter.swift:250`,
  `RecipeExtractor.swift:494`.

**Implementation.** Add a `RenderEngining` method such as `canonicalPreviewRaster(for request:)`
that renders at the canonical long edge directly (scale inside the CI graph) with the engine's
context and returns `CGImage`/`Data`. Give the disk cache a serial writer with coalescing by key,
cancellation, and an in-memory size and LRU index loaded once in the background. Invalidate by key
prefix, meaning portable asset identity, on deletion. Route the other ad-hoc contexts through
`RenderEngineResources` or a shared per-owner context.

**Acceptance.** No `CIContext(` outside `RenderEngineResources`/`RenderEngine`, except documented
test utilities. Cache writes don't enumerate the directory. Deleting one photo leaves other
previews cached. Settled-frame memory peaks drop, measured with the existing preview cost benchmark.

---

### CQ-08 — Bound brush-mask rasterization (carry-over R4)

**Evidence.** `LocalMaskRenderer.brushImage`/`cachedStrokeRaster` (`LocalMaskRenderer.swift:242–330`)
allocate a full-frame `[Float]` per stroke plus a composite. For every pixel they loop over
**every** resampled stroke sample, with no bounding box and no radius cutoff. That is
O(pixels × samples) CPU work on each cache miss. A 24 MP frame is a 96 MB buffer, larger than
the 64 MiB stroke cache, so it is never cached. The loop has no cancellation checks, and the
cache order uses `removeAll { $0 == key }` (O(n)).

**Implementation.** Limit per-sample work to its dab bounding box (radius + feather), and limit
the raster to the evaluated ROI plus a halo. Tile or cache by (stroke, transform, scale, tile).
Check cancellation per row or tile. Better still, evaluate brush influence on the GPU as a Metal
CI kernel that splats samples (pairs well with CQ-09). Preserve preview/export parity and the
full-frame coordinate contract from `9b043c1`.

**Acceptance.** The parity tests described in R4 pass (brush + linear + radial + boolean ops,
crop and rotation, non-zero ROI origin). Cold brush-render time and peak allocation scale with
touched area, not frame size. Record the before and after figures.

---

### CQ-09 — Migrate deprecated CIKL kernels to Metal and precompile shaders

**Evidence.** Nine `CIKernel(source:)`/`CIColorKernel(source:)` uses, deprecated since macOS 10.14.
They account for 9 of the 35 build warnings: `RenderPipeline.swift` (5), `LocalMaskRenderer.swift` (3),
and `ToneCurveFilterCache.swift` (1). They compile at runtime and could be removed in a future
SDK. `PreviewSurface` also compiles `PreviewSurface.metal` from source at runtime
(`makeLibrary(source:)`, `PreviewSurface.swift:869`), which adds first-frame latency.

**Implementation.** Port the kernels to `.ci.metal` functions loaded with
`CIKernel(functionName:fromMetalLibraryData:)`. SwiftPM needs a build step for that. Options: a
checked build-plugin-free script that emits a `.metallib` into `Resources` (verify with CI), or
build-tool-plugin support if it avoids third-party dependencies. Keep a golden-pixel test per
kernel that compares old and new output within tolerance before deleting the CIKL source.
Precompile `PreviewSurface.metal` the same way.

**Acceptance.** Zero deprecation warnings in `Sources/`. Pixel parity tests pass in the serial
lane. No runtime shader compilation on first frame.

---

### CQ-10 — Delete the unused mask-overlay prototype (completed in KRMA-525)

The unused presentation prototype, its dedicated Metal source, benchmark, and prototype-only test
have been removed. Production mask rendering remains covered by `LocalMaskRenderingTests`, and the
presentation library/build lane now contains only the shipped preview surface.

---

### CQ-11 — Delete unreferenced functions, typealiases, views, and compatibility shims

Each item has **zero references in `Sources/` and `Tests/`** apart from its declaration (checked
by hand). Delete them in one PR. Re-run `swift build --build-tests` after each group, because
SwiftUI `#selector` or key-path use can hide references.

**Compatibility typealiases with no users.** `ColorMixerChannelAdjustment`, `ColorMixerChannelAdjustments`
(`ColorMixerAdjustments.swift:118–119`); `EditClipboard` (`EditClipboard.swift:280`); `OpaquePhotoAssetID`,
`OpaquePhotoIdentity`, `OpaquePhotoSourceFingerprint` (`PortablePhotoIdentity.swift:~216–220`);
`PhotoAssetState` (`PhotoAsset.swift:519`); `LibraryQueryController` nested `Query`, `Sort`,
`SortDirection`, `SortKey`, `Page` (`LibraryQueryController.swift:~440`); public `ReleaseFeed` and
`UpdateInstaller` (direct-distribution only). `Release` has test users, so keep it or migrate them.

**Unreferenced views and types.** `AnalysisDebugPanel` (the struct in `AnalysisDebugPanel.swift:3`;
keep `PhotoAnalysisInspectSection`, which `InfoInspectorView` uses); `AdjustInspectorView`
(`AdjustInspectorView.swift:14`; confirm it isn't meant to be wired in before deleting);
`VisionAestheticsScores`.

**Unreferenced functions (no tests either).**
- `AppViewModel`: `updatePhotosImportPhase`, `toggleLibraryGrid`, `selectPreviousLUT`/`selectNextLUT`,
  `rotateSelectedImage`, `chooseLUTFolder`
- `AppViewModel+Color`: `whiteBalanceValue`
- `AppViewModel+Masking`: `updateSelectedMask`, `resetMaskingWorkspace`
- `EditorDocumentCoordinator`: `removeSessions`, `clearClipboard`. `removeSessions` is interesting:
  sessions are never evicted, which is carry-over R5's unbounded history. Wire it into deletion or
  add a budget rather than just deleting it.
- `EditDocumentStore.rebuildFromPackage`, `LibraryQueryController.clearSelection`,
  `MaskInteractionState.clearGestureHandle`/`clearComponentSolo`, `MaskStore.bestAvailable`,
  `RadialGradientMaskMath.outerPoint`, `InfoInspectorView.inspectorTransition`, `PreviewSurface.layoutExtent`
  and `presentationFrame`
- Unused properties: `ImageCollection.canUndoCulling`/`importedDataCount`, `AppViewModel.deletedCount`/
  `peakPendingPersistenceCount`, `EditDocumentStore.canonicalPackageURL`,
  `ToneCurveFilterCache.hasCachedCurve`, `ImageMetadata.hasCameraInfo`, `EditHistory.redoCount`,
  `PortableLibraryValidation.isClean`/`hasCriticalFailures`, `LibraryQueryPage.hasPreviousPage`,
  `AnalysisImage.cgRect`

**Test-only façade in production** (declared in `Sources/`, called only by tests):
`AppViewModel.beginPhotosImport`, `appendPhotosImport`, `recordPhotosImportFailure`,
`finishPhotosImport`, `importPhotosData`, `toggleSourceBrowser`, `dismissRecipeExtractor`. Point the
tests at `PhotosImportCoordinator` with a fake destination, then delete the façade. This overlaps
CQ-02.

**Deprecated shim.** `PhotosImportCoordinator.init(viewModel:)` and `setProgressForCompatibility`,
if CQ-02 hasn't already removed them.

**Acceptance.** Build and all lanes are green with no behavior change, and the PR description
lists each removed symbol.

---

## P2 — architecture, hygiene, hardening

### CQ-12 — Separate diagnostics and evaluation code from the shipping Auto path

**Evidence.** The production module ships harness code that only tests and scripts use:
- `AutoCandidateEvaluation.swift`: `AutoCandidateEvaluator` (20 test references, 0 production),
  `checkPreviewExportParity`, `writeArtifact` (writes evaluation artifacts to disk),
  `AutoEvaluatedRender`, `AutoEvaluationReport`
- `AutoPerformanceDiagnostics.swift`: `VisionAestheticsDiagnostics`/`Scores` (test-only)
- `LiveEditTelemetry`, plus `…ForTesting` hooks and counters on `RenderEngine`, `PreviewSurface`,
  `PortablePackageMaintenance`, and `MaskStore` (7 `ForTesting` symbols and many
  statistics-only properties)

**Implementation.** Move evaluation and report types into the test target, or into a small internal
`KromoraDiagnostics` target that `KromoraKitTests` and `scripts/photo-intelligence-*` depend on.
Group runtime counters behind one `RenderDiagnostics` snapshot API instead of scattered
properties. Keep only the shared *value* types in `KromoraKit` (for example
`AutoCandidateEvaluation`, which `CurrentEditMeasurement` uses).

**Acceptance.** No file-writing evaluation code in the app binary. Scripts still run. Update
`PackageSettingsTests` if a target is added (Swift 6 mode and no opt-outs apply to the new target).

---

### CQ-13 — Extract the Auto workflow and retire the histogram fallback

**Evidence.** `AppViewModel.runAutoAdjustment` spans about 300 lines (`~1403–1700`). It contains
the content-aware path *and* a legacy histogram fallback built on `AutoAdjustmentAnalyzer`
(`AutoAdjustment.swift`, whose header says it inspects no subjects or regions). Two Auto policies
means two behaviors to test and explain.

**Implementation.** Decide whether the fallback is still reachable in practice. If content-aware
Auto can always run once a preview exists, delete the fallback and `AutoAdjustment.swift`.
Otherwise, keep it as an explicit degraded mode inside a new `AutoWorkflowCoordinator`. That
coordinator owns invocation revisions, progress, cancellation, and the value-only result that the
root applies through the normal document commit path (the shape described in R5 step 5).

**Acceptance.** `AppViewModel` holds no Auto policy logic. The coordinator has fake-engine tests
without constructing `AppViewModel`. The Auto quality regression lane is unchanged.

---

### CQ-14 — Continue AppViewModel decomposition

**Evidence.** `AppViewModel.swift` is still **5,464 lines**, with 31 `@Published`, 28 task
references, and about 200 functions. Its extensions add about 1,900 more, including
`AppViewModel+Masking.swift` at 1,310. The main remaining clusters, after CQ-05 removes the
legacy forks and CQ-13 extracts Auto, are:

| Cluster | Approx. lines | Target owner |
| --- | --- | --- |
| Package import orchestration (all entry points) | 2430–2800 | `LibraryImportCoordinator`, built on CQ-02/03 |
| Edit-aware thumbnails | 2986–3239 | `EditedThumbnailCoordinator` |
| Copy/paste, undo/reset, history application | 3239–3500, 4474–4974 | `EditorDocumentCoordinator`, which already owns sessions |
| Crop, rotation, canvas navigation | 4138–4474 | `CanvasInteractionState` / crop workflow |
| Masking extension | +1,310 | `MaskingWorkflowCoordinator` (drafts vs committed recipes) |

**Rules.** One extraction per PR. Each new owner states its owned state, commands, published
values, revision fences, tasks, shutdown, and resource limits, as `APP_ARCHITECTURE.md` requires.
Each gets fake-only tests. Don't add a second document store or an event bus.

**Acceptance.** Per PR: behavior tests for the moved workflow without `AppViewModel`, and the
existing integration tests still green. Record a responsibility inventory in the PR.

---

### CQ-15 — Split RenderEngine by responsibility and bound its bookkeeping

**Evidence.** `RenderEngine.swift` is 2,713 lines in one actor. It covers rendering, histogram,
RAW capabilities, the mask resolution and overlay pipeline, the semantic-mask in-flight table,
the developed-source cache, and statistics.
`latestRenderRequestRevisions: [String: UInt64]` gains one entry per source fingerprint and is
pruned only by `invalidateAll` (`:559, 1852, 2394`), so it grows without bound over a long
session. Mask-revision eviction uses `min(by:)` in a `while` loop, which is O(n²) in the worst case.

**Implementation.** Keep one actor, the isolation boundary, but split its code into
responsibility-scoped files or extensions and nested non-actor helpers (`MaskResolutionState`,
`DevelopedSourceCache`, `RevisionLedger`) that the actor owns. Bound the revision ledgers with
`BoundedCache` (which already exists) or prune on source change.

**Acceptance.** No behavior change (render, mask, and histogram tests green). Ledger size is
bounded under a navigation stress test.

---

### CQ-16 — Simplify EditDocumentStore to a package-backed cache

**Evidence.** In package mode, SwiftData is only an **in-memory projection**
(`makeInMemoryProjectionStore`), with the package sidecars as the source of truth. The
store still carries `ModelContainer` setup, a `try!` on container creation
(`EditDocumentStore.swift:225`), path and bookmark relinking, legacy identity bridging, and a
standalone-store rebuild. That is 867 lines, and most of it serves CQ-05's legacy mode.

**Implementation.** After CQ-05, replace the SwiftData projection with a plain bounded
`[PortablePhotoAssetID: EditDocument]` cache in front of `PortableLibraryPackage` edit revisions.
Keep the status and error model and the retry and coalescing behavior of
`EditPersistenceCoordinator`. Remove `EditRecord` and the SwiftData dependency if nothing else
uses them.

**Acceptance.** Persistence integration tests green, including corrupt revision, write failure,
flush on terminate, and relaunch round-trip. No `try!` left in `Sources/`.

---

### CQ-17 — Reach a zero-warning build and enforce it; reduce test-only production surface

**Evidence.** `swift build --build-tests` at `d6e4977` produces 35 unique warnings.
CLAUDE.md claims zero diagnostics.
- 9 × CIKL deprecation (fixed by CQ-09)
- Test target, **Swift 6 actor-isolation warnings** that will become errors: `CropTests.swift`,
  7 sites (`handleHitPosition`, `handleHitTargetSize`, `CropOverlayView.init` from a nonisolated
  context)
- 12 × unused `flushPendingWrites()` result (`EditPersistenceIntegrationTests` ×7, `LUTWorkflowTests` ×4,
  `CropTests` ×1). These tests **drop the persistence result they are meant to verify**.
- 5 × deprecated `PhotosImportCoordinator.init(viewModel:)` (`PhotosImportTests`)
- 2 × trivial (`SceneEvidenceTests` unused value, `GlobalToneAnalyzerTests` `var`→`let`)

**Implementation.** Fix all of these. Mark crop tests `@MainActor`. Assert
`XCTAssertEqual(await flushPendingWrites(), .success)`. Then add a CI gate: fail on any
new warning in `Sources/` and `Tests/`, either with `-warnings-as-errors` via `unsafeFlags` in a
CI-only configuration or by grepping the build log in `scripts/ci-tests.sh`. Extend
`PackageSettingsTests` or the CI script so the zero-warning claim is enforced by a machine.

**Acceptance.** Clean build log. CI fails on an introduced warning.

---

### CQ-18 — Harden the direct-distribution updater and verify it under App Sandbox

**Evidence** (`Presentation/UpdateInstaller.swift`, only when `KROMORA_DIRECT_DISTRIBUTION` is set).
The code is careful overall: HTTPS-only, the Developer ID anchor, pinning to the running app's
Team ID and bundle ID, strict nested validation, and positional `sh -c` args. Gaps:
- **Verify-then-copy:** `verify(newApp)` runs on the mounted image, then `swap` copies it. The copy
  in `staged` is never re-verified. Re-verify `staged` before the rename (defense-in-depth against
  TOCTOU and partial copies).
- **Sandbox compatibility is unverified.** `Kromora.entitlements` enables App Sandbox for
  every build, including direct distribution. A sandboxed process usually can't run `hdiutil`
  through `Process` or replace its own bundle in `/Applications`. Verify on a signed, sandboxed
  release build. If in-place install can't work, gate `canInstallInPlace` on it and fall back to
  opening the release page, or ship the direct build unsandboxed with its own entitlements file.
- `hdiutil attach -noverify` skips image checksum verification. This is acceptable because code
  signature verification follows, but document the reason.
- Release notes (untrusted remote text) render as plain `Text`, which is fine. Keep them out of
  Markdown or `AttributedString` link rendering.

**Acceptance.** A test verifies that the staged copy passes `verify`. A manual sandboxed
release-build check is recorded in `docs/PACKAGING.md` with its outcome.

---

### CQ-19 — Centralize package path safety and shared helpers

**Evidence.**
- `PortableLibraryPackage.isSafeRelativePath` rejects absolute paths, `..`, empty components,
  and backslashes, but allows `.` components and doesn't resolve symlinks. A package received
  from elsewhere could contain an `Assets/.../Original` symlink that points outside the package,
  and reads would follow it. The sandbox limits the impact, but validation should reject it.
- Duplicated helpers: `safeFilename` (`PortableLibrarySession.swift:264`, `PortablePackageImport.swift:339`),
  21 private `clamp` variants across 11 model files (at least 6 identical copies in
  `LocalMaskModels.swift` alone), and repeated `JSONEncoder` configuration (24 sites).

**Implementation.** Add one `PackagePath` value type that validates components and resolves the
path against the package root, checking that the resolved, symlink-free path stays under the
root. Use it in the package, sidecar, validation, restore, and backup code. Report symlinks as
`criticalFailures` in `PortableLibraryValidation`. Collapse `clamp` into one
`Comparable.clamped(to:default:)` for non-finite handling. Share one filename sanitizer and one
package JSON coder.

**Acceptance.** Tests cover a symlinked original, a `./` component, and a traversal attempt.
There's one helper per concern.

---

### CQ-20 — Reconcile documentation with the package-backed product

**Evidence.**
- `CLAUDE.md` line 3 says *"The current product is the folder-backed Library/Edit workflow"* and
  calls the portable library "explicitly future". Production is package-backed.
- `docs/DOCUMENTATION_AUDIT.md` repeats the folder-backed claim and lists docs as they stood
  on 2026-09-12.
- `docs/LIBRARY_PACKAGE_PLAN.md` §1 says "Kromora today browses referenced folders".
- `docs/REPOSITORY_IMPROVEMENT_PLAN.md` doesn't mark which items are done, open, or moot.
- `docs/LIBRARY_SCALE_REGRESSION.md` doesn't say that the production UI path is not measured
  (CQ-04).
- `docs/ENGINEERING_GUIDE.md` persistence section still describes the standalone v2 store
  (update after CQ-16).

**Implementation.** Update these in the same PRs that change behavior (CQ-04, CQ-05, CQ-16), plus
one immediate docs-only commit for `CLAUDE.md` and the improvement-plan status. Repo-meta docs may
go straight to `main` per CLAUDE.md. Point `REPOSITORY_IMPROVEMENT_PLAN.md` at this file for the
remaining work, or retire it.

---

## Sequencing and conflict map

```
CQ-01 ──► CQ-02 ──► CQ-03 ──► CQ-04 ──┐
                       │               ├─► CQ-05 ──► CQ-14, CQ-16 ──► CQ-20 (final)
                       └───────────────┘
CQ-10, CQ-11            independent, do early (shrinks surface for everything else)
CQ-07, CQ-08, CQ-09     independent of the library chain; CQ-09 before CQ-17's gate
CQ-12 ──► CQ-13
CQ-06                   after CQ-05 ideally; coordinate with KRMA-512–515 UI work
CQ-15                   after CQ-07/08/09 (same files)
CQ-18, CQ-19            independent
```

**Parallel-safe groups** (disjoint files): {CQ-01→03 chain}, {CQ-10, CQ-11}, {CQ-08, CQ-09},
{CQ-12→13}, {CQ-18}, {CQ-19}.
**Serialize these, which share hot files:** `AppViewModel.swift` (CQ-02, 03, 04, 05, 06, 13, 14),
`ImageCollection.swift` (CQ-04, 05, 06), `RenderEngine.swift` (CQ-07, 09, 15),
`LocalMaskRenderer.swift` (CQ-08, 09).

## Verified OK: no ticket needed

These were checked and found sound, so agents shouldn't spend time on them:
- Swift 6 strictness: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` in `Sources/`.
- `.cube` parsing is bounded: file size limit, `LUT_3D_SIZE` ≤ 65, and strict row validation.
  The Package.swift starter-Look manifest check is fail-closed.
- XMP parsing uses `XMLParser` with external entities disabled and a fixed property whitelist.
- Package writer lease acquisition uses `O_EXCL` and never steals a live lease. Only renewal is
  missing (CQ-01).
- No `as!` in `Sources/`, and only one `try!` (CQ-16).
- Entitlements are minimal for the feature set, apart from the updater question in CQ-18.
