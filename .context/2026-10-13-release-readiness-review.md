# Kromora Release Readiness Review — 2026-10-13

> **Dated review, not a roadmap.** Findings reflect `main` at `ccc575c2` (KRMA-920) on 2026-10-13.
> Current product intent remains in [`PRODUCT_SCOPE.md`](../docs/PRODUCT_SCOPE.md); items below
> become work only when accepted into DispatchGraph issues.
>
> **Board status as of 2026-10-14.** Tracked by [KRMA-922](../.dg/issues/KRMA-922.md). The findings
> below are unchanged historical notes. Each heading now carries the current ticket outcome.
> Shipped work is also summarized in
> [the 2026-10-14 review](2026-10-14-release-readiness-review.md).

## Status ledger (2026-10-14)

| Finding | Tickets | Outcome |
| --- | --- | --- |
| M1 Canvas color management | KRMA-923 | Done |
| M2 Undo/Redo and command enablement | KRMA-924, KRMA-925 | Done |
| M3 Keyboard rework verification | KRMA-926 | Done (signed-app spot check recorded) |
| M4 Test hangs, warning gate, CI | KRMA-927, KRMA-928, KRMA-929 done; KRMA-967 ready; KRMA-930 in review | Gate and the named hangs are fixed. CI on the release candidate is still blocked on a human push. KRMA-967 still bounds leftover `Task.yield()` loops. |
| M5 Main-actor package writes | KRMA-931, KRMA-932, KRMA-933, KRMA-934, KRMA-935 | Done |
| M6 Backup/restore and Open Library | KRMA-936, KRMA-937, KRMA-938, KRMA-939, KRMA-988 | Decided. Backup/restore and Finder open were closed unbuilt (post-MVP). Claims were removed; Settings can choose a library for the next launch. |
| S1 `AppViewModel` observation | KRMA-940, KRMA-972–KRMA-981 | Done |
| S2 Display P3 preview | KRMA-941 | Backlog |
| S3 Export peak memory | KRMA-942 | Backlog |
| S4 Launch I/O | KRMA-943, KRMA-944 done; KRMA-945 backlog | Package open and computer-name lookup are off the old path. The `swift run` activation workaround is still open. |
| S5 Quit during import/export | KRMA-946 | Done |
| S6 App-modal panels | KRMA-947, KRMA-948 | Done |
| S7 Share representation | KRMA-949 | Done |
| S8 `ImageSource` file I/O | KRMA-950 | Done |
| S9 Grid and Edit latency | KRMA-951 done; KRMA-952 backlog | Grid identity and scroll tracking shipped. Reopening the 50/100 ms Edit budgets is still a decision. |
| S10 Per-render hashing | KRMA-953, KRMA-954 | Backlog |
| S11 Menu conventions | KRMA-955 done; KRMA-956 backlog | Ellipsis and import/refresh titles shipped. Delete / ⌘S / ⌘D is still a decision. |
| Nice to have | KRMA-957–KRMA-962, KRMA-964 backlog; KRMA-963, KRMA-965 ready | Still open. File-menu `NotificationCenter` plumbing was replaced with KRMA-925. |

**Scope:** release readiness judged on code quality, performance, stability, ease of use, and
platform polish. Effort to resolve is deliberately out of scope. No product source was changed.

**Method:** read the architecture/scope/testing docs, the render engine and resources, package
session/transaction/lease code, `AppViewModel` and coordinators, menus and keyboard routing,
preview surface and Metal presentation, export and share paths, app delegate lifecycle, and the
packaging inputs; searched the tree for crash-prone, blocking, and legacy patterns.

**Verification run during the review:**

| Check | Result |
| --- | --- |
| `swift build` | Clean |
| `scripts/ci-tests.sh serial` | **Pass** — 526/526 |
| `scripts/ci-tests.sh fast` | **Fail** — `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` timed out ("second photo to settle"), then hung in teardown until killed. Passes 3/3 in isolation (~1.3 s). |
| Warning gate | Not re-run; KRMA-920 reports it fails, and the cause is confirmed in source (see M4). |
| Display-bound benchmarks | Not run (per `CLAUDE.md`); performance figures cited from `docs/TESTING.md`. |

Three orphaned `xctest` processes from 2026-10-12 (`RetouchWorkflowCoordinatorTests`) were found
spinning at ~170% CPU each for 16+ hours and were killed during the review; that load likely
contributed to the fast-lane timeout.

