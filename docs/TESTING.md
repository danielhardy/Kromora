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

`last-known-frame` mounts the shipping `ContentView` in an onscreen window, imports 30 generated grid
sources plus the selected licensed RAW into a temporary test package, and warms the actual visible
thumbnail rows before its warm grid samples. Every warm grid sample leaves Edit, waits for
`LibraryGridView` to unmount, re-enters Library, waits for a new grid mount and populated visible
cells, then forces an AppKit layout and display pass. Edit selections run through `AppViewModel`;
the first-pixel clock starts immediately before the selection call and ends at the first drawable
callback from `PreviewSurface`. Exact and stale cases emit `criteriaPassed` and assert their frame
and render-count requirements. Renderer admissions and crossfade counts are captured from the
corresponding production owners. Each output line is JSON prefixed with
`LAST_KNOWN_FRAME_BENCHMARK`; the capture summary supplies machine, OS, commit, and Release
configuration. The synchronous selection call is the measured main-actor work before its first
asynchronous task can run. The harness does not infer a presentation from a published CIImage.

The output includes separate warm grid hydration and warm Edit selection records, with source
dimensions, viewport points, backing pixels, cache state, sample count, p50/p95, drawable frame
counts, render admissions, crossfades, thumbnail swaps, layout passes, and an explicit
`criteriaPassed` result. Grid layout-pass counts represent explicit layout/display work after a
newly mounted grid has populated visible cells. The harness requires a logged-in display and skips
immediately with the window occlusion state when it is not onscreen. Its default is 30 warm samples
so p95 does not collapse to the maximum of a five-sample run. Keep the benchmark opt-in; KRMA-734
targets are unchanged.

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
| Exact/stale/missing stored frames, candidate ordering, renderer failure, and obsolete generations | `WarmReopenPresentationTests`, `PreviewPresentationCoordinatorTests`, `EmbeddedFirstFrameTests`, `PreviewCutoverTests` |
| Same-ID Look replacement and unchanged Look scans | `LUTLibraryTests`, `AppViewModelTests`, `EditedThumbnailCoordinatorTests` |
| Transactional edit plus presented geometry and rollback | `PortableLibraryPackageTests.testEditRevisionAndPresentedGeometryPublishOrRollbackTogether` |
| Packed-frame stable keys, read-window bounds, compaction, and interruptions | `ThumbnailFrameStoreTests`, `PortablePackageMaintenanceTests` |
| Launch-hint schema faults, wrong library, removed IDs, viewport supersession, and stale completion | `LaunchHintsTests`, `LibraryBrowsingCoordinatorTests` |
| Rapid selection, newest-pending work, stale render/thumbnail publication, and actual drawable callbacks | `FilmstripNavigationTests`, `ThumbnailSwitchLifecycleTests`, `IdentityRegressionGateTests`, `PreviewSurfaceTests` |

Run this matrix with `swift test`, then `scripts/ci-tests.sh fast`, `serial`, and `identity`. These
assertions establish correctness and bounded work; fake renderer timings remain orchestration data
and do not count toward the release latency budgets.

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
No target was redefined.

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

### KRMA-744 harness repair and capture attempt (2026-10-01)

The harness now waits for a new `LibraryGridView` mount after leaving Edit, waits for populated
visible thumbnails, forces layout/display work, and records a layout pass for each warm grid sample.
Edit timing starts immediately before `selectCollectionImage` and ends at the first drawable
callback. Exact and stale frame/render requirements are emitted as pass/fail and asserted. The
default is 30 samples. The initial 2026-09-30 grid p95 and Edit first-pixel timings above remain
invalid evidence; the new harness did not change any KRMA-734 budget.

The requested Release capture was attempted with the 30-sample command above on the logged-in
Apple M1 Pro MacBook Pro, macOS 27.0 build 26A428, stable Xcode 27.0, using `DSC01019.ARW`. Both the
capture wrapper and direct Release test reached the visibility guard and skipped in about eight
seconds because `window.occlusionState` was `8192` (the window had no visible bit). No latency or
frame measurements were produced. Capture summary:
`/tmp/kromora-capture-krma744/KRMA744-DSC01019-20261001-041641-summary.txt`.

An additional capture attempt on 2026-10-01 used the same command from the agent shell and rebuilt
the Release test bundle successfully. The XCTest process still could not activate its window:
`occlusionState=8192`, `isVisible=true`, `keyWindow=false`, `appActive=false`, and
`activationPolicy=0`. It skipped before producing measurements, so this run is not budget evidence.
Summary and trace: `/tmp/kromora-capture/KROMORA-last-known-frame-DSC01019-20261001-081124-summary.txt`
and `.trace`.

To complete qualification, run the same 30-sample capture from an interactive macOS session where
the XCTest-created Kromora window is onscreen, then append the output and budget results here.
