# Testing and profiling

This document is authoritative for the release bar, verification commands, and lane requirements.

## Release bar

The app is ready to release when the ordinary Library → Edit → Export loop is dependable and these
properties hold:

- Imports and exports report partial failures honestly, preserve the user's source files, and leave
  recoverable package state after interrupted operations.
- Edits survive navigation, relaunch, undo/redo, and a quit-and-copy of the package. A corrupt or
  unsupported edit is reported instead of silently replaced with a blank edit.
- Preview and full-resolution export use one ordered rendering pipeline; supported crop, masks,
  Looks, and retouch recipes stay aligned across both.
- Library membership and canonical data live in the package. Indexes, previews, thumbnails, masks,
  and analysis caches are disposable and can be rebuilt.
- The `fast` and `serial` lanes below pass on the supported toolchain. Hardware and licensed-camera
  checks (the `optional` lane) are reported separately when their environment is unavailable; skipped
  work is not described as a pass.
- Distribution follows the signed-app and entitlement process in [`PACKAGING.md`](PACKAGING.md).

Performance numbers in the dated diagnostics below are evidence for their recorded machines and
methods, not universal release claims.

The required checks are deterministic build/test lanes. Hardware, AppKit, RAW, and Instruments
work is opt-in because it needs a logged-in display or licensed local fixtures.

The `xcode-app` CI job runs `scripts/app-store-build.sh` in verify mode to build the Release app
through the Xcode project and verify the resulting app bundle, catching project-reference, asset,
entitlement, Info.plist, and SwiftPM-versus-Xcode issues. It runs on pushes to `main` and manual
workflow dispatches, not on pull requests.

## Photos permission verification

Use the packaged `Kromora` Xcode scheme to verify PhotoKit-backed Photos thumbnails and filenames.
`swift run` launches the SwiftPM executable without the app bundle's `NSPhotoLibraryUsageDescription`
and sandbox configuration, so its PhotosPicker transfer behavior does not verify the shipping app's
PhotoKit authorization path. In the packaged app, grant Photos access when prompted; test denied access
and Limited access through the tile's failure tooltip and retry behavior.

## Required lanes

```sh
scripts/ci-tests.sh warning-gate
swift build
swift test
swift build -c release
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
scripts/ci-tests.sh identity
git diff --check
dg validate
```

`warning-gate` runs `swift build --build-tests -Xswiftc -warnings-as-errors` over both `KromoraKit`
and `KromoraKitTests`, then scans the build output for Swift source diagnostics
(`path:line:col: warning:`). Both halves are needed: on Xcode 27 / Swift 6.4,
`-warnings-as-errors` promotes ordinary warnings but not diagnostics the compiler downgrades from
errors (the XCTest lifecycle actor-isolation warnings in `PhotosReviewTransferCacheTests` built and
exited 0). The scan matches only compiler source locations, so linker, SDK, and packaging notes
(such as the AppIntents metadata note) cannot trip it, and it runs only after a zero exit, so it can
never mask a failing build. All output stays visible. Because the compiler only reports on files it
recompiles, CI's clean checkout is the authoritative run; a warm local build may skip unchanged files.

`scripts/ci-tests.sh warning-gate-selftest` (also a CI step, and run by `PackageSettingsTests`)
proves the gate with disposable stub builders: clean passes, source and test warnings fail, an
ordinary compiler failure fails, and a non-Swift linker warning passes. Do not add warning
suppressions or Swift 6 opt-outs to make the gate pass.

`fast` covers deterministic model, coordinator, and fake-engine tests in parallel. `serial` covers
Core Image, render, and AppKit/UI-sensitive tests. `scripts/ci-tests.sh optional` runs RAW-fixture,
benchmark, and packaging checks when their inputs are available. Procedural fixtures are created by
the tests and are not committed; the photo-intelligence resource exception is documented below.

`PresentationBudgetTests` is part of `serial`. It uses generated package fixtures and two distinct
`AppViewModel` lifetimes for the exact-frame relaunch cases; the cold canonical-write case uses the
real renderer. When the suite had ten tests it took 6.3 seconds to execute on an Apple M4 Pro running macOS 27.2
(targeted serialized run, excluding build time); it has since grown to 17 and has not been re-timed.

Keyboard routing is tested at three levels (KRMA-920): `KeyboardCommandRouterTests` covers the
dispatch table and focus ownership without AppKit, `KeyboardShortcutCatalogTests` keeps the menu
bar, reference sheet and key surface in agreement (and fails if an `NSEvent` monitor returns), and
`KeyboardInventoryMatrixTests` (every inventory key × canvas, workspace picker, popup, button, list,
text field, slider, stepper × with/without a photo), `KeyboardSurfaceWindowTests`,
`FocusedSceneValueTests` and `KeyRoutingProbeTests` synthesize key events into a real `NSWindow` and
assert none reach `NSWindow.noResponder(for:)`, the call that plays the system alert (text fields
and slider/stepper arrows are deliberately left to the control). All three
need no unlocked display and run in the serial lane. Silence of the sound itself is a by-ear check.

The photo-intelligence corpus has two intentionally separate checks. The fast
`PhotoIntelligenceDecisionLogicTests` suite uses deterministic fakes to test scene/Auto decision
logic. The serial `PhotoIntelligenceRealCorpusTests` suite writes deterministic procedural PNGs to
a temporary directory, opens them as file-backed sources, and measures them through the production
`RenderEngine` and Vision mask provider. It writes a disposable stats manifest beside the report;
the test fails when a declared procedural target band drifts. Run the visual review with:

```sh
scripts/photo-intelligence-report.sh
```

The report is gitignored and contains real original/Auto-rendered pixels, a computed 4× pixel
difference, and the returned subject mask when Vision provides one. AI-generated photo-intelligence
fixtures (KRMA-459 Part C) may be committed under the tests target resources within a ≤ 5 MB budget,
with a provenance manifest recording generator, model, date, and prompt. Procedural tone fixtures
remain generated at test time. Local camera RAWs in the gitignored `realworldtest/` folder are used
only by the opt-in RAW lane.

The Auto pixel evaluator, report value, artifact writer, and Vision-aesthetics probe are test-target
support code under `Tests/KromoraKitTests/Support`. `KromoraKit` keeps only the small
`AutoCandidateEvaluation` document/geometry transform needed by runtime measurement; a package
settings test guards this shipping boundary.

The standing identity regression gate is IdentityRegressionGateTests. It generates a disposable
1,000-asset library and verifies full-library relocation, duplicate/collision handling, render and
thumbnail mask supersession, preview publication supersession, and direct edit-store recovery. It
is included in serial and can also be run directly with scripts/ci-tests.sh identity.

`LaunchHintsTests` covers schema and ID bounds, atomic persistence, library scoping, unsupported
versions, and corrupt records. `LibraryBrowsingCoordinatorTests` verifies that actual viewport IDs
are persisted without restoring selection from the hint.

The pre-package folder-backed library baseline is documented in
[`LIBRARY_PACKAGE_BASELINE.md`](LIBRARY_PACKAGE_BASELINE.md). Its opt-in harness runs in the
optional lane with `KROMORA_LIBRARY_BASELINE_BENCHMARK=1` and emits the stable JSON report shape
described there.

## Library grid with a large cold import (KRMA-841)

`LargeImportLibraryGridBenchmark` is the window-independent, opt-in harness (no `NSWindow`, so it
measures model, scheduler and decode cost, not SwiftUI layout). It copies the `realworldtest/` RAW
files N times with unique trailing bytes (identity and the memory cache are content-keyed, so links
or plain copies would share one decode), drives a real `ImageCollection` with the real scheduler and
ImageIO/RAW decode, requests the first 30-cell window, simulates a fast scroll (one 6-cell row every
16 ms, request entering and release leaving cells as `LibraryGridView` does), then runs select-all and
a shift-click while decodes are in flight. A main-actor heartbeat (4 ms sleep) measures stalls.

```sh
KROMORA_LARGE_IMPORT_BENCHMARK=1 KROMORA_LARGE_IMPORT_COUNT=1500 \
KROMORA_LARGE_IMPORT_OUTPUT=/tmp/krma841.txt \
swift test -c release --filter LargeImportLibraryGridBenchmark
```

Measured state, Release, Apple M4 Pro, macOS 27.2, 8 local fixtures (two 126-129 MB ARW, six
3-17 MB DNG/HEIC) cycled to N cold files, on top of commit `3cba3952` plus the KRMA-841 index cache:

| Files | Fill first 30 cells | Heartbeat gap p50 / p99 / max | Gaps > 33 ms | Select-all | Shift-click | Peak RSS |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 300 | 396 ms | 4.8 / 6.0 / 17.8 ms | 0 of 512 | 0.14-0.42 ms | 0.16 ms | 1812 MB |
| 1500 | 2006 ms | 5.0 / 6.7 / 18.2 ms | 0 of 1291 | 0.57-1.10 ms | 0.76 ms | 1928 MB |

Counterpoint verification reran the 1,500-file Release case twice on 2026-10-11 after the
visible-window lookup was changed to use the collection's cached item index. The two runs filled
the first 30 cells in 2430 ms and 2052 ms. Heartbeat p50/p95/p99/max was 4.9 / 5.1 / 5.8 / 54.7
ms with 1 of 1451 gaps above 33 ms in the first run, then 4.8 / 5.1 / 5.5 / 19.6 ms with 0 of
1383 gaps above 33 ms in the second. Select-all samples were 1.41, 0.62, 0.97, 0.75, 0.54 ms
and 1.23, 0.60, 0.53, 0.62, 0.65 ms; shift-click was 0.66 and 0.85 ms; peak RSS was 1881 and
1991 MB. The single 54.7 ms model-heartbeat outlier did not reproduce. These runs still do not
mount SwiftUI or measure frame presentation; the owner waived that profile criterion on 2026-10-11
after reporting acceptable in-use behavior.

Root causes from the measurements:

- Rejected: main-actor starvation. During sustained cold RAW decode the heartbeat never exceeded
  18 ms (about 13 ms over its 4-5 ms cadence) and never missed a 33 ms frame. Selection costs
  about 1 ms at 1500 items. Decode concurrency is bounded (4 running / 24 queued) and
  `releaseThumbnail` cancels queued decodes when a cell leaves the viewport
  (`testLargeColdLibraryBoundsDecodeWorkAndReleaseCancelsQueuedDecodes`).
- Fixed earlier (92a5ea8f): per-arrival `items.firstIndex(where:)` scans and whole-library
  filtering/sorting in `fillThumbnailQueue`. These were quadratic on the main actor; the numbers
  above are with the `itemIndex(for:)` cache in place. Pre-change baseline (same harness and
  fixtures on `92a5ea8f~1`, Release, M4 Pro): 300 files fill 1042 ms, heartbeat p50/p99/max
  5.0 / 5.4 / 18.0 ms, 0 of 428 gaps > 33 ms, select-all 0.28-0.47 ms, shift-click 0.34 ms, peak
  RSS 1894 MB; 1500 files fill 1953 ms, heartbeat 5.0 / 6.1 / 15.8 ms, 0 of 1337 gaps > 33 ms,
  select-all 1.41-1.83 ms, shift-click 1.70 ms, peak RSS 1936 MB. The scans cost roughly 1 ms per
  selection operation at 1500 items (select-all and shift-click about 2x slower than after the
  fix) and did not produce frame-length stalls at the model level, so they were a real but small
  contributor; fill time and peak memory are unchanged within fixture-order noise.
