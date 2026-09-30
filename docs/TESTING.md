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
remain generated at test time. Licensed RAW / non-redistributable camera files still stay outside
the checkout via `KROMORA_RAW_FIXTURE_DIR`.

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

Use a licensed RAW outside the checkout and set `KROMORA_RAW_FIXTURE_DIR` as required by the
specific test. The real drawable benchmark requires a logged-in display:

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
```

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
