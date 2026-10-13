# Kromora Release Readiness Review — 2026-10-13

> **Dated review, not a roadmap.** Findings reflect `main` at `ccc575c2` (KRMA-920) on 2026-10-13.
> Current product intent remains in [`PRODUCT_SCOPE.md`](../docs/PRODUCT_SCOPE.md); items below
> become work only when accepted into DispatchGraph issues.

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

`AppViewModel` is an `ObservableObject` with 41 `@Published` properties plus synchronous
`objectWillChange` forwarding from seven child objects
([`AppViewModel.swift:1393`](../Sources/KromoraKit/ViewModels/AppViewModel.swift)). About 20 views
hold it via `@ObservedObject` (inspectors, status bar, culling bar, grid rows, masking workspace).
Each slider tick publishes `document` and re-evaluates all of them. Migrating the root to
`@Observable` gives per-property tracking and is the largest available SwiftUI performance win.
The file is 5,111 lines (6,511 with extensions) against a 5,120-line guard.

### S2. sRGB-only preview pipeline

`WorkingSpace.current = .sRGB`
([`WorkingSpace.swift`](../Sources/KromoraKit/Models/WorkingSpace.swift)), so the canvas is
clipped to sRGB on P3 displays, while export offers Display P3. A P3 export cannot be previewed
accurately. Moving preview to Display P3 (or extended linear with `rgba16Float` and EDR) matches
Photos.app on current hardware. The `RecipeExtractor` sRGB pin documented in `WorkingSpace` is the
prerequisite.

### S3. Export peak memory

`RenderEngine.encode` renders a full `CGImage`, then encodes into an `NSMutableData`
([`RenderEngine.swift:1201`](../Sources/KromoraKit/Models/RenderEngine.swift)), then
`ExportCoordinator.write` writes that `Data` with `.atomic` (a second temp file). A 60 MP 16-bit TIFF
peaks around 850 MB+; 100 MP sources exceed 1.4 GB. Encode straight to a staging file with
`CGImageDestinationCreateWithURL`.

### S4. Launch does blocking work before the first window

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

`applicationShouldTerminate`
([`KromoraAppDelegate.swift:43`](../Sources/KromoraKit/Presentation/KromoraAppDelegate.swift)) only
flushes edits; an in-flight batch export or import is cancelled during `shutdown()` without
confirmation.

### S6. App-modal panels and alerts presented from view models

Thirteen `runModal()` calls (`NSSavePanel`, `NSOpenPanel`, `NSAlert`) across `ExportCoordinator`,
`ExportWorkflowCoordinator`, `LookSaveCoordinator`, `DeriveCoordinator`, `AppViewModel`,
`AppKitFileDialogAdapter`, and the app delegate. Mac convention is window-attached sheets
(`beginSheetModal(for:)` or SwiftUI `fileExporter`/`fileImporter`/`alert`), and presentation belongs
in the view layer.

### S7. Share exports full-resolution 16-bit TIFF

[`ExportWorkflowCoordinator.swift:295`](../Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift)
renders `.tiff` at full size before showing `NSSharingServicePicker`, anchored to the key window's
content view rather than the Share control. Sharing to Messages/AirDrop/Mail should use HEIC or JPEG
at a sensible size, and the picker should appear immediately (deferred file promise) from the
button.

### S8. `ImageSource.init` performs file I/O and can hash a whole file

`ImageSource.init` stats the file (`PhotoSourceFingerprint.file(at:)`, including a sample digest) and,
on the fallback path, reads and SHA-256s the entire original on whatever thread constructs it
([`ImageSource.swift:228`](../Sources/KromoraKit/Models/ImageSource.swift)). This already regressed
once onto the main actor (KRMA-860). Make the initializer pure and move identity resolution to an
explicit asynchronous, off-main step; stream hashing instead of `Data(contentsOf:)`.

### S9. Library grid and Edit entry latency

- Grid: user-visible "Showing X of Y — scroll for more" paging; scroll position tracked through a
  `GeometryReader` preference that re-runs the grid body every 24 pt; rows identified by index
  (`ForEach(0..<rowCount, id: \.self)`). Warm re-entry p95 ≈ 150 ms (TESTING.md, 2026-10-11).
- Edit: warm first pixel p95 ≈ 190 ms with an exact stored frame and zero renders — SwiftUI mount
  cost. The 50/100 ms budgets were closed as won't-do (KRMA-748/749/750); for the "instant" bar they
  are worth reopening.

Consider `onScrollGeometryChange`/`scrollPosition`, stable item identity, and a continuous virtualized
grid whose scroller reflects the full library.

### S10. Per-render JSON + SHA-256 hashing of the edit document

`RenderCacheHash.digest(_:)` JSON-encodes with sorted keys and SHA-256s
([`RenderCacheKey.swift:157`](../Sources/KromoraKit/Models/RenderCacheKey.swift)); a single render
request hashes the document, mask recipes, and RAW develop several times
([`RenderEngine.swift:214`](../Sources/KromoraKit/Models/RenderEngine.swift), `:2224`, `:2290`,
`:2787`). With brush masks this is several milliseconds per slider tick on the render actor. Use
structural `Hashable` keys or revision counters; hex encoding via `String(format:)` per byte
appears at 21 sites.

### S11. Menu and shortcut conventions

- Delete Selected Photos uses bare Delete; Photos uses ⌘⌫ for destructive removal.
- ⌘S runs Export; ⌘D runs Derive Look.
- Titles mix `...` and `…`.
- "Open Source Folder…" is an import, and "Refresh Library" (⌘R) is a leftover concept for a
  package library.

---

## Nice to have

- **`Task.detached { … }.value`** appears ~39 times; it drops cancellation and priority inheritance.
  Swift 6.2 `@concurrent` nonisolated functions are the modern idiom.
- **Concurrency escape hatch:** `OSAllocatedUnfairLock(uncheckedState:)` / `withLockUnchecked` in
  [`Thumbnails.swift:209`](../Sources/KromoraKit/Models/Thumbnails.swift) is not caught by
  `PackageSettingsTests`; with `CGImage` now `Sendable` it may be unnecessary.
- **Localization:** no String Catalog; user-facing strings are composed in view models with manual
  plurals.
- **Menu plumbing:** File-menu commands use `NotificationCenter`; `FocusedValue` gives enablement
  for free.
- **Logging:** photo-switch logs at `.notice` are persisted in release; subsystem `com.kromora.app`
  does not match bundle ID `com.last8.kromora.photo` (KRMA-892); `print()` remains at
  [`LUTLibrary.swift:283`](../Sources/KromoraKit/Models/LUTLibrary.swift) and `:580`; detail strings
  are built eagerly outside `os_log` interpolation.
- **Code cleanups:** `try!` in
  [`PortableLibraryPackage.swift:641-655`](../Sources/KromoraKit/Models/PortableLibraryPackage.swift)
  (safe today, not idiomatic); dead `#if os(macOS)` branch in `fullSync`; test-only
  `waitUntilCompleted` seam in production `PreviewSurface`.
- **GPU allocation:** a new processing texture per render
  ([`RenderEngineResources.swift:320`](../Sources/KromoraKit/Models/RenderEngineResources.swift));
  pool or reuse by size/format.
- **Virtual copies duplicate the entire original** — a product decision about storage cost versus a
  true reference-sharing copy.
- **Doc drift:** `CLAUDE.md` says `CIImage` is not `Sendable`, but the engine returns `CIImage` from
  detached tasks.

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