- Fixed in counterpoint verification: `requestVisibleThumbnails` rebuilt an ID-to-index dictionary
  by scanning all loaded items on every viewport update. It now resolves only the requested
  visible IDs through `itemIndex(for:)`, reusing the cached index and keeping repeated admission
  work proportional to the viewport.
- Remaining cost is decode time and transient memory, not UI-thread work. Filling a 30-cell window
  of cold RAWs takes 0.4-2.0 s depending on which fixtures lead, and four concurrent full decodes
  push peak RSS to about 1.9 GB (resident 1.3-1.5 GB afterwards). `PlatformThumbnailProvider`
  creates thumbnails with `kCGImageSourceCreateThumbnailFromImageAlways`, which decodes the full
  RAW instead of the embedded preview. Moving to an embedded-preview tier changes thumbnail pixels
  and frame-store signatures, so it is a separate quality decision, not part of this change.
- Not measured here: SwiftUI body/layout cost per frame in a mounted `LibraryGridView`. That needs a
  supervised Instruments session (Instruments could not record on this machine, see KRMA-860's
  note above). The model-level result suggests it is not main-actor decode or scheduling work.
- Still open and worth measuring with a mounted grid: the grid body reads selection at grid and row
  level, so a selection change re-evaluates hosted rows; `applyThumbnail` re-signals edited demand
  for every visible id on each arrival.

## Optional RAW and performance work

Use local RAW fixtures in `realworldtest/` by default, or set `KROMORA_RAW_FIXTURE_DIR` to another
fixture directory. The real drawable benchmark requires a logged-in display:

```sh
KROMORA_METAL_BENCHMARK=1 \
swift test -c release --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark

KROMORA_TRACE_BENCHMARK=1 \
swift test --filter TracingOverheadBenchmark/testMeasureTracingOverhead

KROMORA_PHOTOS_BENCHMARK=1 \
KROMORA_PHOTOS_RAW=/absolute/path/to/representative.dng \
swift test --filter PhotosImportPerformanceTests
```

Share Copy peak memory (KRMA-1048) is measured through the real engine and pasteboard path, one process
per selection size:

```sh
KROMORA_SHARE_COPY_MEMORY=1 KROMORA_SHARE_COPY_COUNT=32 \
swift test --filter ShareCopyMemoryTests/testMeasurePeakFootprintForMultiPhotoCopy
```

Measured 2026-10-19 on an Apple Silicon host, debug build, using a private local RAW/DNG fixture set at
the 4096-pixel JPEG share size. Fixture names and source metadata are omitted. `phys_footprint` peak:

| Photos | Peak footprint | Result |
| ---: | ---: | --- |
| 1 | 3,720.75 MiB | copied |
| 8 | 3,889.35 MiB | copied |
| 24 | 4,373.02 MiB | copied |
| 32 | 4,635.14 MiB | copied |
| 48 | 4,437.30 MiB | rejected, clipboard untouched |

The peak is set by one RAW render's Core Image intermediates and does not grow with the selection;
retained encoded JPEGs add at most the 256 MiB cap, and the pasteboard server's copy is the same size
again outside the app. The cap therefore
bounds the part that scales with selection size and is kept. The production cap is also exercised
deterministically by `ShareCopyMemoryTests`.

For a reproducible `xctrace` run, use the supported wrapper with an explicit mode:

```sh
KROMORA_RAW_FIXTURE_DIR=/absolute/path/to/fixtures \
scripts/run-kromora-capture.sh --benchmark metal-presentation \
  --source /absolute/path/to/fixtures/DSC07826.ARW

scripts/run-kromora-capture.sh --benchmark concurrent-export-editing \
  --source /absolute/path/to/fixtures/DSC07826.ARW

scripts/run-kromora-capture.sh --benchmark last-known-frame \
  --source /absolute/path/to/fixtures/DSC01019.ARW --iterations 30
```

`last-known-frame` mounts the shipping `ContentView` in an onscreen window, imports 29 generated grid
sources plus the selected licensed RAW (a 30-cell grid) into a temporary test package, and warms the
actual visible thumbnail rows before its warm grid samples. Every warm grid sample leaves Edit,
waits for `LibraryGridView` to unmount, re-enters Library, waits for a new grid mount and populated
visible cells, then forces one AppKit layout and display pass; the sample is the time from the
navigation request to that pass. Every warm Edit sample does the reverse and selects the RAW again
through `AppViewModel`, so the Edit surface remounts. First-pixel and confirmed latencies come from
the presentation session's own drawable-callback clock (which starts at the top of
`selectCollectionImage`), re-based to a timestamp taken before the call; no sleep or polling
interval is inside a reported number. Each wait requires a session created after that timestamp,
so a confirmation left over from the previous selection cannot satisfy it. The synchronous
selection call is the measured main-actor work before its first asynchronous task can run. Exact
and stale cases assert their frame and render-count requirements. Renderer admissions and
crossfade counts come from the production owners, and the harness never infers a presentation from
a published `CIImage`.

Each output line is JSON prefixed with `LAST_KNOWN_FRAME_BENCHMARK`, and the wrapper also writes
the same records to `<capture>-report.jsonl` so a consumer need not parse them out of interleaved
xctest output. Records carry machine, OS, commit, source format/dimensions, viewport points,
backing pixels, cold/warm and cache state, sample count, p50/p95 (nearest-rank), confirmed-frame
p95, provisional/confirmed frame counts, render admissions, crossfades, thumbnail swaps, grid
mounts, SwiftUI body evaluations, p95 main-actor time before first suspension, and
`criteriaPassed`. A final `LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=… stale=… grid=… edit=…` line gives
the four verdicts. The default is 30 warm samples (5...100) so p95 does not collapse to the
maximum. `KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1` turns a wall-clock miss into a test failure;
without it the test fails only for harness errors and the structural exact/stale criteria, so a
green run is **not** evidence that the budgets pass. Check the summary line. Keep the benchmark
opt-in; KRMA-734 targets are unchanged.

Requirements and behavior of the capture host:

- The display must be unlocked and awake (`caffeinate -d` for a long session). xctest is a
  background process that only spins the run loop, and AppKit delivers activation and window-state
  events through its own event queue, so the harness calls `finishLaunching()` and drains that
  queue (`settle`) at every wait. Without both, the app never activates and its window stays
  occluded (`occlusionState=8192`, `appActive=false`) however often `activate` or `orderFront` is
  called. If the window is still not onscreen after five seconds the test skips with the occlusion
  state; it also skips, rather than failing, if the window is occluded mid-run (locked or asleep
  display, another window covering it).
- Metal reports `presentedTime == 0` for a drawable the compositor skipped, and `PreviewSurface`
  then withholds confirmation and stops retrying after a bounded number of skips. That is correct
  for an occluded product window but strands the session at `provisional` in a capture. The harness
  sets `zeroPresentedTimeFallback` (as `ConcurrentExportEditingBenchmark` does) and reports how
  often it was used as `zeroPresentedTimeFallbacks`; one or two per run is normal. Latencies are
  therefore handler time, not scan-out time, and are diagnostic in the same sense as
  `metal-presentation`.
- Run one capture at a time. Concurrent runs share `.build`, the capture directory, and window
  activation, and one will be occluded or rebuilt under the other.

Record hardware, OS, commit, source format/dimensions, viewport/backing pixels, decoder, and
cold/warm state. Points of Interest under `com.kromora.app` / `workflow` distinguish input, render,
GPU completion, and actual drawable presentation.
Mask editing adds `MaskOverlayResolve`, `MaskSemanticResolve` and `MaskSemanticApply` intervals plus
`MaskResolutionState` (loading/ready/unavailable/cancelled) and `MaskResolveTiming` events (lookup,
resize and apply milliseconds with source/target sizes). To triage a stuck "Analyzing mask…", stream
them with `log stream --predicate 'subsystem == "com.kromora.app"' --level debug`: a `loading` with no
following `ready`/`unavailable`/`cancelled` is a hung or torn-down task; large `resizeMs`/`applyMs`
points at the CPU passes. The mask, thumbnail and photo-switch mirrors log at `.debug`, so they are
not persisted in release and appear only with `--level debug`; their detail strings are built lazily,
only while a log or signpost stream is attached. Fake-renderer timings are orchestration checks,
not product latency claims.

## Manual UI checks

When changing inspectors, masking, appearance, or packaging, exercise the packaged app in a real
macOS UI session. Check light/dark appearance, Settings transitions, keyboard/focus/VoiceOver
behavior, inspector disclosure state, mask overlay and export parity, and icon/signature outputs.
The app-level smoke test and the verification scripts under `scripts/` are the executable checks;
the source and test names are the authoritative coverage map.

### Live checks on a disposable library

`scripts/disposable-app.sh start <package.kromoralibrary>` builds the development launcher, wraps it
in an ad hoc signed bundle with its own bundle id (`com.kromora.disposable`) and preferences, and
launches it on an APFS clone of the package through `KROMORA_LIBRARY_PACKAGE`. The variable replaces
the stored library choice and the default for that launch only and writes nothing to preferences.
`stop` quits the app and deletes the clone and its preferences. This is the unsandboxed development
launcher, so it is not evidence about the sandboxed App Store build: use it to exercise UI and
export behavior, and use `scripts/app-store-build.sh` and the packaged-app smoke for the signed app.
KRMA-1086 used this setup to show that the unsandboxed launcher and the signed app export identical
pixels.

### Packaged-app UI smoke

`scripts/smoke-macos-app.sh [Kromora.app]` (default `.build/xcode/Build/Products/Release/Kromora.app`,
built by `scripts/app-store-build.sh`) drives the packaged app through System Events: launch, first-run
welcome dismissal when needed, Open Image import of a generated `000-Kromora-Smoke.png` (256 x 256),
Settings, File menu readiness
(File > Export… enabled), then the one-photo export workflow: the "Export 1 Photo" setup sheet
(selected settings kept; the script reads the sheet's "Example filename" text, Continue), the folder chooser (a throwaway folder entered with Go to Folder,
Export Here). It passes only when the file named by that example (the persisted prefix, suffix, and Append Look
choice, so `000-Kromora-Smoke.jpg` under default naming) exists in that folder as a decodable 256 x 256
JPEG (checked with `sips`). On a fresh profile it locates the empty-library welcome action by its stable
accessibility identifier and waits for the sheet to close before opening the import panel. Native
file-dialog stages wait for their actionable controls, including the Go to Folder path field.
The script never rewrites preferences; a profile whose remembered format is not JPEG fails the format
check.