---

## Must fix before release

### M1. The editing canvas is not color-managed

**Status (2026-10-14):** done — KRMA-923.

The `MTKView` uses `.bgra8Unorm` and never sets a layer color space
([`PreviewSurface.swift:1178`](../Sources/KromoraKit/Views/PreviewSurface.swift)). The presentation
shader samples the texture straight through (`Resources/PreviewSurface.metal`). With a nil
`CAMetalLayer.colorspace`, Core Animation does not color-match, so sRGB-encoded pixels are sent to
the display as-is. On the P3 panels in every Apple Silicon Mac, the canvas should therefore appear
more saturated than grid thumbnails (`NSImage`/`CGImage`, color-managed by AppKit), exported files,
and the same photo in Preview.

**Verify:** Digital Color Meter on a saturated photo, canvas vs. grid thumbnail vs. exported JPEG in
Preview. **Fix direction:** set the layer color space to the working space at minimum; see S2 for
wide gamut/EDR.

### M2. ⌘Z / ⇧⌘Z are duplicated in the File menu and likely steal text undo

**Status (2026-10-14):** done — KRMA-924, KRMA-925.

`CommandGroup(replacing: .newItem)` puts Undo, Redo, Reset Photo, Apply Auto, Copy/Paste Edits,
Derive, Export, and Delete in the **File** menu
([`MenuCommands.swift:79-150`](../Sources/KromoraKit/Views/MenuCommands.swift)). The standard
Edit › Undo/Redo still exists with the same key equivalents. AppKit resolves key equivalents across
the main menu in order, so the File item should win, meaning ⌘Z inside a text field (Look name,
search, rename) would undo the photo edit instead of the text. No test covers this.

Related: no File-menu item has enabled/disabled state (all post `NotificationCenter` notifications
unconditionally), so commands appear available with no photo open. Undo titles are not dynamic
("Undo Exposure").

**Fix direction:** integrate with the window `UndoManager` (or `CommandGroup(replacing: .undoRedo)`
that defers to the text system when a field editor is first responder); move editing commands to
Edit/Photo menus; drive enablement from focused scene values.

### M3. KRMA-920 keyboard rework is unverified in the running app

**Status (2026-10-14):** done — KRMA-926. The signed-app spot check and no-beep pass are recorded.

- Photo/Tools menu items are `.disabled(keyboardRouter == nil)`
  ([`MenuCommands.swift:164`](../Sources/KromoraKit/Views/MenuCommands.swift)). If
  `@FocusedValue(\.keyboardRouter)` does not resolve in the real scene, every plain-key shortcut
  (C, V, I, P, X, 1–5, `[`, `]`, …) is dead.
- Items are otherwise always enabled by design, so unavailable commands are silent no-ops (HIG
  deviation).
- Plain ⌘V no longer pastes edits (only ⌥⌘V).
- The "no alert beep" acceptance check (by ear) has not been performed.

**Required before release:** hands-on pass in the signed sandboxed app covering every inventory key
in each focus state.

### M4. The required test gate is not reliably green, and failures hang instead of failing

**Status (2026-10-14):** mostly done. KRMA-927, KRMA-928, and KRMA-929 are done. KRMA-967 (remaining unbounded `Task.yield()` loops, child of KRMA-928) is `ready`. KRMA-930 is in `review`, blocked until someone pushes the release candidate and shares the Actions run.

- `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` (KRMA-919) is
  load-sensitive: 1.3 s alone, >5 s under parallel load. When `waitUntil` throws before
  `gate.release(oneID)`, the teardown's `viewModel.shutdown()` awaits the gated materialization task
  forever. The gate must be released in teardown.
- `RetouchWorkflowCoordinatorTests` uses unbounded `while … { await Task.yield() }` loops (e.g.
  `testThresholdBurstCoalescesAndFinalThresholdWins`). A regression becomes an infinite CPU spin,
  not a failure. (The orphaned runs predate the final KRMA-901 commit, so they do not by themselves
  prove a current product bug; the hang-on-failure design is the defect.)
- Warning gate fails on a real test bug: `"(name) should visibly desaturate…"` is missing the
  interpolation backslash
  ([`ColorMixerTests.swift:193`](../Tests/KromoraKitTests/ColorMixerTests.swift)).
