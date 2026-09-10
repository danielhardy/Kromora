---
id: KRMA-257
title: EditDocumentStore relink fallback does a full-table fetch+deserialize on every unedited-photo load
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Relink fallback compares locator fields without fetching documentData for every EditRecord
      result: pass
    - criterion: A matching moved record still relinks, persists its new asset ID, and restores the original document
      result: pass
    - criterion: The indexed assetID lookup and existing persistence behavior remain intact
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests (9 passed, 0 failures)
    - swift test (919 passed, 41 skipped, 0 failures)
    - swift build -c release (passed)
    - git diff --check (passed)
    - dg validate (OK; existing unrelated pickup-model and context-completeness warnings)
  findings: []
  fixes:
    - Replaced the full-row relink scan with a locator-only FetchDescriptor using assetID, sourcePath, and sourceBookmark; the matched record lazily faults documentData when its document is returned.
  verification_commits:
    - c9d449b
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-07T00:30:10.195Z
  session: 01MTQHZGIDTDTM1FFN
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-06T23:21:34.576Z
updated: 2026-09-10T12:53:51.234Z
depends_on:
  - KRMA-244
order: nm6c3gb8
board: product
commits:
  - c9d449b
---

## Finding (verification of KRMA-244 / commit c2b7851)

`EditDocumentStore.load(for:)` (Sources/LumoKit/Models/EditDocumentStore.swift:165-208) does an
indexed, O(1) fetch by `assetID` first. When that misses (the common case: opening any photo that
has never been edited) and a `url` is available, it falls back to:

```swift
guard let url = source.url,
    let record = try fetchRecords().first(where: { matches($0, url: url) })
```

`fetchRecords()` runs `modelContext.fetch(FetchDescriptor<EditRecord>())` — a full-table fetch
that faults in *every* `EditRecord` row, including its `documentData` blob (the encoded
`EditDocument`, which can hold a full adjustment list and LUT reference), just to compare
`sourcePath`/`sourceBookmark`. This runs once per unedited-photo open, unconditionally.

Under the old JSON store the equivalent scan (`records.first(where:)`) was a linear walk over an
already-fully-loaded in-memory dictionary — cheap, no disk I/O, paid once at process start. The
SwiftData version pays a fresh SQL fetch and full-row deserialization on every call, so browsing
N unedited photos in a library with M edited photos costs O(N*M) disk-backed work — exactly the
scaling problem `docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md` and this epic were created to
remove, just moved from "every edit" to "every unedited-photo open."

Not a blocker: no test in the current suite exercises this path at scale, and the epic's definition
of done doesn't include a browse-time benchmark. But it's a real regression risk against the
epic's own motivation and should be tracked as a follow-up, e.g. restrict the fallback fetch's
`propertiesToFetch` to the locator fields (`assetID`, `sourcePath`, `sourceBookmark`) so it doesn't
deserialize `documentData` for records that don't match, or index by a normalized path/bookmark
hash so the fallback doesn't need a full-table scan at all.


### Comment — codex @ 2026-09-07T00:30:09.907Z

Implemented in commit c9d449b. The relink fallback now uses SwiftData FetchDescriptor.propertiesToFetch for assetID, sourcePath, and sourceBookmark, so browsing unedited photos does not deserialize every stored documentData blob; the matched record still lazy-loads its document for relinking. Verification: focused EditDocumentStoreTests (9 passed), full swift test (919 passed, 41 skipped, 0 failures), swift build -c release, git diff --check, dg validate.

## Agent log

- 2026-09-07T00:30:10.195Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Relink fallback compares locator fields without fetching documentData for every EditRecord (pass)
- [x] A matching moved record still relinks, persists its new asset ID, and restores the original document (pass)
- [x] The indexed assetID lookup and existing persistence behavior remain intact (pass)
Checks run:
- swift test --filter EditDocumentStoreTests (9 passed, 0 failures)
- swift test (919 passed, 41 skipped, 0 failures)
- swift build -c release (passed)
- git diff --check (passed)
- dg validate (OK; existing unrelated pickup-model and context-completeness warnings)
Findings:
- None
Fixes:
- Replaced the full-row relink scan with a locator-only FetchDescriptor using assetID, sourcePath, and sourceBookmark; the matched record lazily faults documentData when its document is returned.
Verification commits:
- c9d449b
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQHZGIDTDTM1FFN
Summary: Avoid decoding every stored edit document during relink fallback scans.