The app imports into its own current library, so run it only in a disposable macOS profile or VM and set
`KROMORA_SMOKE_DISPOSABLE_PROFILE=1` to confirm. CI sets it for the ephemeral hosted runner. Do not run it
against a real photo library. The script quits only the instance it launched (matched by pid and
executable path), removes only its own temporary fixtures, and bounds every wait; a failure names the stage.

| Exit | Meaning |
| --- | --- |
| 0 | Executed and passed |
| 1 | Failed; stderr names the failed stage |
| 2 | Deferred: no accessible UI session, automation refused, or the running terminal/app lacks Accessibility access. Not a pass; CI logs a warning |
| 3 | Refused: disposable-profile confirmation missing |

To run the harness without touching any real library, point it at the development bundle from
`scripts/disposable-app.sh` and pass the clone through `KROMORA_LIBRARY_PACKAGE`, which the script
forwards to the launched app. The packaged, sandboxed app ignores that variable, and its container
holds the real profile, so the signed app's smoke needs a genuinely disposable profile or VM.

```bash
scripts/disposable-app.sh start "<package.kromoralibrary>"   # builds the bundle and clones; launches the app
osascript -e 'tell application id "com.kromora.disposable" to quit'   # keep the clone and preferences
KROMORA_SMOKE_DISPOSABLE_PROFILE=1 \
  KROMORA_LIBRARY_PACKAGE="$PWD/.build/disposable-app/Library.kromoralibrary" \
  scripts/smoke-macos-app.sh .build/disposable-app/KromoraDisposable.app
scripts/disposable-app.sh stop
```

KRMA-1067 ran both passes this way on macOS 27: default naming exported `000-Kromora-Smoke.jpg` and
seeded `pre-`/`-sfx` naming exported `pre-000-Kromora-Smoke-sfx.jpg`, each a 256 x 256 JPEG. The
running terminal or app (for Claude Code, its separate `claude.app`) needs Accessibility access.

For the persisted-naming run, seed the disposable domain before the second run, for example
`defaults write com.kromora.disposable export.batchFilenamePolicy -data "$(printf '{"appendsLook":true,"prefix":"pre-","suffix":"-sfx"}' | xxd -p | tr -d '\n')"`.

Manual sandbox acceptance remains in `docs/APP_STORE_ACCEPTANCE.md` (KRMA-1058).

## Last-known-frame qualification matrix

The deterministic frame qualification is split across model, store, coordinator, package, and UI
boundary suites so injected failures stay reproducible and do not depend on a screenshot:

| Scenario | Deterministic coverage |
| --- | --- |
| Freshness rows, unresolved Looks, source replacement, color-space mismatch, and pixel-epoch changes | `PresentationFrameClassifierTests`, `LookSignatureTests` |
| Truncated/overflow/corrupt preview envelopes, unsupported storage format, per-entry isolation, LRU cap and pinning | `PresentationFrameEnvelopeTests`, `LatestPreviewFrameStoreTests` |
| Canonical frame reaches a fresh store within the two-second settle-to-disk bound; interrupted atomic replacement preserves the prior complete frame | `LatestPreviewFrameStoreTests` |
| Exact/stale/missing stored frames, candidate ordering, renderer failure, and obsolete generations | `WarmReopenPresentationTests`, `PreviewPresentationCoordinatorTests`, `EmbeddedFirstFrameTests`, `PreviewCutoverTests` |
| Idle warming fills all three frame tiers in viewport/LaunchHints order, uses one background editor admission per photo, skips exact source reads, pauses for system conditions, fences cancellation, protects pinned frames at the preview low-water threshold, and survives a package relaunch | `IdleFrameWarmerCoordinatorTests`, `RelaunchParityTests.testIdleWarmFramesRemainExactAcrossPackageRelaunch` |
| Same-ID Look replacement and unchanged Look scans | `LUTLibraryTests`, `AppViewModelTests`, `EditedThumbnailCoordinatorTests` |
| Transactional edit plus presented geometry and rollback | `PortableLibraryPackageTests.testEditRevisionAndPresentedGeometryPublishOrRollbackTogether` |
| Packed-frame stable keys, read-window bounds, compaction, write interruptions, and retry | `ThumbnailFrameStoreTests`, `PortablePackageMaintenanceTests` |
| Launch-hint schema faults, wrong library, removed IDs, viewport supersession, and stale completion | `LaunchHintsTests`, `LibraryBrowsingCoordinatorTests` |
| Rapid selection, newest-pending work, stale render/thumbnail publication, and actual drawable callbacks | `FilmstripNavigationTests`, `ThumbnailSwitchLifecycleTests`, `IdentityRegressionGateTests`, `PreviewSurfaceTests` |

Persisted presentation frame reads are recorded by `FrameLookupLedger` with their surface, outcome,
and monotonic timestamp; the ledger stores no paths or image data. The one-line `FrameLookupSummary`
signpost groups outcomes by surface and names the most frequent rejection reason for quick cache-miss triage.

Run this matrix with `swift test`, then `scripts/ci-tests.sh fast`, `serial`, and `identity`. These
assertions establish correctness and bounded work; fake renderer timings remain orchestration data
and do not count toward the release latency budgets.

### Canonical preview write bound

`LatestPreviewFrameStore` writes canonical preview envelopes at user-initiated task priority. The
named `maxSettleToDiskDelay` is two seconds from the first queued frame; newer frames for the same
asset coalesce into that pending write without moving its deadline. The store test polls fresh store
instances until the frame is readable and never calls `flush()` or `shutdown()`. Its interruption
test damages the staged bytes immediately before atomic replacement and verifies that the prior
complete envelope remains readable. Existing replacement coverage verifies that a successful
write exposes the new complete frame.

### Idle package frame warming

`IdleFrameWarmerCoordinatorTests` uses a deterministic renderer and a real package fixture to
verify original thumbnails, edited thumbnails, and canonical previews. It checks viewport distance
before LaunchHints recency, background editor admission one photo at a time, metadata-only exact
hits, pause gates for Low Power Mode/serious thermal/inactive app state, unresolved Look blocking,
late-result cancellation, and preservation of an existing pinned preview at the low-water mark.
`RelaunchParityTests.testIdleWarmFramesRemainExactAcrossPackageRelaunch` fills the stores through
the warmer, closes the package, then reopens an `AppViewModel` and verifies the grid and editor use
those pixels without a source decode or render.

### Packed thumbnail write batching

`ThumbnailFrameStore` batches settled thumbnail frames and rewrites `index.json` once per append
batch. It flushes after 250 ms of quiet, at 32 pending records, on an explicit flush, or when the
batch reaches its named two-second maximum pending age from the first queued write. The two-second
age deadline does not move as new records arrive; with successful cache writes, this is the maximum
in-memory loss window during a sustained write burst. Count-triggered flushes can publish a batch
earlier and are accounted for separately in the rewrite bound. `ThumbnailFrameStoreTests` drives the
timers with a manual clock, verifies a continuously active batch is readable from a fresh store after
its age deadline, bounds index rewrites for a 200-write burst, and checks a failed append preserves
the previous index and can recover on retry.

### KRMA-734 release qualification attempt (2026-09-30)

The required warning gate, debug and Release app builds, full test suite, fast lane, serial lane, and
identity lane passed. `scripts/ci-tests.sh optional` was also run with the local `IMG_0371.DNG`
(8064×6048). It reported two failing test methods with three failed assertions: `ImageLoadingTests.testLoadingARAWGoesThroughCIRAWFilter`
could not prepare that DNG through `RenderEngine`; `RAWCapabilitiesTests.testEveryPerImageSeedLandsStrictlyInsideItsSliderRange`
found the decoder's Sharpness and Local Tone Map seeds at the slider maximum. The remaining 32
optional methods skipped because their separate benchmark switches or matching RAW/JPEG pair were
not available.

The Release drawable capture was attempted on an Apple M4 Pro Mac mini (12 CPU cores, 48 GB RAM),
macOS 27.2 build 26B5091g, source commit `986e73b41e0be9e87a31522c91ef715183c3dcf6`, with the same
DNG and a 1280×800 drawable target, 30 requested samples. The Release app build passed, but the
Release XCTest bundle did not link with the installed Xcode 27.0 beta (build 27A5252f): its SDK
reported unresolved SwiftUI opaque descriptors and an unavailable `CoreAudioTypes` framework.
The capture process never launched, so it produced no latency samples or drawable/frame counts.
This attempt is not release-budget evidence. The warm Edit, 30-cell hydration, crossfade/swap, and
layout budgets remain unmeasured until the Release capture can run with a supported test toolchain.

### KRMA-734 stable-toolchain re-verification (2026-09-30)

Re-run on an Apple M1 Pro MacBook Pro (10 cores, 16 GB), macOS 27.0 build 26A428, stable Xcode 27.0
(build 27A266a, macOS 27.0 SDK), commit `0c567dfec94c61d457d3f91e3999a6c7c13dd08f`. The warning
gate, debug and Release builds, fast lane, identity lane, `git diff --check`, and `dg validate` passed.
The serial lane failed in `MetalKernelParityTests.testGrainKeepsGoldenStatistics` and
`testMigratedKernelsRenderOnTheSoftwareRenderer`: the `grain-seed` golden's worst byte delta was 34
against the 32 tolerance (mean and standard deviation checks passed), so the golden is sensitive to
the OS build. Across the two observed systems, both Metal and software rendering produced a worst
byte delta of 34 on macOS 27.0 build 26A428 and 29 on macOS 27.2 build 26B5091g. These are alternate
valid noise patterns from implementation-defined single-precision `sin` range reduction, not a
change in grain character. The grain golden therefore checks mean and standard deviation within 3
levels, along with repeatability for the same seed and a changed result for a different seed; it
does not compare individual grain bytes across OS builds. The other migrated kernels retain their
pixel comparisons.

`scripts/run-kromora-capture.sh --benchmark metal-presentation --source realworldtest/DSC01019.ARW
--iterations 30` still failed before launching: the Release `KromoraKitTests.xctest` bundle fails to
link on stable Xcode 27.0 with the same unresolved SwiftUI opaque type descriptors (`View.tag(_:includeOptional:)`,
`View.task(name:priority:file:line:_:)`) and missing `CoreAudioTypes` framework. The failure is
therefore not specific to the beta SDK. No latency samples, drawable counts, or budget results exist.

### KRMA-738 stable Release capture retry (2026-09-30)

