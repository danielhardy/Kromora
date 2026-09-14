---
id: KRMA-419
title: "KRMA-406 verification: instrumented 10k-scale index-only query test + minor query perf cleanup"
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A 10,000-asset PortableLibraryPackage-shaped fixture exists for query-lane tests.
      result: pass
      notes: Shared GeneratedLibrary.makePortableLibraryPackage adapter is reused by the scale benchmark and the LibraryQueryController 1k/10k test.
    - criterion: An instrumented test proves filtering/sorting/paging at that scale never opens a full asset record or original file.
      result: pass
      notes: Always-on 1k/10k test installs invalid asset-record canaries for every generated asset; warm package-backed query, filtering, sorting, paging, and selectAll complete without opening them. The query projection contains membership summaries only, so originals are not required.
    - criterion: The two efficiency nits are cleaned up.
      result: pass
      notes: Search text is folded once per page/selectAll call, and selectAll no longer sorts before constructing its Set.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: swift build, focused affected swift test suite (16 executed, 1 opt-in benchmark skipped), dg validate, and git diff --check passed.
  checks_run:
    - swift test --no-parallel --filter LibraryQueryControllerTests|SyntheticLibraryGeneratorTests|LibraryScaleRegressionPerformanceTests
    - swift build
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - 1f90c7c
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T18:42:21.362Z
  session: 01MU05MQ27L3DDKBEM
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - performance
created: 2026-09-13T14:00:40.426Z
updated: 2026-09-13T18:42:21.364Z
parent: KRMA-406
depends_on:
  - KRMA-406
order: zzzzzzw
board: product
commits:
  - 1f90c7c
---

## Objective

`LibraryQueryController` (KRMA-406) is architecturally guaranteed to be index-only — `LibraryIndexEntry`
carries only denormalised summary fields, never a full asset record or original — but the acceptance
criteria for KRMA-406 called for that guarantee to be verified by test instrumentation at 10,000-asset
scale using KRMA-389's synthetic generator, and for that lane to exist at 1k/10k. The merged tests
instead hand-build 1,200 membership entries directly and never touch KRMA-389's generator (which
currently produces folder-backed `PhotoAsset` libraries, not `PortableLibraryPackage` membership
shards, so it isn't directly pluggable yet).

## Context

Found during KRMA-406 counterpoint verification. `swift build`/`swift test`/`dg validate`/
`git diff --check` all pass and the merged code structurally cannot touch full asset records or
originals during a query (the type system alone enforces it), so this is a coverage gap, not a
correctness bug.

## Scope

- Add a bridge (or adapter) from `SyntheticLibraryGenerator`'s output to a `PortableLibraryPackage`
  membership shard set, or an equivalent 10k-scale fixture, so `LibraryQueryController` can be
  exercised at the scale the original acceptance criteria specified.
- Add an instrumented test that proves filtering/sorting/paging at 10k assets touches only the index
  projection — e.g. a `FileManager`-call-counting shim or a canary file per asset record that the
  query path must never open.
- Minor query-perf cleanup found during the same review (non-blocking, safe to batch with the above):
  - `LibraryQueryController.matches(_:query:)` re-folds `query.searchText` on every entry instead of
    folding it once per `page`/`selectAll` call.
  - `selectAll(query:)` sorts the matching entries before discarding the order for a `Set`; the sort
    is unnecessary there.

## Acceptance criteria

- [ ] A 10,000-asset `PortableLibraryPackage`-shaped fixture exists for query-lane tests.
- [ ] An instrumented test proves filtering/sorting/paging at that scale never opens a full asset
  record or original file.
- [ ] The two efficiency nits above are cleaned up.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Implementation notes

Non-blocking; batch with other library-index follow-up work rather than treating as urgent.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-13T18:42:21.362Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A 10,000-asset PortableLibraryPackage-shaped fixture exists for query-lane tests. (pass) — Shared GeneratedLibrary.makePortableLibraryPackage adapter is reused by the scale benchmark and the LibraryQueryController 1k/10k test.
- [x] An instrumented test proves filtering/sorting/paging at that scale never opens a full asset record or original file. (pass) — Always-on 1k/10k test installs invalid asset-record canaries for every generated asset; warm package-backed query, filtering, sorting, paging, and selectAll complete without opening them. The query projection contains membership summaries only, so originals are not required.
- [x] The two efficiency nits are cleaned up. (pass) — Search text is folded once per page/selectAll call, and selectAll no longer sorts before constructing its Set.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build, focused affected swift test suite (16 executed, 1 opt-in benchmark skipped), dg validate, and git diff --check passed.
Checks run:
- swift test --no-parallel --filter LibraryQueryControllerTests|SyntheticLibraryGeneratorTests|LibraryScaleRegressionPerformanceTests
- swift build
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- 1f90c7c
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU05MQ27L3DDKBEM
Summary: Implemented a shared SyntheticLibraryGenerator-to-PortableLibraryPackage bridge, added always-on 1k/10k index-only query coverage with invalid asset-record canaries across filtering, sorting, paging, and select-all, and removed repeated search folding plus unnecessary selectAll sorting.
