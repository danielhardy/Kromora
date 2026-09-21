# Package-backed library scale regression (KRMA-410)

This is the Phase 3.5 scale and concurrency gate. It uses the deterministic generator from KRMA-389
at 1,000, 10,000, and 100,000 assets, writes only membership summaries and a local index, and then
measures the package-backed query path. The fixture deliberately has no asset records, originals,
or thumbnail files in the package; an accidental eager read therefore fails loudly.

Since KRMA-519 the fixture also measures the production path: each sample opens a real
`PortableLibrarySession` on a private copy of the fixture package and walks the exact
AppViewModel launch sequence — session open (`production-launch`), first query page via
`browsingWindow(pageIndex: 0)` (`production-reload`), first grid frame through the real
`ImageCollection` window adapter (`production-first-grid`), and one delta-based library-state
write followed by reload (`production-mutation-reload`) — with a read observer gating
`production-record-reads` to zero and a page-size bound gating retained Items. The copy keeps
lease acquisition and disposable-index writes off the shared fixture. This closes the KRMA-519
false assurance gap where the benchmark measured only the bare index session while production
materialized every record (slice 1) and then every `PhotoAsset`+`Item` (slice 2 windows to the
first page; further pages fault in on scroll/selection via `browsingWindow`/`appendPortableWindow`
with the query controller as the single filter/sort/selection authority).

## KRMA-519 production-path probe (windowed; slice 3)

Slice 3 promotes the windowed production path into the comparison table with a three-sample
run at 1k/10k/100k on 2026-09-21 (Mac16,11, macOS 27.0, disk unavailable from `diskutil`,
Apple Swift 6.4). With three samples the documented nearest-rank p95 and p99.9 are both the
maximum, so each cell below is a single p95 / p99.9 value (ms, except record reads in counts).

| Scale | production-launch | production-reload | production-first-grid | production-mutation-reload | production-record-reads |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 281.98 / 281.98 | 44.71 / 44.71 | 17.21 / 17.21 | 45.71 / 45.71 | 0 / 0 |
| 10,000 | 2,089.18 / 2,089.18 | 67.63 / 67.63 | 16.17 / 16.17 | 87.86 / 87.86 | 0 / 0 |
| 100,000 | 21,300.04 / 21,300.04 | 335.16 / 335.16 | 17.02 / 17.02 | 323.02 / 323.02 | 0 / 0 |

First-grid time is flat across scales: retained `Item` objects stay bounded by the page size
(500) while `totalCount` proves the full library is addressable, pages preserve stable identity
with zero overlapping IDs, and filter/sort/selection run in the query controller without opening
records (`LibraryBrowsingProjectionTests`, `LibraryWindowedBrowsingTests`). Launch is dominated
by the one-time disposable projection build from membership shards plus the index write; reload
is the steady-state paging cost. The pre-519 production path opened one record per asset plus
one full-file fingerprint hash per original at launch.

Earlier slices: slice 1 (full browsing projection, 1k) measured `production-launch` 240.49 ms,
`production-reload` 85.97 ms, 0 reads; slice 2 narrowed launch/reload to the first query page
with stable `portable:<uuid>` identity. Slice 3 additionally routes grid keyboard stepping
(`selectNext/PreviousPortableInGrid`) through the controller authority, fires the record-read
observer on the `resolveEmbeddedSourceURL` record fallback so the zero-read gate is honest, and
hardens launch/reload into the first-grid and mutation-reload rows above.

Known follow-up (pre-existing, not a 519 regression): `PortablePackageImportCatalog` builds its
duplicate-detection map by opening every asset record, and the scale fixture carries no records
by design, so an import against the fixture copy throws instead of quietly materializing.
Import-time catalog reads need hash-index work tracked separately; the mutation-reload row above
proves the post-mutation reload path stays at zero reads.

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
