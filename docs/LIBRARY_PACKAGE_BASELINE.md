# Folder-backed library baseline (KRMA-395)

This is the frozen pre-package baseline for the current `ImageCollection` folder-backed library and
the `AppViewModel` interactive preview submission path. It was captured on 2026-09-12 from commit
`d4ef55b5df9c0375899db682a6a5fca857823125`, before the package/index phases begin.

## Reproduction

The lane is opt-in because it creates 1,000, 10,000, and 100,000 temporary JPEGs and can take a few
minutes:

```sh
KROMORA_TEST_ISOLATION=1 \
KROMORA_LIBRARY_BASELINE_BENCHMARK=1 \
KROMORA_LIBRARY_BASELINE_SAMPLES=3 \
KROMORA_LIBRARY_BASELINE_OUTPUT=/tmp/kromora-library-baseline.json \
swift test --no-parallel \
  --filter LibraryFolderBaselinePerformanceTests/testCurrentFolderBackedLibraryBaseline
```

The JSON report has a stable schema (`schemaVersion: 1`) and is printed between
`LIBRARY_BASELINE_REPORT_BEGIN/END`. `KROMORA_LIBRARY_BASELINE_SAMPLES` defaults to 3; the committed
capture below used one completed sample because this runner could not retain two successive 100k
models without terminating the test process. For a finite sample set, p95 and p99.9 use the
nearest-rank definition `sorted[ceil(p * n) - 1]`; with one sample both are necessarily that sample.

## Environment and method

| Field | Capture |
| --- | --- |
| Machine class | MacBookPro18,3 (Apple M1 Pro) |
| Memory | 16 GB |
| macOS | 26.6.2 |
| Disk | APFS, Apple Fabric protocol; `Media Type: Generic` (SSD/NVMe not exposed by `diskutil`) |
| Swift | 6.3.3, arm64-apple-macosx26.0 |
| Synthetic seed | `0x4B52_4D41_3339_34` |
| First page | 60 assets; the current loader publishes 32-item discovery batches |
| Thumbnail window | Request first 60 assets, wait for all 60 decoded thumbnails |
| Scroll | Request the next 60 assets and time until the first new thumbnail decodes |
| Memory | Resident task footprint delta from immediately before collection creation through the retained scale model |
| Preview | Public `AppViewModel.openImage(url:)` on the first generated JPEG, then one interactive document submission to the injected `FakeRenderEngine`; this measures submission-to-renderer admission, not GPU pixels |

The folder loader’s first-page and warm-launch timings at 1k/10k run through the shipped recursive
discovery path. At 100k, the shipped loader retains the complete discovery array and then performs
main-actor deferred metadata lookups over the growing item array; on this machine an unbounded
100k attempt exceeded 1 GB and terminated before a stable batch barrier. The 100k row therefore uses
the harness’s bounded current-`ImageCollection.Item` materialization mode, with real generated URLs
for thumbnail decoding. Its memory/filter/scroll/count values are valid eager-object baselines;
its warm/first-page values are a bounded lower-level materialization baseline and must not be
mistaken for a paged-loader result.

## Frozen measurements

Times are milliseconds, memory is resident bytes, and counts are item/thumbnail counts. `p999` is
p99.9.

| Scale | Method | Metric | Samples | p95 | p99.9 |
| ---: | --- | --- | ---: | ---: | ---: |
| 1,000 | folder loader | warm launch | 1 | 335.33 | 335.33 |
| 1,000 | folder loader | first-page delivery | 1 | 270.94 | 270.94 |
| 1,000 | folder loader | filter | 1 | 1.30 | 1.30 |
| 1,000 | folder loader | scroll | 1 | 21.14 | 21.14 |
| 1,000 | folder loader | memory footprint (bytes) | 1 | 15,663,104 | 15,663,104 |
| 1,000 | folder loader | decoded-thumbnail count | 1 | 60 | 60 |
| 1,000 | folder loader | interactive preview submission | 1 | 0.48 | 0.48 |
| 10,000 | folder loader | warm launch | 1 | 7,915.10 | 7,915.10 |
| 10,000 | folder loader | first-page delivery | 1 | 2,658.99 | 2,658.99 |
| 10,000 | folder loader | filter | 1 | 12.58 | 12.58 |
| 10,000 | folder loader | scroll | 1 | 118.63 | 118.63 |
| 10,000 | folder loader | memory footprint (bytes) | 1 | 106,348,544 | 106,348,544 |
| 10,000 | folder loader | decoded-thumbnail count | 1 | 60 | 60 |
| 10,000 | folder loader | interactive preview submission | 1 | 0.38 | 0.38 |
| 100,000 | bounded current-item materialization | warm launch | 1 | 6,989.94 | 6,989.94 |
| 100,000 | bounded current-item materialization | first-page delivery | 1 | 6,989.94 | 6,989.94 |
| 100,000 | bounded current-item materialization | filter | 1 | 115.90 | 115.90 |
| 100,000 | bounded current-item materialization | scroll | 1 | 1,140.79 | 1,140.79 |
| 100,000 | bounded current-item materialization | memory footprint (bytes) | 1 | 505,020,416 | 505,020,416 |
| 100,000 | bounded current-item materialization | decoded-thumbnail count | 1 | 60 | 60 |
| 100,000 | bounded current-item materialization | interactive preview submission | 1 | 0.43 | 0.43 |

## Interpretation and guardrails

- The current folder implementation eagerly materializes every discovered asset; the 100k bounded
  row retains 100,000 observable `Item` objects while only 60 source thumbnails are decoded.
- The 10k warm-launch cost is already 7.9 s, while filtering remains 12.6 ms; later package/index
  work must preserve filter semantics while removing the scale-dependent launch/materialization
  cost.
- Interactive preview submission is below the one-frame p99.9 stall budget in this fake-renderer
  orchestration measurement. It is not a claim about real GPU first-visible latency; a real-display
  or Instruments lane is required for that.
- Later comparisons must report the same seven metric names, units, scale sizes, environment, and
  sample counts. Any change to the 100k method must be called out explicitly rather than compared
  as if it were the folder-loader path.
