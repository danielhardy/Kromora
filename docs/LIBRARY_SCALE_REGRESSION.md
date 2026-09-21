# Package-backed library scale regression (KRMA-410)

This is the Phase 3.5 scale and concurrency gate. It uses the deterministic generator from KRMA-389
at 1,000, 10,000, and 100,000 assets, writes only membership summaries and a local index, and then
measures the package-backed query path. The fixture deliberately has no asset records, originals,
or thumbnail files in the package; an accidental eager read therefore fails loudly.

Since KRMA-519 the fixture also measures the production path: each sample opens a real
`PortableLibrarySession` on a private copy of the fixture package and publishes the browsing
projection exactly as AppViewModel launch (`production-launch`) and reload (`production-reload`)
do, with a read observer gating `production-record-reads` to zero. The copy keeps lease
acquisition and disposable-index writes off the shared fixture. This closes the KRMA-519 false
assurance gap where the benchmark measured only the bare index session while production
materialized every record.

## KRMA-519 production-path probe (first capture)

One sample at 1,000 assets on Mac16,11 / macOS 27.0, 2026-09-21: `production-launch` 240.49 ms
(real session open: manifest, membership, writer lease, disposable projection),
`production-reload` 85.97 ms (browsing projection over all 1,000 summaries), and
`production-record-reads` 0. The pre-519 production path opened one record per asset plus one
full-file fingerprint hash per original at launch; the committed KRMA-410 table above still
reports the bare index-session capture. Promote these rows into the comparison table with a
three-sample 10k/100k run before closing KRMA-519.

Run it only in the optional benchmark lane:

```sh
KROMORA_LIBRARY_SCALE_BENCHMARK=1 \
KROMORA_LIBRARY_SCALE_SAMPLES=3 \
KROMORA_LIBRARY_SCALE_OUTPUT=/tmp/kromora-library-scale.json \
swift test --no-parallel \
  --filter LibraryScaleRegressionPerformanceTests/testPackageBackedLargeLibraryRegressionBenchmark
```

The JSON report has schema version 1 and uses the same metric names, units, and nearest-rank p95 and
p99.9 definition as [`LIBRARY_PACKAGE_BASELINE.md`](LIBRARY_PACKAGE_BASELINE.md). The report also
includes the 100,000-asset scheduler/package-writer result. The always-on tombstone test is in the
`LibraryQueryControllerTests` suite and does not require the benchmark environment variable.

## Captured comparison

The baseline values below are the committed KRMA-389 capture on the M1 Pro. The package-backed
capture is one completed sample from 2026-09-13 on the same MacBookPro18,3 / Apple M1 Pro. With one
sample, nearest-rank p95 and p99.9 are necessarily equal; rerun with
`KROMORA_LIBRARY_SCALE_SAMPLES=3` when a multi-sample decision is needed. The disk type was
unavailable from `diskutil` in this runner.

| Scale | Metric | KRMA-389 baseline p95 / p99.9 | KRMA-410 p95 / p99.9 | Unit |
| ---: | --- | ---: | ---: | --- |
| 1,000 | warm launch | 335.33 / 335.33 | 19.00 / 19.00 | ms |
| 1,000 | first-page delivery | 270.94 / 270.94 | 19.00 / 19.00 | ms |
| 1,000 | filter | 1.30 / 1.30 | 0.59 / 0.59 | ms |
| 1,000 | scroll | 21.14 / 21.14 | 5.03 / 5.03 | ms |
| 1,000 | memory footprint | 15,663,104 / 15,663,104 | 737,280 / 737,280 | bytes |
| 1,000 | decoded-thumbnail count | 60 / 60 | 60 / 60 | count |
| 1,000 | interactive preview submission | 0.48 / 0.48 | 0.50 / 0.50 | ms |
| 10,000 | warm launch | 7,915.10 / 7,915.10 | 172.99 / 172.99 | ms |
| 10,000 | first-page delivery | 2,658.99 / 2,658.99 | 172.99 / 172.99 | ms |
| 10,000 | filter | 12.58 / 12.58 | 4.73 / 4.73 | ms |
| 10,000 | scroll | 118.63 / 118.63 | 52.10 / 52.10 | ms |
| 10,000 | memory footprint | 106,348,544 / 106,348,544 | 3,227,648 / 3,227,648 | bytes |
| 10,000 | decoded-thumbnail count | 60 / 60 | 60 / 60 | count |
| 10,000 | interactive preview submission | 0.38 / 0.38 | 0.55 / 0.55 | ms |
| 100,000 | warm launch | 6,989.94 / 6,989.94 | 1,746.79 / 1,746.79 | ms |
| 100,000 | first-page delivery | 6,989.94 / 6,989.94 | 1,746.79 / 1,746.79 | ms |
| 100,000 | filter | 115.90 / 115.90 | 52.15 / 52.15 | ms |
| 100,000 | scroll | 1,140.79 / 1,140.79 | 506.19 / 506.19 | ms |
| 100,000 | memory footprint | 505,020,416 / 505,020,416 | 32,161,792 / 32,161,792 | bytes |
| 100,000 | decoded-thumbnail count | 60 / 60 | 60 / 60 | count |
| 100,000 | interactive preview submission | 0.43 / 0.43 | 0.51 / 0.51 | ms |

The package path's materialization instrumentation is bounded by the returned page: at 100,000
assets it returns at most 60 `LibraryQueryItem` values, reports zero observable `PhotoAsset` objects,
and decodes only those 60 requested page thumbnails. Filtering, sorting, and UUID selection operate
on `LibraryIndexEntry` summaries; they do not open asset records or leave the index.

The benchmark also enqueues 32 real package edit revisions through the shared scheduler while an
active editor is running. The acceptance gate is `maxConcurrentPackageWriters == 1`, all 32 revisions
committed, the editor starting while package I/O is active, and a positive package-I/O yield count.
The existing `LibraryDeletionTests/testReferencedDeletionRemovesEditsAndDoesNotReturnAfterRescan`
and `LibraryQueryControllerTests/testIndexProjectionExcludesTombstonesAndKeepsSelectionUUIDBased`
remain the KRMA-371 deletion regressions.