Retried on the selected stable Xcode 27.0 (build 27A266a, macOS 27.0 SDK), Apple M1 Pro MacBook Pro
(10 cores, 16 GB), macOS 27.0 build 26A428, commit `2bb86786e08925ac7506016a6ec6900aeb9ca7f5`,
using `DSC01019.ARW` and 30 requested iterations. The Release test sources compiled, but linking
`KromoraKitTests.xctest` failed with unresolved SwiftUI opaque type descriptors for
`View.tag(_:includeOptional:)` and `View.task(name:priority:file:line:_:)`, unavailable `CoreAudioTypes`,
and an SDK diagnostic that `SwiftUICore.tbd` cannot be linked by this client. The benchmark process
did not launch. The harness's configured drawable is 1280×800, but it was not created or measured;
latencies, frame counts, render admissions, transitions, and KRMA-734 budgets remain unmeasured.
Capture summary: `/tmp/kromora-capture/KRMA-738-stable-xcode-27-DSC01019-20260930-185223-summary.txt`.

### KRMA-738 stable Release capture (2026-09-30)

After KRMA-741 removed the eager `MaskingPanel.body` evaluation from the test bundle, the Release
`KromoraKitTests.xctest` links on stable Xcode 27.0 (build 27A266a). `scripts/run-kromora-capture.sh`
looked for a stale `KromoraPackageTests.xctest` name and aborted before tracing; it now uses
`KromoraKitTests.xctest`.

`scripts/run-kromora-capture.sh --benchmark metal-presentation --source realworldtest/DSC01019.ARW
--iterations 30` ran on an Apple M1 Pro MacBook Pro (10 cores, 16 GB), macOS 27.0 build 26A428,
commit `dd70dfb9d9fcacc90caf611078978ddd724e6d33`, Release configuration, `DSC01019.ARW` (ARW,
6336×9504 source extent) decoded through `CIRAWFilter`, 1280×800 drawable. Single automated run:
a 30-iteration warm transform phase after a 529 ms completed-texture warm-up, plus 5 settled
adjustment iterations; the Core Image/preview caches were warm for the measured phase.

| Metric | Value |
| --- | --- |
| Input to present p50 / p95 / p99 | 24.4 / 24.5 / 25.2 ms |
| Release to settled p50 / p95 / p99 | 41.0 / 49.5 / 49.5 ms |
| Warm presentation encoding p50 / p95 | 0.79 / 6.96 ms |
| Warm drawable acquisition p50 / p95 | 0.08 / 0.16 ms |
| Warm GPU p95 | 0.30 ms |
| Peak memory delta | 65.0 MB |

Trace: `/tmp/kromora-capture/KRMA-738-verify-DSC01019-20260930-201225.trace`.

This harness measures single-photo drawable presentation only. It does not emit confirmed and
provisional frame counts, render admissions, crossfades, thumbnail swaps, layout changes, main-actor
time before first suspension, or 30-cell grid hydration, and nothing else in the test target does.
These KRMA-734 budgets therefore remain unmeasured: warm Edit navigation p95 <= 50 ms with <= 2 ms
main-actor work before first suspension, exact warm Edit zero renders and one confirmed frame, stale
warm Edit one provisional plus at most one confirmed frame, and warm 30-cell hydration p95 <= 100 ms.
No target was redefined. (Superseded: the KRMA-744 capture below measures all four.)

### KRMA-742 last-known-frame Release capture (2026-09-30)

Ran `scripts/run-kromora-capture.sh --benchmark last-known-frame --source
realworldtest/DSC01019.ARW --iterations 5` on stable Xcode 27.0 (27A266a), macOS 27.0 build
26A428, Apple M1 Pro MacBook Pro (10 cores, 16 GB), Release configuration, commit
`29496b3df7cea4bc9e1d6b24074f15b5551ccb9d`. The source is ARW, metadata dimensions 9504×6336,
decoded with `CIRAWFilter`; viewport 1440×897 points and 2880×1794 backing pixels. Exact and stale
warm scenarios each ran once; the 30-cell grid and warm Edit selection ran five samples each.
The first grid hydration was 1095.0 ms. KRMA-744 later found that the warm grid loop did not wait
for the Library view to mount or yield to SwiftUI, and that Edit latency used a timestamp stamped
inside selection. Therefore the warm grid p95 and all Edit first-pixel timings below are invalid
measurements and must not be used as budget evidence. The recorded drawable and render counts remain
historical observations from that run, but the harness did not assert its exact/stale criteria.

| Scenario | p50 / p95 first-pixel or hydration | Frames (provisional / confirmed) | Render admissions | Other counts |
| --- | ---: | ---: | ---: | --- |
| Exact warm Edit | 211.7 / 211.7 ms (1 sample) | 1 / 1 | 0 | 0 crossfades; 0 thumbnail swaps; 2 layout changes |
| Stale warm Edit | 182.3 / 182.3 ms (1 sample) | 1 / 1 | 1 | 0 crossfades; 0 thumbnail swaps; 2 layout changes |
| Warm 30-cell grid | 0.135 / 0.135 ms (5 samples, invalid) | 0 / 0 | 0 | 0 crossfades; 0 thumbnail swaps; 5 navigation flips |
| Warm Edit selection | 196.3 / 197.2 ms (5 samples, invalid timing) | 5 / 5 | 0 | 0 crossfades; 0 thumbnail swaps; 10 navigation flips |

The warm Edit main-actor selection call p95 was reported as 289.0 ms. The corrected harness measures
the first drawable from before the selection call and separately rechecks both budgets. KRMA-743
tracks the main-actor work improvement; no KRMA-734 target was changed.

Trace and full capture summary:
`/tmp/kromora-capture-krma742/KROMORA-last-known-frame-DSC01019-20260930-213520.trace` and
`/tmp/kromora-capture-krma742/KROMORA-last-known-frame-DSC01019-20260930-213520-summary.txt`.

### KRMA-743 diagnostic Release capture (2026-10-01)

The selection path previously performed a portable-library page query and requested an active
edited thumbnail before starting the source load. Those supporting operations are now deferred or
owned by the visible-grid demand path. Selection begins the source transition promptly, while the
stored-frame lookup cancels an older read after yielding; its generation check prevents an old read
from clearing or publishing over a newer selection. Presentation signpost tokens hash the opaque
portable asset UUID directly instead of JSON-encoding the full source fingerprint.

On the same M1 Pro / Xcode 27.0 / macOS 27.0 setup, a 20-iteration Release capture was attempted
with the display awake. The pre-suspension selection call measured 1.23 ms in the single warm-up
sample that ran. The harness then timed out waiting for the RAW preview to settle: it observed one
embedded-JPEG drawable callback at 1,132.7 ms from selection, but no confirmed RAW drawable, so it
did not reach the warm samples or produce a valid p50/p95. This is not a pass for either KRMA-734
latency budget. The warm-up/window harness repair and follow-up capture status are tracked in
KRMA-744. Targets remain unchanged.

Capture summary and trace:
`/tmp/kromora-capture-krma743/KRMA743-retry-DSC01019-20260930-235547-summary.txt` and
`/tmp/kromora-capture-krma743/KRMA743-retry-DSC01019-20260930-235547.trace`.

### KRMA-744 harness repair and first valid capture (2026-10-01)

The harness now measures what the budgets describe (see the method above). Before this, every
attempt either timed out waiting for a drawable or skipped with `occlusionState=8192`; none
produced a record. The cause was the capture host, not the product: xctest never finished
launching or drained AppKit's event queue, so the window was never composited. A scratch probe
showed an `NSApplication.run()` loop (or manually draining events) reaches `occlusionState=8194`,
`active=true` within a second, while a bare `RunLoop` never does. A second, intermittent failure
(about one run in three hung at `provisional`, in a different step each time) was the
`presentedTime == 0` skip described above; with `zeroPresentedTimeFallback` set it did not recur in
8 short runs, a full 30-sample run, and both runs of the rewritten harness (a 5-sample run and the capture below). A deferred perceptual-digest publish in
`AppViewModel.presentAdjustedFrame` was investigated and ruled out for this hang (it never fired in
a failing run).

First valid capture: `scripts/run-kromora-capture.sh --benchmark last-known-frame --source
realworldtest/DSC01019.ARW --iterations 30`, Release, Apple M1 Pro, macOS 27.0 (26A428), stable
Xcode 27.0, commit `a130e6b27c0a7c66a50c7d6772c46549e57e298a` plus the KRMA-744 harness changes,
`DSC01019.ARW` (126 MB, 9504×6336), viewport 1440×897 points / 2880×1794 backing pixels, 86 s,
0 failures. Records:
`/tmp/kromora-capture/KROMORA-last-known-frame-DSC01019-20261001-101504-report.jsonl` (trace and
summary beside it).

| Scenario | p50 / p95 first pixel or hydration | Confirmed p95 | Frames (prov / conf) | Renders | Budget |
| --- | ---: | ---: | ---: | ---: | --- |
| Exact warm Edit (1 sample) | 627 / 627 ms | 933 ms | 1 / 1 | 0 | zero renders, one confirmed: **pass** |
| Stale warm Edit (1 sample) | 651 / 651 ms | 1282 ms | 1 / 1 | 1 | one provisional, ≤ 1 confirmed: **pass** |
| Warm 30-cell grid (30) | 193 / 214 ms | — | — | 0 | p95 ≤ 100 ms: **miss** |
| Warm Edit navigation (30) | 652 / 664 ms | 1009 ms | 30 / 30 | 0 | p95 ≤ 50 ms: **miss** |
| Main-actor before first suspension | p95 72 ms | — | — | — | ≤ 2 ms: **miss** |

Cold grid hydration was 723 ms (one visit, not a budget). Warm grid: 30 mounts, 330 body
evaluations, 0 thumbnail swaps. Warm Edit: 0 crossfades, 0 thumbnail swaps, 870 body evaluations
over 30 samples. These supersede the invalid 2026-09-30 grid and Edit-latency figures above; the
earlier exact/stale one-sample counts agree with the asserted results here.

**Diagnosis of the warm Edit miss.** A 1 ms `sample` of the xctest main thread during a 100-sample
run attributes **37% of all main-thread time to `AccelerateCrypto_SHA256_compress`, every sample of
it under `ImageSource.makePortableIdentity`**. For a URL-backed source that calls
`PortablePhotoSourceFingerprint.file(at:)`, which does `Data(contentsOf:)` and a full SHA-256 of the
126 MB RAW, and `SourceImportPlan.source` is a computed property, so each access builds a new
`ImageSource` and hashes again. The hashing lands at four points of one selection, all on the main
actor: inside `selectCollectionImage` itself (9% of main-thread time; the ~70 ms pre-suspension
miss), `AppViewModel.load` (5%), `SourceSessionCoordinator.prepare` (14%), and
`EditedThumbnailCoordinator.request` after the yield (9%). Roughly half a second of every ~1.4 s
handoff cycle is this hash, which accounts for most of the ~650 ms first pixel even when the stored
frame is exact (627 ms with zero renders). Not attributed: the remainder of the first-pixel time
(SwiftUI Edit-surface mount and inspector construction) should be re-measured after the hash is
removed from the path. The remedy is the portable-identity design question, not a harness defect:
`existing` identity is passed in but the content hash is still recomputed, so reuse it while the
file-change signature (size, modification date, resource identifier) is unchanged, and construct
the plan's `ImageSource` once. Any such change must keep the in-place-replacement identity tests
(KRMA-734) passing.

