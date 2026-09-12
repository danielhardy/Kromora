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

## Packed thumbnail spike (KRMA-396)

The packed-thumbnail prototype is isolated in the test target at
`Tests/KromoraKitTests/Support/PackedThumbnailPrototype.swift`; it is not imported by any shipping
target and does not alter thumbnail generation, deletion, or import behavior. Reproduce the
benchmark with:

```sh
KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 \
KROMORA_PACKED_THUMBNAIL_OUTPUT=/tmp/kromora-packed-thumbnail.json \
swift test --no-parallel \
  --filter PackedThumbnailPerformanceTests/testPackedByShardComparisonAtAllSupportedScales
```

The comparison uses the same deterministic synthetic library as the folder baseline. Every asset
is initially materialised as a thumbnail so the file-count result represents the upper bound. The
regeneration subset is exactly the generator's `needsThumbnailGeneration` set (about 35% of the
assets), and deletion removes every tenth asset before compaction. The current layout writes one
`.thumb` file per asset. The packed layout writes a single persisted offset index and up to 256
`xx.pack` files; lookup validates the offset and reads only the indexed byte range. Cold scan is a
fresh open followed by index/offset validation. The capture below is one Debug-build sample on the
same MacBookPro18,3 / Apple M1 Pro / macOS 26.6.2 environment used for the baseline above, recorded
2026-09-12; times are milliseconds except lookup, which is microseconds per single fetch.

| Scale | Files current / packed | Cold scan current / packed | Lookup current / packed | Regeneration current / packed | Compaction current / packed | Packed bytes before → after | Current bytes after deletion |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 1,000 / 257 | 3.31 / 8.61 | 36.74 / 61.54 | 95.86 / 26.18 | 3.32 / 172.77 | 1,588,080 → 1,100,481 | 985,500 |
| 10,000 | 10,000 / 257 | 36.31 / 28.79 | 42.37 / 62.47 | 1,028.12 / 312.39 | 33.35 / 770.45 | 15,957,661 → 11,017,832 | 9,855,000 |
| 100,000 | 100,000 / 257 | 387.16 / 228.88 | 64.20 / 71.18 | 14,083.52 / 3,106.28 | 459.94 / 8,080.04 | 159,535,412 → 110,274,456 | 98,550,000 |

### Decision

**Recommendation: adopt packed thumbnails by shard for the package format, with compaction as
low-priority maintenance.** At the 100,000-asset target, the prototype reduces thumbnail files
from 100,000 to 257, improves fresh cold scan by about 41%, and reduces the measured regeneration
subset from 14.1 s to 3.1 s. Warm single-thumbnail lookup remains in the same range in this
prototype (64.20 µs per-file versus 71.18 µs packed). These are the deciding scale metrics because file count
drives filesystem/backup/indexing overhead and regeneration is a common write path.

The tradeoff is explicit: packed compaction is a maintenance rewrite (8.1 s at 100k versus 0.46 s
for the per-file deletion/scan comparator), and packed storage is slower at the 1k cold/lookup
sample. Compaction must therefore remain cancellable, serialized, and below editor/visible-thumbnail
work; it must never be part of launch or a thumbnail lookup. The spike's deterministic tests cover
missing keys, duplicate replacement, stale offsets, deleted entries, bounded lookup reads, and
compaction verification that live data survives with no dangling offsets.
