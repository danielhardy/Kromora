# Testing and profiling

The required checks are deterministic build/test lanes. Hardware, AppKit, RAW, and Instruments
work is opt-in because it needs a logged-in display or licensed local fixtures.

## Required lanes

```sh
swift build
swift test
swift build -c release
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
git diff --check
dg validate
```

`fast` covers deterministic model, coordinator, and fake-engine tests in parallel. `serial` covers
Core Image, render, and AppKit/UI-sensitive tests. `scripts/ci-tests.sh optional` runs RAW-fixture,
benchmark, and packaging checks when their inputs are available. Generated fixtures are created by
the tests and are not committed.

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