**Diagnosis of the warm grid miss (partial).** None of the SHA-256 time sits under grid
mount or thumbnail demand. The main-thread profile is dominated by SwiftUI graph updates and layout
(`ViewLayoutEngine.sizeThatFits`, `AG::Graph::update_attribute`, `NSHostingView` transactions): about
11 body evaluations and one full layout per grid entry. The grid re-enters at ~190 ms against a
100 ms budget with nothing else competing, so this needs its own focused profile of grid mount
(cell body cost, whether the 30 cells are laid out eagerly, and the `.onAppear` thumbnail demand);
it is separate from the Edit hashing finding.

Re-run from the repository root with the display unlocked:

```sh
caffeinate -d -t 1800 &
scripts/run-kromora-capture.sh --benchmark last-known-frame \
  --source realworldtest/DSC01019.ARW --iterations 30
```

then read `…-report.jsonl` (or the `LAST_KNOWN_FRAME_BUDGET_SUMMARY` line), and set
`KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1` when the budgets are expected to pass.

KRMA-745 profiling attempt (2026-10-01): a five-sample Release Time Profiler run reported warm-grid
p50/p95 of 205.7 / 206.7 ms, with zero thumbnail swaps and zero render admissions
(`/tmp/kromora-grid-time-profile.jsonl`; trace `/tmp/kromora-grid-time-profile.trace`). Its full
XCTest main-thread sample set contains SwiftUI graph/layout work (`AG::Graph::UpdateStack::update`,
`ForEachState.item(at:offset:)`, `ContentView.body.getter`, and
`LibraryMosaicRow.body.getter`). This profile spans setup, Edit handoffs, and grid re-entry, so those
samples do not isolate the grid interval or quantify a specific view's contribution. A separate
SwiftUI-template recording produced no SwiftUI update rows. The profiling request therefore remains
open. A subsequent 30-sample capture after changing the grid's `AppViewModel` property from
an observed-object wrapper to a plain reference (the `@Observable` migration is complete) was skipped before measurement because the capture window was
not onscreen (`occlusionState=8192`, `isVisible=false`, `keyWindow=false`, `appActive=false`); it
provides no performance evidence. Keep the KRMA-734 target unchanged and complete the capture from an
unlocked, awake display before claiming a pass.

KRMA-738 verification re-run (commit `8bb287a7`, same host, 30 iterations, 88 s, 0 failures) reproduced
the capture: exact and stale warm Edit pass; warm 30-cell grid p50/p95 197 / 202 ms (miss, KRMA-745);
warm Edit navigation p50/p95 676 / 694 ms with main-actor p95 74 ms before first suspension (miss,
KRMA-743). Records: `/tmp/kromora-capture-738v/KRMA738v-DSC01019-20261001-104724-report.jsonl`.
Targets are unchanged.

KRMA-734 verification capture (commit `1145f266` plus the verification fixes below, same host, Apple
M1 Pro, macOS 27.0 (26A428), Xcode 27.0 (27A266a), 30 iterations, 2880×1794 backing, source
`DSC01019.ARW` 9504×6336; records `/tmp/kromora-capture-734v1/KRMA734v1-DSC01019-20261001-150054-report.jsonl`).
Structural budgets pass: exact warm Edit 0 renders / 1 provisional / 1 confirmed; stale warm Edit
1 render / 1 provisional / 1 confirmed; warm Edit navigation 0 renders, 30 provisional / 30
confirmed, main-actor time before first suspension p95 1.86 ms (≤ 2 ms; 1.99 ms in the prior
capture). Per ADR-LKF-001 the wall-clock budgets are release evidence, not a KRMA-734 gate, and
remain **unmet** and unchanged under KRMA-750: warm Edit first pixel p50/p95 265 / 278 ms (target
p95 ≤ 50 ms) and warm 30-cell grid p50/p95 219 / 230 ms (target p95 ≤ 100 ms).

### Last-known-frame measured state after KRMA-746/747/751 (2026-10-01)

Three consecutive `scripts/run-kromora-capture.sh --benchmark last-known-frame --source
realworldtest/DSC01019.ARW --iterations 30` runs on commit `4bbc5c5f`, Release, Apple M1 Pro,
macOS 27.0 (26A428), `DSC01019.ARW` (126 MB, 9504×6336), viewport 1440×897 points, 30 warm samples
each. Values are the median across the three runs, with the three individual p95 values in
parentheses. Reports: `/tmp/kromora-capture/KROMORA-final-{1,2,3}-DSC01019-20261001-*-report.jsonl`.

| Scenario | p50 | p95 | Budget | Result |
| --- | ---: | ---: | --- | --- |
| Exact warm Edit | 293 ms | 293 ms (286/293/313) | zero renders, one confirmed frame | **pass** |
| Stale warm Edit | 275 ms | 275 ms (274/275/276) | one provisional, at most one confirmed | **pass** |
| Warm Edit first pixel | 279 ms | 293 ms (287/293/294) | p95 <= 50 ms | miss (was 664 ms before KRMA-746/747) |
| Main-actor before first suspension | — | 2.03 ms (2.03/2.19/2.00) | <= 2 ms target; median p95 <= 3 ms passes (ADR-LKF-001 amendment) | **pass** (0.03 ms over the 2 ms target; was 72 ms) |
| Warm 30-cell grid re-entry | 227 ms | 235 ms (235/238/235) | p95 <= 100 ms | miss (unchanged across attempts) |

The whole-file SHA-256 on the main actor is gone (KRMA-746, KRMA-747). The first-pixel and grid
misses are tracked, unchanged and non-gating, by KRMA-748 and KRMA-749 under KRMA-750 (see
ADR-LKF-001). Exact warm Edit paints at about 290 ms with zero renders, so the remaining first-pixel
time is Edit-surface mount and SwiftUI work, not rendering or hashing.

### Last-known-frame measured state on Apple M4 Pro (2026-10-10)

Three consecutive direct Release runs of `LastKnownFrameReleaseBenchmark/testReleaseLastKnownFrameBudgets`
with `KROMORA_LAST_KNOWN_FRAME_ITERATIONS=30` on commit `3cba3952`, Apple M4 Pro, macOS 27.2
(26B5101f), Xcode 27.0 beta, `DSC01019.ARW` (9504×6336), viewport 1440×1032 points, 30 warm samples
for the grid and Edit-navigation scenarios. **These are direct runs without `xctrace`**: Instruments
could not record on this machine (`DTServiceHub` connection failure), so there is no Metal System
Trace, and the table below is not a like-for-like comparison with the 2026-10-01 M1 Pro table (different
chip, OS, viewport, and no tracing overhead). Values are the median across the three runs, with the
individual p95 values in parentheses. Reports: `/tmp/kromora-capture/lkf-direct-{1,2,3}.jsonl`.

| Scenario | p50 | p95 | Budget | Result |
| --- | ---: | ---: | --- | --- |
| Exact warm Edit | 365 ms | 365 ms (365/375/363) | zero renders, one confirmed frame | **pass** |
| Stale warm Edit | 363 ms | 363 ms (364/362/363) | one provisional, at most one confirmed | **pass** |
| Warm Edit first pixel | 361 ms | 387 ms (389/387/387) | p95 <= 50 ms | miss |
| Main-actor before first suspension | — | 99.0 ms (99.2/99.0/99.0) | <= 2 ms target; median p95 <= 3 ms | **miss** |
| Warm 30-cell grid re-entry | 142 ms | 147 ms (147/147/147) | p95 <= 100 ms | miss |

Exact and stale warm Edit are single-sample scenarios by design (`sampleCount` 1); their p50 and p95
are that sample. One run recorded a single zero-presented-time fallback in each scenario; the other two
recorded none.

Compared with 2026-10-01 the grid re-entry p95 improved (235 to 147 ms) but still misses its 100 ms
budget. The main-actor time before the first suspension is about 99 ms, far above the 2.03 ms measured
after KRMA-746/747 and close to the 72 ms that fix removed. This is not explained by the
hardware change: a faster chip should lower it. KRMA-860 found the cause (below), so the 99 ms is a
regression that has since been fixed, not a baseline. The warm Edit first-pixel p95 (387 ms) was
inflated by the same main-thread starvation.

#### Post-fix state (KRMA-860, 2026-10-10)

Cause: whole-file SHA-256 hashing on the main actor while building an `ImageSource`, about 50 ms for a
126 MB ARW. Two paths: (1) `makePortableIdentity` compared the persisted file-change signature with
`==`, but package dates are whole seconds, so it never matched; (2) browsing assets carry a placeholder
signature, so edited-thumbnail requests, adjacent-preview prefetch, the idle warmer, and open all
rehashed (about 35 in a row at idle). Fixes: `2eaef446` (tolerant `isSameFileSnapshot`), `0b152709`
(keep the stored hash for a real identity with a browsing signature; legacy `browsing-v1` identities
still hash), `871d216d` (`wholeFileRehash` log line).

Post-fix evidence is a **dev-build** photo-switch timeline (three Library to Edit switches, KRMA-869
log), not the Release `last-known-frame` p95 series:

| Phase | Before | After |
| --- | ---: | ---: |
| `selectPortableItem` | 50.8 ms | 2.4 ms |
| `selectionSyncReturned` | 100.9 ms (303.8 in one run) | 2.8 ms |
| `loadSyncPrefix` `planMs` | 49-50 ms | 0 ms |
| `beginLoadScheduled` | 520 ms | 32 ms |
| First pixel, stored frame | 1,313-1,955 ms | 74 / 192 / 205 ms |

No `wholeFileRehash` runs on the main thread; the remaining ones are off-main in source preparation
(`hadStoredSignature=false`, 50-62 ms each).

**Release measurement (2026-10-11, KRMA-860):** three supervised `last-known-frame` runs on Apple M4 Pro /
macOS 27.2, DSC01019.ARW, 30 warm samples each, run with `--no-trace` because Instruments could not
record (`DTServiceHub` error). Run 1 used `873684f2`; runs 2 and 3 used `d2d1c72b`. Main-actor time
before first suspension p95 (warm Edit navigation) was 1.47, 1.52, and 1.48 ms, **median 1.48 ms**, inside
the <= 3 ms budget. Selection sync is about 1.4 ms per switch. For context, warm Edit first-pixel p95 was
187-197 ms and warm 30-cell grid p95 154-157 ms; both miss the old optional 50/100 ms budgets, which were
closed as won't-do after a release build felt fast (KRMA-748/749/750). Regression guard without a
window: `ImageSourceIdentityReuseTests` (the date round-trip test fails without the fix).

### Last-known-frame measured state on Apple M1 Pro (2026-10-14)