- `main` is 156 commits ahead of `origin`; CI has not run on the release candidate.

### M5. Durable package writes run synchronously on the main actor

**Status (2026-10-14):** done — KRMA-931, KRMA-932, KRMA-933, KRMA-934, KRMA-935.

`PortableLibrarySession` is `@MainActor`, and these calls perform full package transactions
(journal writes, `F_FULLFSYNC` per file, directory fsyncs, checksums, renames) inline:

| Path | Location | Impact |
| --- | --- | --- |
| Rating / flag | `LibraryBrowsingCoordinator.persistPortableLibraryStateIfNeeded` → `updateLibraryState` ([`LibraryBrowsingCoordinator.swift:570`](../Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift)) | One transaction per selected photo, in a loop; also `items.first(where:)` per asset. Culling a large selection stalls the UI. |
| Virtual copy | `PortableLibrarySession.createVirtualCopy` ([`PortableLibrarySession.swift:1167`](../Sources/KromoraKit/Models/PortableLibrarySession.swift)), invoked via a synchronous `@MainActor` closure in [`EditHistoryCoordinator.swift:194`](../Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift) | Copies and hashes the whole original (100+ MB RAW), then `refreshIndex()` rebuilds the entire projection. |
| Delete | [`LibraryDeletionCoordinator.swift:174`](../Sources/KromoraKit/ViewModels/LibraryDeletionCoordinator.swift) | Each removal blocks. |
| Legacy open repair | `materializedAsset` → `replaceSourceFingerprint` ([`PortableLibrarySession.swift:1385`](../Sources/KromoraKit/Models/PortableLibrarySession.swift)) | Write transaction during photo open. |

`withWriterMutationLock` additionally holds an `OSAllocatedUnfairLock` across this disk I/O.

**Fix direction:** route all package mutations through the existing package-I/O scheduler/worker;
coalesce culling writes per shard (one transaction for N ratings) with optimistic UI.

### M6. Backup/restore and library selection are not reachable from the UI

**Status (2026-10-14):** decided, not built as originally framed. KRMA-936 recorded the decision: backup/restore and Finder document open stay post-MVP (KRMA-937 and KRMA-938 closed unbuilt). KRMA-939 removed the claims. KRMA-988 adds Settings > Choose Library… for the next launch.

- `PortableLibraryBackup` / `PortableLibraryRestore` are implemented and tested but have no callers
  outside their own files.
- The library is fixed at `~/Pictures/Kromora Library.kromoralibrary`
  ([`KromoraStorage.swift:93`](../Sources/KromoraKit/Models/KromoraStorage.swift)); there is no
  Open/New/Move Library UI.
- `Info.plist` declares `CFBundleDocumentTypes` (role Editor, rank Owner) for
  `com.kromora.kromoralibrary`, but no open handler exists, so double-clicking a library in Finder
  does nothing.
- README and PRODUCT_SCOPE list "verified backup/restore" in the MVP and release bar.

**Decision required:** wire Backup/Restore (and ideally Open Library) into the app, or remove the
claims and the document-type declaration before release.

---

## Should fix (high value)

### S1. `AppViewModel` invalidates most of the UI on every edit

**Status (2026-10-14):** done — KRMA-940 and observation steps KRMA-972 through KRMA-981.

`AppViewModel` is an `ObservableObject` with 41 `@Published` properties plus synchronous
`objectWillChange` forwarding from seven child objects
([`AppViewModel.swift:1393`](../Sources/KromoraKit/ViewModels/AppViewModel.swift)). About 20 views
hold it via `@ObservedObject` (inspectors, status bar, culling bar, grid rows, masking workspace).
Each slider tick publishes `document` and re-evaluates all of them. Migrating the root to
`@Observable` gives per-property tracking and is the largest available SwiftUI performance win.
The file is 5,111 lines (6,511 with extensions) against a 5,120-line guard.

### S2. sRGB-only preview pipeline

**Status (2026-10-14):** open — KRMA-941 (`backlog`).

`WorkingSpace.current = .sRGB`
([`WorkingSpace.swift`](../Sources/KromoraKit/Models/WorkingSpace.swift)), so the canvas is
clipped to sRGB on P3 displays, while export offers Display P3. A P3 export cannot be previewed
accurately. Moving preview to Display P3 (or extended linear with `rgba16Float` and EDR) matches
Photos.app on current hardware. The `RecipeExtractor` sRGB pin documented in `WorkingSpace` is the
prerequisite.

