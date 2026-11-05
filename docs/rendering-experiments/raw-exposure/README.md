# RAW exposure experiment

A standalone, reversible Core Image diagnostic. It does not use or change Kromora documents, production rendering, caches, or UI. It reproduces the neutral subset of the current graph: `CIRAWFilter`, then (for A/C) `CIExposureAdjust`, evaluated in an extended-linear Display P3 `CIContext`. No Look, masks, crop, or other creative adjustments are applied. RAW orientation is the filter's default. The mode definitions are A = decoder boost default + RGB EV, B = default boost + RAW EV, C = boost 0 + RGB EV, D = boost 0 + RAW EV. EV is applied once. Each is run at −3, −2, −1, 0, +1, +2 EV and EDR 0 and 1. EDR is the only deliberately changed decoder default besides exposure/boost. The full settings for each render are recorded in JSON; support flags should be read with the setting values. Version is deliberately not pinned.

## Run

Requires macOS 26+, Apple Silicon, a Swift toolchain with the macOS SDK, and GPU access. The sheet script additionally uses Python Pillow, which is only a diagnostic dependency, not an application dependency. The Core Image renderer may fail in a sandbox that denies GPU/decoder resources. Use an absolute original RAW path; don't commit private RAWs or derived pictures unless authorized.

```sh
cd docs/rendering-experiments/raw-exposure
mkdir -p /tmp/kromora-module-cache
CLANG_MODULE_CACHE_PATH=/tmp/kromora-module-cache swiftc -module-cache-path /tmp/kromora-module-cache -O experiment.swift -o /tmp/kromora-raw-experiment
/tmp/kromora-raw-experiment /absolute/path/to/photo.ARW "$PWD" 800
python3 contact_sheets.py "renders/photo"
CLANG_MODULE_CACHE_PATH=/tmp/kromora-module-cache swiftc -module-cache-path /tmp/kromora-module-cache -O benchmark.swift -o /tmp/kromora-raw-benchmark
/tmp/kromora-raw-benchmark /absolute/path/to/photo.ARW "$PWD/metrics/photo-benchmark.json"
```

The last renderer argument is the maximum dimension; `scaleFactor` is set on the decoder. Use separate output roots for sources with the same basename; rerunning a source overwrites its corresponding files. Rendering every graph and writing PNGs twice is intentionally expensive. Each mode has an unmodified fixed-display-transform PNG and a `matched_` PNG. The latter uses a single global gain so its sampled median linear luminance matches mode A at the **same EV and EDR**, with gains recorded per record. It is a viewing aid, not a restoration, tone curve, or metric input. Contact sheets show matched outputs at −2, 0 and +2; boost-0 neutral is therefore brightness-matched, while the unmodified PNGs preserve the actual default rendering. No automatic local matching is performed. All viewable images are 8-bit Display P3; they are not the measurement data.

JSON metrics are calculated directly from a full float RGBAf readback in extended-linear Display P3, before output conversion or display matching. Each record contains decoder state, sample dimensions, timings, channel counts at or above 1, any-channel percentage, P3 unit-cube excursions, negative/nonfinite counts, high-luminance occupied bins and local neighbor contrast, mean highlight chromaticity, and shadow luminance variance. Pairwise records compare A/B and C/D at identical positions and settings. The `>=1` threshold is an output reference, **not proof of sensor clipping**. Values outside the unit P3 cube include extended highlights, not only chromatic gamut violations. The luminance-selected distributions vary by mode and do not isolate a fixed scene region; bin count or contrast is not a count of genuinely recovered detail. Shadow variance includes image content and is not an isolated noise estimate. Alpha is excluded from pairwise statistics. Negative/NaN/infinity are counted per RGB channel except the explicitly named pixel count.

The standalone benchmark compares float-readback rendering of a materialized RGB source to a fresh RAW filter per tick at 800 pixels, plus one full-resolution RAW render. It is a proxy: it does not exercise Kromora's interactive RAW session, cache invalidation machinery, scheduling, drawable presentation, or GPU utilization. Its first-preview timing is not time to first visible frame and it has no settled-frame measurement. Use Kromora's existing window-independent render-engine benchmarks for actual app cache behavior; do not treat these numbers as product latency. Peak RSS is a process high-water mark, not per-mode GPU allocation.