One `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30`
run on commit `aef050e8`, Release, Apple M1 Pro (16 GB), macOS 27.0.1 (26A434), `DSC01019.ARW`
(9504×6336), viewport 1440×897 points, backing 2880×1794. Instruments recorded a Metal System Trace,
so this is comparable to the 2026-10-01 M1 Pro table above and not to the 2026-10-11 M4 Pro
`--no-trace` series. The XCTest passed (1 test, 0 failures, 44.7 s). Budgets were not enforced.
Report, summary, and trace:
`/tmp/kromora-capture/KROMORA-last-known-frame-DSC01019-20261014-084221-report.jsonl`,
`-summary.txt`, and `.trace`.

| Scenario | p50 | p95 | Samples | Budget | Result |
| --- | ---: | ---: | ---: | --- | --- |
| Exact warm Edit | 268 ms | 268 ms | 1 | zero renders, one confirmed frame | **pass** |
| Stale warm Edit | 228 ms | 228 ms | 1 | one provisional, at most one confirmed | **pass** |
| Warm Edit first pixel | 249 ms | 286 ms | 30 | p95 <= 50 ms | miss |
| Main-actor before first suspension | — | 1.32 ms | 30 | <= 2 ms; median p95 <= 3 ms passes | **pass** |
| Warm 30-cell grid re-entry | 210 ms | 247 ms | 30 | p95 <= 100 ms | miss |

`LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=PASS stale=PASS grid=FAIL edit=FAIL`. Exact warm Edit had 0
render admissions, 1 provisional, and 1 confirmed frame. Stale warm Edit had 1 render admission,
1 provisional, and 1 confirmed frame. Warm Edit navigation had 0 render admissions, 0 crossfades,
0 thumbnail swaps, and 30 provisional / 30 confirmed frames. The grid had 30 mounts, 0 thumbnail
swaps, and 0 render admissions. Cold grid hydration was 1270 ms (one visit, not a budget).
`zeroPresentedTimeFallbacks` was 1 on exact warm Edit and 2 on the other three scenarios, which is
normal for this harness; the times are handler time.

Cite this capture for later M1 Pro traced runs. It sits in the same band as the 2026-10-01 three-run
median (Edit first-pixel p95 293 ms, grid p95 235 ms, main-actor p95 2.03 ms) after the Library and
Edit paths changed substantially. The 50 ms and 100 ms misses stay the closed won't-do work in
KRMA-748, KRMA-749, and KRMA-750. A wall-clock miss on an unchanged tree is a handoff with this
profile (ADR-LKF-001); do not start another capture to reproduce it.

### Warm navigation profile without a window (KRMA-1002, 2026-10-14)

`WarmNavigationProfileBenchmark` (optional lane; `KROMORA_WARM_NAVIGATION_PROFILE=1 swift test -c release --filter WarmNavigationProfileBenchmark`)
mounts the shipping `ContentView` in an `NSHostingView` that is never attached to an `NSWindow`,
lays it out by hand at 1440×897 points, and drives `selectCollectionImage` / `navigate(to:)`. It
uses the exact stored frame, so the warm Edit path is the zero-render case. Two runs, Release,
Apple M4 Pro (48 GB), macOS 27.2 (26B5112a), commit `6568ffbd`, `DSC01019.ARW` (9504×6336), 30
samples after 5 unmeasured warm-up opens, package library of 30 items, no window, no compositor.
These are **not** comparable to the M1 Pro capture above (different chip, no display path); the
only like-for-like context is the 2026-10-11 M4 Pro capture (Edit p95 187-197 ms, grid p95 154-157 ms).

| Phase (p50 / p95, run 1; run 2 in parentheses) | Library → Edit | Edit → Library |
| --- | ---: | ---: |
| State publication (`selectCollectionImage` / `navigate` return) | 0.33 / 0.35 ms (0.32 / 0.37) | 0.03 / 0.03 ms |
| View mount + layout (first synchronous `layoutSubtreeIfNeeded`) | 24.6 / 28.8 ms (25.0 / 27.3) | 28.4 / 29.9 ms (28.4 / 30.3) |
| All layout passes until settled | 30.6 / 35.7 ms (31.5 / 42.1) | same as first pass |
| Frame hydration (selection → `previewSurface.image` set) | 46.9 / 54.7 ms (46.5 / 58.1) | 28.4 / 29.9 ms (grid cells already hydrated) |
| Drawable presentation | not measurable without a window | not measurable without a window |

Counts: warm Edit admitted 1 and 2 renders over 30 samples (plus 1 in the 5 warm-ups) because with no
window the presentation session never confirms; the capture's zero-render result remains the
authority. Edit → Library admitted 0. Body evaluations per sample: about 10.5 (Edit) and 4.0 (grid).
`AppViewModel.document` published **0** Observation invalidations per sample in both directions.

The unattached hosting view has no SwiftUI App/Scene lifecycle. A counterpoint rerun on 2026-10-14
at `1633ec3f` emitted SwiftUI `SceneStorage` warnings from `LibraryGridView` and used the default
constant binding for `libraryFacetSidebarPresented`; the benchmark does not manipulate this
control. Treat this as a no-scene harness limitation when interpreting layout timings.

What this shows. On this machine the whole main-actor chain up to a hydrated frame is about 47-58 ms
for Edit and about 30 ms for the grid, and state publication is under 0.4 ms. Mounting and laying
out the hierarchy is a single synchronous pass of 25-29 ms and is the largest window-independent
piece. This breakdown does not attribute the remaining display-bound interval: the M4 window-free
profile and the 2026-10-11 M4 capture used different methods and commits, while the 2026-10-14 M1
capture is a different machine. Do not subtract these measurements to estimate a drawable,
compositor, or window-layout remainder. Some capture timestamps are callback-handler fallbacks,
which also limits attribution. The profile does **not** show `document` invalidation rebuilding
Light, Color, Effects, and the preview together on this path (document never published), so no
Observation-splitting ticket was filed.

Proposed targets (proposals only; nothing is adopted in code, and KRMA-952 decides):

| Target | Proposal | CI-assertable? |
| --- | --- | --- |
| First meaningful pixels (stored frame on canvas) | p95 ≤ 150 ms on M4-class, ≤ 250 ms on M1-class | Supervised capture only; window-free proxy: hydration p95 ≤ 100 ms (this benchmark, optional lane) |
| Usable controls (inspector sliders respond) | main-actor work before first suspension p95 ≤ 3 ms (already asserted); mount + layout pass p95 ≤ 40 ms | Pre-suspension is already structural; layout is optional-lane evidence |
| Final-quality settlement | confirmed full-quality frame p95 ≤ 1 s with ≤ 1 render | Render counts in CI (`WarmReopenPresentationTests`); time is supervised |
| p99 frame gaps during navigation | no gap > 50 ms after first pixel | Supervised capture only (needs a display link) |
| Cancellation under rapid navigation | N rapid selections leave one live session, 0 stale-generation presentations | Yes, fake-engine tests (`PreviewPresentationCoordinatorTests` style) |

Reproduce with the command above; do not run `scripts/run-kromora-capture.sh` for this question.

### Bundled Look load cost (KRMA-1113, 2026-10-26)

`BundledLookLibrary.load()` runs synchronously inside `LUTLibrary.init` on the main thread. Measured in a
release build (`swift test -c release -Xswiftc -enable-testing`, no window) on Apple M4 Pro with 20
generated 33^3 text cubes (35,937 rows each, ~750,000 lines):

| Loader | 20 x 33^3 cubes | Shipping set (14 cubes, one 33^3) |
| --- | --- | --- |
| Serial (before) | 0.748-0.753 s, main thread | 0.109 s |
| Parallel across cores (after) | 0.216-0.239 s, main thread | not re-measured |

About 37 ms per 33^3 cube serially, which is too much to add to launch for ~20 cubes. The fix parses the
independent cubes with `DispatchQueue.concurrentPerform` and folds results back in manifest order, so
duplicate detection, warnings, stable ids and Look output are unchanged. The load is still on the main
thread (~0.22 s for the full film family); moving it off the main actor or to a binary resource is the
next step if the budget is tightened.

### Render-key hashing baseline (KRMA-954, 2026-10-24)

`RenderKeyHashingBenchmark` (optional lane; `KROMORA_RENDER_KEY_BENCHMARK=1 swift test -c release
--filter RenderKeyHashingBenchmark`, `KROMORA_RENDER_KEY_ITERATIONS` defaults to 30) uses a real
`RenderEngine` and no window. It times the JSON + SHA-256 cache-identity digests in a warm
interactive request, one durable `editHash`, and the extra component hashes on a first mask-payload
cache miss, beside a 30-tick exposure drag. The warm request has 19 digests for five masks; the
first request has 24 because `DefaultLocalMaskResolver` hashes each component definition once more.
The real-engine drag recorded 150 payload-cache hits and five misses. Verification rerun on Release,
Apple M4 Pro, macOS 27.2, 30 iterations; medians:

| Recipe | Warm digests / ms | Cold digests / ms | `editHash` | Engine ms / warm request (p95) |
| --- | ---: | ---: | ---: | ---: |
| Plain document | 6 / 0.153 | 6 / 0.152 | 0.049 ms | 3.02 (3.64) |
| 5 brush masks (480 samples) | 19 / 4.763 | 24 / 5.483 | 0.810 ms | 168.62 (221.23) |
| 5 brush masks, large recipe (20,480 samples) | 19 / 173.573 | 24 / 202.743 | 29.204 ms | 636.64 (657.61) |

`docs/RENDER_KEY_PLAN.md` interprets the numbers and stages the fix. Child tickets record their
before/after numbers from the same benchmark.

**KRMA-1098 main-actor identity (2026-10-24).** `markingManualEdits`, `AutoWorkflowCoordinator`'s
change check, and `PreviewFrameIdentity` now compare documents with `==` (Auto fingerprint cleared
via `EditDocument.visibleEditValue`) instead of `renderingHash`/`editHash`. The benchmark's
`main_actor_tick_ms` times one `markingManualEdits` plus one frame-identity construction. Before:
two `renderingHash` calls plus one `editHash` per presented frame (about 87.6 ms on the large
recipe at 29.204 ms each; plain about 0.15 ms). After (Release, M4 Pro, macOS 27.2, medians):

| Recipe | `main_actor_tick_ms` before | after |
| --- | ---: | ---: |
| Plain document | about 0.15 | 0.0005 |
| 5 brush masks | about 2.4 | 0.0007 |
| 5 brush masks, large recipe | about 87.6 | 0.0007 |

`EditDocumentIdentityTests` pins the durable `editHash` bytes for a fixture with a brush mask, a
Look, and an excluded Auto fingerprint.