### S3. Export peak memory

**Status (2026-10-14):** open — KRMA-942 (`backlog`).

`RenderEngine.encode` renders a full `CGImage`, then encodes into an `NSMutableData`
([`RenderEngine.swift:1201`](../Sources/KromoraKit/Models/RenderEngine.swift)), then
`ExportCoordinator.write` writes that `Data` with `.atomic` (a second temp file). A 60 MP 16-bit TIFF
peaks around 850 MB+; 100 MP sources exceed 1.4 GB. Encode straight to a staging file with
`CGImageDestinationCreateWithURL`.

### S4. Launch does blocking work before the first window

**Status (2026-10-14):** mostly done. KRMA-943 and KRMA-944 are done. KRMA-945 (limit the `swift run` activation workaround) is `backlog`.

- Package open, lease acquisition, and dead-writer recovery (`PortablePackageTransaction.recover`,
  which can checksum staged files) run inside `KromoraAppDelegate.init` → `AppViewModel.init` on the
  main thread.
- The lease's default `deviceName` uses `Host.current().localizedName`
  ([`PortablePackageTransaction.swift:222`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift)),
  which is known to block for seconds on some networks. Prefer
  `SCDynamicStoreCopyComputerName`.
- `setActivationPolicy(.regular)` / `activate(ignoringOtherApps:)` (a `swift run` workaround) and an
  `NSAlert.runModal()` lease prompt can run before `applicationDidFinishLaunching` in the production
  delegate.

### S5. Quit silently cancels imports and exports

**Status (2026-10-14):** done — KRMA-946.

`applicationShouldTerminate`
([`KromoraAppDelegate.swift:43`](../Sources/KromoraKit/Presentation/KromoraAppDelegate.swift)) only
flushes edits; an in-flight batch export or import is cancelled during `shutdown()` without
confirmation.

### S6. App-modal panels and alerts presented from view models

**Status (2026-10-14):** done — KRMA-947, KRMA-948.

Thirteen `runModal()` calls (`NSSavePanel`, `NSOpenPanel`, `NSAlert`) across `ExportCoordinator`,
`ExportWorkflowCoordinator`, `LookSaveCoordinator`, `DeriveCoordinator`, `AppViewModel`,
`AppKitFileDialogAdapter`, and the app delegate. Mac convention is window-attached sheets
(`beginSheetModal(for:)` or SwiftUI `fileExporter`/`fileImporter`/`alert`), and presentation belongs
in the view layer.

### S7. Share exports full-resolution 16-bit TIFF

**Status (2026-10-14):** done — KRMA-949.

[`ExportWorkflowCoordinator.swift:295`](../Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift)
renders `.tiff` at full size before showing `NSSharingServicePicker`, anchored to the key window's
content view rather than the Share control. Sharing to Messages/AirDrop/Mail should use HEIC or JPEG
at a sensible size, and the picker should appear immediately (deferred file promise) from the
button.

### S8. `ImageSource.init` performs file I/O and can hash a whole file

**Status (2026-10-14):** done — KRMA-950.

`ImageSource.init` stats the file (`PhotoSourceFingerprint.file(at:)`, including a sample digest) and,
on the fallback path, reads and SHA-256s the entire original on whatever thread constructs it
([`ImageSource.swift:228`](../Sources/KromoraKit/Models/ImageSource.swift)). This already regressed
once onto the main actor (KRMA-860). Make the initializer pure and move identity resolution to an
explicit asynchronous, off-main step; stream hashing instead of `Data(contentsOf:)`.

### S9. Library grid and Edit entry latency

**Status (2026-10-14):** partial. KRMA-951 is done. KRMA-952 (whether to reopen the 50/100 ms Edit-entry budgets) is `backlog`.

- Grid: user-visible "Showing X of Y — scroll for more" paging; scroll position tracked through a
  `GeometryReader` preference that re-runs the grid body every 24 pt; rows identified by index
  (`ForEach(0..<rowCount, id: \.self)`). Warm re-entry p95 ≈ 150 ms (TESTING.md, 2026-10-11).
- Edit: warm first pixel p95 ≈ 190 ms with an exact stored frame and zero renders — SwiftUI mount
  cost. The 50/100 ms budgets were closed as won't-do (KRMA-748/749/750); for the "instant" bar they
  are worth reopening.

