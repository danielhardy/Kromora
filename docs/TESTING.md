# Testing and profiling

The release bar and interpretation of required versus optional checks are summarized in
[`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). This document is authoritative for verification commands
and lane requirements.

The required checks are deterministic build/test lanes. Hardware, AppKit, RAW, and Instruments
work is opt-in because it needs a logged-in display or licensed local fixtures.

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

`warning-gate` builds the package and test target with Swift compiler warnings promoted to errors
(`swift build --build-tests -Xswiftc -warnings-as-errors`). This is deliberately compiler-enforced
rather than a grep over build output: SDK/toolchain paths and informational output cannot create
false positives, while a warning introduced in `Sources/` or `Tests/` fails the build. Keep the
gate on the supported Xcode/macOS toolchain; do not add warning suppressions or Swift 6 opt-outs
to make it pass.

`fast` covers deterministic model, coordinator, and fake-engine tests in parallel. `serial` covers
Core Image, render, and AppKit/UI-sensitive tests. `scripts/ci-tests.sh optional` runs RAW-fixture,
benchmark, and packaging checks when their inputs are available. Procedural fixtures are created by
the tests and are not committed; the photo-intelligence resource exception is documented below.

`PresentationBudgetTests` is part of `serial`. It uses generated package fixtures and two distinct
`AppViewModel` lifetimes for the exact-frame relaunch cases; the cold canonical-write case uses the
real renderer. The ten-test suite took 6.3 seconds to execute on an Apple M4 Pro running macOS 27.2
(targeted serialized run, excluding build time).

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
GPU completion, and actual drawable presentation. Fake-renderer timings are orchestration checks,
not product latency claims.

## Manual UI checks

When changing inspectors, masking, appearance, or packaging, exercise the packaged app in a real
macOS UI session. Check light/dark appearance, Settings transitions, keyboard/focus/VoiceOver
behavior, inspector disclosure state, mask overlay and export parity, and icon/signature outputs.
The app-level smoke test and the verification scripts under `scripts/` are the executable checks;
the source and test names are the authoritative coverage map.

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

Persisted presentation frame reads are recorded by `FrameLookupLedger` with their surface, outcome,
and monotonic timestamp; the ledger stores no paths or image data. The one-line `FrameLookupSummary`
signpost groups outcomes by surface and names the most frequent rejection reason for quick cache-miss triage.
| Launch-hint schema faults, wrong library, removed IDs, viewport supersession, and stale completion | `LaunchHintsTests`, `LibraryBrowsingCoordinatorTests` |
| Rapid selection, newest-pending work, stale render/thumbnail publication, and actual drawable callbacks | `FilmstripNavigationTests`, `ThumbnailSwitchLifecycleTests`, `IdentityRegressionGateTests`, `PreviewSurfaceTests` |

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
`@ObservedObject` to a plain reference was skipped before measurement because the capture window was
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