**KRMA-1099 durable editHash memo (2026-10-24).** `EditDocument.editHash`/`renderingHash` read
`DurableEditIdentityMemo.shared`, a bounded (8) in-memory memo matched by `==` on `visibleEditValue`.
The bytes are unchanged (golden test), so no stored frame, revision, or cache is invalidated. Every
remaining consumer (preview classification and canonical writes, thumbnails, idle warmer, Look
strip, Auto fingerprint, measurement, Apple reference) now shares one digest per distinct document
value; `EditDocumentIdentityTests` asserts one computation per value over a 30-tick drag with six
consumers per tick (was six per tick). Concurrent first reads of one value coalesce on a per-value
slot, so simultaneous consumers share one computation (`testConcurrentMissesCoalesceIntoOneDigest`).
The Look preview cache key and async durable writes (canonical preview frame, idle-warmer write,
edited-thumbnail signature and revision, `storedFrameIsExact`) read `digestOffCaller(for:)`, which
computes a miss on the concurrent pool and never on the main actor. `testStoredFrameWithGoldenHashClassifiesExactAfterRoundTrip`
round-trips a frame signed with the golden pre-memo digest through `FrameClassifier` as `.exact`.
Remaining synchronous main-actor reads (open-time stored-frame classification and Auto) are not
per-tick paths.

First-miss cost over 30 distinct drag values (Release, M4 Pro, macOS 27.2, medians; "before" is the
digest computed on the caller, "after" is the work left on the calling actor, the memo lookup):

| Recipe | before: first miss on caller ms | after: main-actor ms | off-caller end to end ms |
| --- | ---: | ---: | ---: |
| Plain document | 0.050 | 0.0005 | 0.050 |
| 5 brush masks | 0.797 | 0.0006 | 0.797 |
| 5 brush masks, large recipe | 28.482 | 0.0018 | 28.439 |

Repeat reads of a memoized value cost an `==` (about 15 µs worst case, < 0.01 µs on shared storage).

**KRMA-1100 `RenderDocumentIdentity` and engine memo (2026-10-24).** Adds the session-tier
identity value and `RenderDocumentIdentityMemo` (owned by `RenderEngine.documentIdentity(for:source:)`)
with no production call-site change; KRMA-1101 threads it through the render path. The benchmark's
`identity_build_ms` reports a cold build and a memoized build after an exposure tick (Release,
M4 Pro, macOS 27.2, 30 iterations, medians; the render path today still pays the 19 warm digests
above until KRMA-1101 lands):

| Recipe | cold build ms | memoized after exposure tick ms (p95) |
| --- | ---: | ---: |
| Plain document | 0.069 | 0.056 (0.059) |
| 5 brush masks | 2.280 | 0.056 (0.059) |
| 5 brush masks, large recipe | 86.897 | 0.058 (0.066) |

`RenderDocumentIdentityTests` covers equal documents (including a JSON round trip), per-component
digest changes, memo miss versus cold build, a `NaN` field never reusing a digest, memo bounds,
and the `==` audit over representative `EditDocument` field edits.

**KRMA-1101 render path on `RenderDocumentIdentity` (2026-10-26).** `RenderEngine` builds the
identity once per request (`documentIdentity(for:source:)`) and threads it through `RenderBuildPlan`
(mask recipe fence and revision-ledger document key), the preview key, `DevelopedSourceCacheKey` and
the RAW `OutputKey`, both processing-prefix keys, `LocalMaskCacheKey.definitionHash`, and
`LocalMaskResolveRequest.definitionHash`. No `digest(document)`, `digest(rawDevelop)`,
`digest(localAdjustments)`, or `digest(component.source)` call remains in `RenderEngine.swift` or
`LocalMaskRendering.swift`. The benchmark's mirrored set is now the two memoized identity lookups a warm
request makes (an exposure-tick build plus a memo hit) and, for a first cache miss, one cold build.
Release, M4 Pro, macOS 27.2, 30 iterations, medians:

| Recipe | Warm digest ms/request before → after | First cache miss ms before → after |
| --- | ---: | ---: |
| Plain document | 0.153 → 0.064 | 0.153 → 0.067 |
| 5 brush masks | 4.7 → 0.068 | not baselined separately → 2.286 |
| 5 brush masks, large recipe | 173.573 → 0.067 | 202.743 → 85.204 |

`RenderCacheTests.testDocumentIdentityKeysReuseAndInvalidateTheRightCaches` proves an exposure tick
reuses the developed-source and mask-payload entries, and that a brush edit, a RAW-develop edit, and a
crop edit miss the mask, developed-source, and preview caches respectively.

### Persisted package identity hash reuse (KRMA-753, 2026-10-01)

Release last-known-frame capture after reusing the asset record's content hash for an unchanged
embedded original: `scripts/run-kromora-capture.sh --benchmark last-known-frame --source
realworldtest/DSC01019.ARW --iterations 30 --capture-id KRMA753 --output-dir
/tmp/kromora-capture-krma753`. One run on Apple M1 Pro / macOS 27.0 (26A428), Xcode 27.0,
9504×6336 DSC01019.ARW, 1440×897-point viewport, 30 warm navigation samples. The warm Edit
first-pixel p50/p95 was 264.3 / 283.0 ms, versus the three-run KRMA-746/747 baseline median p95
of 293 ms (about 10 ms lower in this run). The 50 ms p95 target remains unmet. Main-actor time
before first suspension was 1.96 ms p95. Exact and stale warm Edit structural checks passed; the
warm 30-cell grid p95 was 221.9 ms and remains over its 100 ms target. Capture records and trace:
`/tmp/kromora-capture-krma753/KRMA753-DSC01019-20261001-201014-report.jsonl` and
`/tmp/kromora-capture-krma753/KRMA753-DSC01019-20261001-201014.trace`.

Also fixed in this pass: a package-library photo selected from the filmstrip left the previous
photo's pixels on the canvas while its record resolved. `AppViewModel.openImage` now clears the
surface and resets the presentation session before that suspension, covered by
**KRMA-1102 per-stroke brush identity (2026-10-26).** `BrushStrokeDigest` memoizes
`RenderCacheHash.digest(stroke)` per stroke ID and reuses it by `==` (O(1) for strokes that share
sample storage). A brush definition digest is SHA-256 over the ordered per-stroke digests.
`RenderDocumentIdentity` uses it for mask component digests, and for the `localAdjustments` and mask
recipe digests through `RenderCacheHash.sessionDigest`, a session-only encoding that substitutes the
composition for the samples; the durable `BrushMaskDefinition` encoding and `editHash` are unchanged.
`LocalMaskRenderer`'s stroke raster cache key reuses the same per-stroke digest. The benchmark's
`paint_tick_identity_ms` appends one sample to the last stroke of the last brush mask per tick and
times the memoized identity build. Release, M4 Pro, macOS 27.2, 30 iterations, medians:

| Recipe | Paint-tick identity ms before → after |
| --- | ---: |
| Plain document | not applicable (no brush) |
| 5 brush masks (48-sample active stroke) | 1.68 → 0.198 |
| 5 brush masks, large recipe (512-sample active stroke) | 61.9 → 0.839 |

The plain document's warm request is unchanged by this ticket (0.061 ms, two memoized lookups). The
first-miss identity build for brush recipes now reads about 0.17 ms in the benchmark only because the
process-wide stroke memo is already warm from earlier iterations; a truly cold process still encodes
each stroke once (about 56 ms for the large recipe).

`LibraryBrowsingProjectionTests`. Full gate on `4bbc5c5f`: warning gate, `fast`, `serial` (455
tests), and `identity` (4 tests) all pass.

### Edit-panel stored-edit adoption (KRMA-755)

The Edit panel binds to `AppViewModel.document`. The stored edit document is a small read that now
starts in `SourceSessionCoordinator.begin` at selection and is published through
`onStoredDocumentLoaded` as soon as it is read; `AppViewModel.adoptStoredDocumentValues` puts it on
the panel. Before this change it was published only after `engine.prepareSource` returned, and
preparation is serialized behind the previous source, so the panel waited for the RAW to prepare
while the pixels (from the stored frame) did not. The source-dependent reconciliation
(`adoptStoredEdits`: source size, mask selection, corrective render, histogram, deferred preview)
is unchanged and still runs after preparation. If the stored document reached the panel before the
first render was scheduled, that render already uses it and no corrective render is queued.

`StoredEditAdoptionBenchmark` measures it without a window, so it needs no unlocked display:

```sh
KROMORA_STORED_EDIT_ADOPTION_BENCHMARK=1 KROMORA_STORED_EDIT_ADOPTION_ITERATIONS=10 \
swift test -c release --filter StoredEditAdoptionBenchmark
```

It reopens a package with a stored exposure edit for each sample (real `RenderEngine`, real RAW,
empty frame store, production browsing items) and prints one `STORED_EDIT_ADOPTION` line. Release,
Apple M1 Pro, macOS 27.0, `DSC01019.ARW` (126 MB), 10 samples each, milliseconds from selection:

| | Panel has stored values (p50 / p95) | Source prepared (p50) | Photo ready (p50 / p95) |
| --- | ---: | ---: | ---: |
| Before | 295 / 308 | 295 | 915 / 1354 |
| After | **154 / 197** | 292 | **703 / 740** |

Before the change the panel received its values at exactly the instant preparation finished (lead
0.0 ms). After it the panel leads preparation by about 138 ms at the median, and the photo settles
about 210 ms sooner because the redundant corrective render is gone. The panel now has its values
before first pixel (about 290 ms in the last-known-frame capture). What remains in the 154 ms is the
package-record resolution hop in `openImage` plus the edit read; it has not been profiled.

Deterministic coverage (`StoredEditAdoptionTests`, fake engine with source preparation held open):
the panel gets the stored values while preparation is pending; the first render uses the stored
document so no canvas render uses the identity document; and a superseded selection never publishes
the old photo's values. All three fail on the previous code.

#### Warm switch and histogram timing (KRMA-757)

The opt-in benchmark now reports both `relaunch` and `switch`. Relaunch retains the one-photo,
fresh-view-model setup above. Switch imports three copies of the RAW with distinct stored exposure
values, opens A and waits for its histogram, then measures B→C→B while the same view model remains
open; it returns to A between rounds. A histogram sample counts only when its `HistogramData` differs
from the previous photo's value, since the prior chart intentionally remains visible during a switch.

Release, Apple M4 Pro Mac mini, macOS 27.2, `DSC01019.ARW` (126 MB): 10 relaunch samples and 30 warm
switch samples (10 A→B→C→B rounds), milliseconds from selection. Histogram-after-ready is
`histogram - ready` at p50.

| Scenario | Panel stored values (p50 / p95) | Source prepared (p50 / p95) | Photo ready (p50 / p95) | Histogram (p50 / p95) | Panel lead p50 | Histogram after ready p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Relaunch (10) | 451 / 514 | 618 / 778 | 901 / 1111 | 916 / 1129 | 170 | 16 |
| Warm switch (30) | 95 / 296 | 188 / 424 | 188 / 684 | 244 / 697 | 93 | 56 |
| Warm switch after neighbour warming (KRMA-758, 30) | **92 / 140** | 182 / 268 | 182 / 649 | 237 / 662 | 91 | 54 |