Consider `onScrollGeometryChange`/`scrollPosition`, stable item identity, and a continuous virtualized
grid whose scroller reflects the full library.

### S10. Per-render JSON + SHA-256 hashing of the edit document

**Status (2026-10-14):** open — KRMA-954 (structural keys) and KRMA-953 (shared hex encoder), both `backlog`.

`RenderCacheHash.digest(_:)` JSON-encodes with sorted keys and SHA-256s
([`RenderCacheKey.swift:157`](../Sources/KromoraKit/Models/RenderCacheKey.swift)); a single render
request hashes the document, mask recipes, and RAW develop several times
([`RenderEngine.swift:214`](../Sources/KromoraKit/Models/RenderEngine.swift), `:2224`, `:2290`,
`:2787`). With brush masks this is several milliseconds per slider tick on the render actor. Use
structural `Hashable` keys or revision counters; hex encoding via `String(format:)` per byte
appears at 21 sites.

### S11. Menu and shortcut conventions

**Status (2026-10-14):** partial. KRMA-955 (ellipsis and import/refresh titles) is done. KRMA-956 (Delete, ⌘S, ⌘D conventions) is `backlog`.

- Delete Selected Photos uses bare Delete; Photos uses ⌘⌫ for destructive removal.
- ⌘S runs Export; ⌘D runs Derive Look.
- Titles mix `...` and `…`.
- "Open Source Folder…" is an import, and "Refresh Library" (⌘R) is a leftover concept for a
  package library.

---

## Nice to have

**Status (2026-10-14):** still open, except the File-menu `NotificationCenter` item, which KRMA-925 replaced. KRMA-963 and KRMA-965 are `ready`; the rest below are `backlog`.

- **`Task.detached { … }.value`** appears ~39 times; it drops cancellation and priority inheritance. KRMA-957, KRMA-958.
  Swift 6.2 `@concurrent` nonisolated functions are the modern idiom.
- **Concurrency escape hatch:** `OSAllocatedUnfairLock(uncheckedState:)` / `withLockUnchecked` in
  [`Thumbnails.swift:209`](../Sources/KromoraKit/Models/Thumbnails.swift) is not caught by
  `PackageSettingsTests`; with `CGImage` now `Sendable` it may be unnecessary. KRMA-959.
- **Localization:** no String Catalog; user-facing strings are composed in view models with manual
  plurals. KRMA-960.
- **Menu plumbing:** File-menu commands use `NotificationCenter`; `FocusedValue` gives enablement
  for free. Done in KRMA-925.
- **Logging:** photo-switch logs at `.notice` are persisted in release; subsystem `com.kromora.app`
  does not match bundle ID `com.last8.kromora.photo` (KRMA-892); `print()` remains at
  [`LUTLibrary.swift:283`](../Sources/KromoraKit/Models/LUTLibrary.swift) and `:580`; detail strings
  are built eagerly outside `os_log` interpolation. KRMA-961.
- **Code cleanups:** `try!` in
  [`PortableLibraryPackage.swift:641-655`](../Sources/KromoraKit/Models/PortableLibraryPackage.swift)
  (safe today, not idiomatic); dead `#if os(macOS)` branch in `fullSync`; test-only
  `waitUntilCompleted` seam in production `PreviewSurface`. KRMA-962.
- **GPU allocation:** a new processing texture per render
  ([`RenderEngineResources.swift:320`](../Sources/KromoraKit/Models/RenderEngineResources.swift));
  pool or reuse by size/format. KRMA-963 (`ready`).
- **Virtual copies duplicate the entire original** — a product decision about storage cost versus a
  true reference-sharing copy. KRMA-964.
- **Doc drift:** `CLAUDE.md` says `CIImage` is not `Sendable`, but the engine returns `CIImage` from
  detached tasks. KRMA-965 (`ready`).

---

## Already solid

- Swift 6 language mode with strict concurrency, zero diagnostics, and an enforced no-opt-out
  policy (apart from the lock noted above).
- Journaled package transactions with crash recovery, writer leases, and verified backup/restore
  primitives.
- Ordered, generation-fenced shutdown and cancellation across coordinators.
- One render pipeline shared by preview and export, bounded caches, memory-pressure eviction, and a
  separate export engine instance so export does not block interactive preview.
- A large deterministic test suite (~2,300 tests across lanes) with structural architecture guards.