On this run, the histogram followed ready by 15.8 ms at the relaunch median and 55.6 ms after a warm
switch. Warm-switch panel adoption was 95.1 ms at p50, below the cold relaunch's 450.9 ms.

KRMA-758 ran the same Release switch scenario on Apple M4 Pro, macOS 27.2, using 10 rounds and the
same 126 MB RAW. The warmed neighbour reached the panel in 91.6 ms at p50 (140.2 ms p95), compared
with the KRMA-757 baseline of 95.1 ms p50 (296 ms p95). The median improved by 3.5 ms but missed the
under-50 ms aim. The warmed path still measures selection through publication as a whole; the
remaining time in the document cache-hit validation and source handoff has not been separately
profiled, so no additional machinery was added.

#### Histogram delay investigation (KRMA-759)

The same Release `StoredEditAdoptionBenchmark` was run on an Apple M4 Pro Mac mini with macOS 27.2
and `DSC01019.ARW`. The KRMA-757 baseline was 54.1 ms histogram-after-ready p50 across 30 warm
switches. A 30-switch run that temporarily admitted histogram work at comparison priority before
the supporting comparison render measured 54.4 ms p50, so changing queue order did not improve the
result. The temporary scheduling change was removed.

To split the delay, a temporary monotonic timestamp probe recorded the confirmed-frame callback,
histogram enqueue, scheduler operation start, and completion of `engine.histogram` for 9 warm-switch
samples. At p50, confirmed frame to enqueue was 0.013 ms, scheduler queue wait was 0.075 ms, and the
histogram call took 53.3 ms. This is compute-bound; the histogram's bounded Core Image rasterization
accounts for essentially all of the roughly 55 ms after-ready delay. The probe was removed, and no
product change was retained. The previous chart remains visible while this computation runs by
design, which adds to the perceived delay after a photo switch.

## Package import throughput measured state (KRMA-840, 2026-10-09)

Use the window-independent package transport harness in **Release**. Debug builds inflate Swift
loop, JSON, path-validation, and observation costs and are not throughput evidence. The harness
creates fresh temporary packages and deterministic camera-sized byte payloads (not decoded images):
200 small files totaling 64 MiB (192 × 256 KiB plus 8 × 2 MiB), and 12 large files totaling
512 MiB (8 × 32 MiB plus 4 × 64 MiB). Source generation and package creation are outside the timer;
SHA-256, duplicate-catalog construction, lease renewal, staging, and each source's durable commit
are inside it. The disposable index delta/write is reported separately. No window is created.

```sh
KROMORA_IMPORT_BENCHMARK=1 swift test -c release \
  --filter PortablePackageImportPerformanceTests

# Optional read-only camera source; defaults to twelve non-hidden files in filename order.
KROMORA_IMPORT_BENCHMARK=1 \
KROMORA_IMPORT_SOURCE_DIR=/Volumes/Card/DCIM/100MSDCF \
swift test -c release --filter PortablePackageImportPerformanceTests
```

`KROMORA_IMPORT_SAMPLES` defaults to three. `KROMORA_IMPORT_SOURCE_COUNT` and
`KROMORA_IMPORT_SOURCE_OFFSET` select a bounded card sample; `KROMORA_IMPORT_CHUNK_SIZE` allows
chunk-size experiments. The optional suite is excluded from the required fast/serial lanes.
`IMPORT_THROUGHPUT` prints decimal MB/s, wall time, index time, and opt-in per-phase totals.
`read`, `hash`, and `write` are nested within `staging`; staging also includes record/membership
encoding and path work. `begin` includes lease renewal and the initial journal. `commit` includes
flushes, destination SHA-256 verification, durable publication journals, renames, and cleanup.

`F_NOCACHE` on the sequential reference prevents that pass from intentionally filling the cache;
it does **not** evict pages cached by an earlier import. Generated files start in the write cache,
so their read reference measures cache throughput, not physical SSD speed. For card evidence, use
files not previously imported/read in the session and report cold and warm results separately.
Do not interpret a subsequent multi-GB/s card result as reader throughput or purge global caches
to hide this distinction. The optional camera originals are only read and are never copied into
the repository.

Measurements used an Apple M4 Pro, 48 GB RAM, macOS 27.2 (26B5101f), Xcode 27.0 beta
(27A5252f), a temporary destination on the internal APFS SSD, and a 128 GB USB/ExFAT removable
card. The baseline was `32e3f688` plus timing-only instrumentation; all timed runs used streamed
copying (no APFS clone shortcut), 1 MiB chunks, and fresh empty packages. Generated results are
medians of three runs. A separate 4 MiB baseline experiment produced 2.68 MB/s small and
297.73 MB/s large, giving no reason to increase the default chunk or cancellation bound.

| Mix | Baseline MB/s | After MB/s | Change | Baseline / after wall time |
| --- | ---: | ---: | ---: | ---: |
| Generated small, cache resident | 2.74 | 4.23 | +54% | 24.52 / 15.85 s |
| Generated large, cache resident | 301.87 | 394.77 | +31% | 1.779 / 1.360 s |
| Camera RAWs, first cold pass | 84.51 | 87.12 | +3.1% indicative | 17.97 / 17.57 s |

The cold card baseline used twelve RAWs totaling 1,518,751,744 bytes; after used twelve different,
previously unread RAWs totaling 1,530,351,616 bytes (`KROMORA_IMPORT_SOURCE_OFFSET=24`). Their
sequential references were 93.77 and 94.86 MB/s. These are single cold observations of different
file groups, not a statistically established 3.1% card improvement. After import achieved **92%**
of its sequential reference. Subsequent cached card samples reached 561–565 MB/s before and
614–655 MB/s after; their 9.7–11.1 GB/s reference rates identify them as cached, and they are
excluded from cold-reader evidence.

Representative phase totals in seconds (the generated rows are the median-throughput runs):

| Mix / version | Catalog | Begin | Read | Hash | Write | Staging, inclusive | Commit | Index |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Small before | 0.0527 | 2.4118 | 0.0205 | 0.0385 | 0.0178 | 7.4853 | 14.5361 | 0.0049 |
| Small after | 0.0517 | 2.3815 | 0.0184 | 0.0366 | 0.0168 | 1.3842 | 12.0023 | 0.0055 |
| Large before | 0.0514 | 0.1245 | 0.0532 | 0.1873 | 0.0399 | 0.6838 | 0.9179 | 0.0003 |
| Large after | 0.0515 | 0.1245 | 0.0491 | 0.1794 | 0.0404 | 0.3076 | 0.8755 | 0.0003 |
| Cold card before | 0.0536 | 0.1240 | 15.4283 | 0.4910 | 0.1816 | 16.5022 | 1.2895 | 0.0004 |
| Cold card after | 0.0547 | 0.1208 | 15.3697 | 0.4965 | 0.1804 | 16.0927 | 1.2970 | 0.0003 |

The measured small-file bottleneck was fixed transaction overhead, not read chunking or SHA-256.
Staging no longer repeats durable file flushes and file-list journal writes that commit already
performs. Recovery discards all preparation under the durable initial journal; commit still
persists the complete list, flushes every file, verifies the destination hash/length in bounded
1 MiB chunks, and durably journals every publication boundary. One transaction per source,
lease renewal, duplicate policy, and already-committed successes survive cancellation unchanged.
Small files still pay approximately 60 ms/source in commit plus 12 ms/source to begin/renew: that
integrity floor explains why their throughput remains far below a reader's sequential bulk rate.

For cold RAWs, reading takes 15.37 of 17.57 seconds. Source SHA-256 (0.50 s), writes (0.18 s), and
commit/verification/publication (1.30 s) explain most of the remaining gap; the reference pass also
warms filesystem metadata and read timing varies. Overlapping hashes or adding parallel card reads
would address a small fraction of this workload and was not justified by these measurements.
The duplicate catalog is built once (about 53 ms for an empty library); this harness does not
establish its cost in a populated library. The asynchronous app path applies the final index delta
once and coalesces its disposable write rather than synchronously rewriting it per source.

The redundant per-selection readability/yield loop was removed: scanned selections go directly
to the worker, which isolates source-open failures if media disappears. The progress sink publishes
at most ten work snapshots/second plus preparation/final totals, starts staging immediately, and
buffers only the newest snapshot when the main actor is busy. Streamed sources report bytes each
chunk and retain partial byte totals through cancellation or a source failure. Recovery, corruption,
known SHA-256, duplicate policies, per-source failure isolation,
cancellation during copy/checksum, and bounded progress tests cover these contracts.

This harness excludes the selector's decode/EXIF scan and the post-import grid/thumbnail work;
it does not establish end-to-end UI import latency. Those remain KRMA-839/KRMA-841 work. No
display-bound capture was run.

Final verification passed the warnings-as-errors build, 1,572 fast tests, 500 serial tests, the
44-test focused Release run including the benchmark, packaged app build/verification, and
`git diff --check`. `dg validate` passed with existing model-registry warnings. The first fast run
hit two assertions in the unrelated
`ThumbnailSwitchLifecycleTests.testFilmstripSelectionSchedulesOriginalBeforeAdjustedDrawableConfirmation`;
its focused rerun and both subsequent full fast runs passed without changing that test or product
path. This is a synchronization caveat, not evidence of an import regression.

### Info color-gamut view (KRMA-1132)

The Info tab's collapsed-by-default "Color Gamut" disclosure measures the edited result. While
collapsed or hidden it does nothing. Expanded, `AppViewModel.measureGamut()` asks `RenderEngine`
(`gamutSample(presentedImage:maxDimension:)`) to rasterize the last presented frame, already
completed on the GPU so no graph is rebuilt, into a float sample of at most 512 px on the long
side. The sample is RGBAf in extended-linear Display P3, so out-of-range (beyond-P3) values
survive. The pure `GamutTally(linearDisplayP3:)` then runs on a detached utility task. The
disclosure's `task(id:)` is keyed on the histogram's `sampleIdentity`, so it re-measures once per
edit or image switch and a cancelled task discards its result. Cost is one 512-px render plus a
tally of at most ~262k pixels, only while the disclosure is open. The plot is a 64x64 CIE 1976
u'v' density with sRGB and Display P3 triangles.

Tests: `GamutTallyTests` (pure tally) and `GamutSampleTests`, which push a generated
extended-linear image with sRGB-safe, P3-only and beyond-P3 quadrants through the production
`gamutSample` then `GamutTally` path (outside sRGB 50%, outside P3 25%).
`GamutSampleLocalFixtureTests` is the opt-in local-fixture lane. On the default edit it measured
(outside sRGB / outside P3): Sony ARW 0% / 0% (both files); iPhone DNG 0% to 4.46% / 0%. The
Sony figures match KRMA-1114's 0%; the iPhone maximum differs from KRMA-1114's 4.39% by 0.07
percentage points, within a stated 0.1-point tolerance. This measures the edited, tone-mapped,
512 px preview sample, while KRMA-1114 used a one-off decode, so small differences are expected.
The HEIC fixture is not a RAW extension, so this lane does not cover it.
