---
id: KRMA-887
title: Extract durable edit history and snapshots from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: EditHistoryCoordinator owns durable history state and the history, restore, snapshot, and virtual-copy store operations.
      result: pass
      notes: Reviewed the narrow store protocol, closure-based root boundary, stale-reference fencing, and flush-before-restore/write behavior.
    - criterion: Focused coordinator tests use a fake store without constructing AppViewModel.
      result: pass
      notes: Fake-store coverage includes refresh, stale references, restore ordering/failure, snapshots, and virtual copies.
    - criterion: AppViewModel keeps thin forwarders and remains the published EditDocument owner.
      result: pass
      notes: Root wiring and restore sequencing remain in AppViewModel; undo/redo and applyHistoryDocument were not extracted.
    - criterion: Architecture docs and AppViewModel line-count guard reflect the extraction.
      result: pass
      notes: docs/APP_ARCHITECTURE.md reports 5,105 lines; PackageSettingsTests sets a 5,120 ceiling.
    - criterion: Required build and fast checks pass; serial runs if render or UI paths are touched.
      result: pass
      notes: Build and fast lane passed. Serial was not applicable because the change touches coordinator logic and tests, not render or UI implementation paths.
  checks_run:
    - swift build — passed (exit 0)
    - scripts/ci-tests.sh fast — passed (exit 0; 1,707 tests)
    - git diff --check — passed
  findings:
    - "Fixed during verification: a failed history read from a stale source could clear durable history state after the active source changed. Stale failures in restore, snapshot, and virtual-copy paths could also publish status to the wrong photo."
  fixes:
    - Added active-reference guards to stale error and status paths and before virtual-copy creation proceeds after the persistence flush.
    - Added a fake-store regression test proving a stale refresh failure does not clear existing history.
  verification_commits:
    - a437630268dbea13ea18ed2930d867cb910f7ceb
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T19:57:30.355Z
  session: 01MV48S0V88HU2PC22
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T17:09:55.536Z
updated: 2026-10-11T19:57:30.358Z
blockers: []
order: zzh
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T19:40:37.294Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - a437630268dbea13ea18ed2930d867cb910f7ceb
---

Child of KRMA-460. AppViewModel.swift is 5,403 lines (ceiling test: PackageSettingsTests.testAppViewModelDoesNotRegrow at 5,500). Extract workflow *ownership*, not just a file split. Keep AppViewModel the composition root and sole owner of the published EditDocument (docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference: the new type takes a narrow protocol or closures and returns value outcomes that the root applies (pattern: LookSelectionCoordinator, ExportWorkflowCoordinator). Locate code by function name; line numbers drift. Run serially with other KRMA-460 children, since they edit the same file.

## Scope
Package-backed history is root-owned (~105 lines under Undo and reset): `refreshDurableEditHistory`, `restoreEditRevision`, `saveEditSnapshot(named:)`, `createVirtualCopy`, and published state `durableEditHistory` / `durableCurrentEditRevision`. Each is an async editStore call guarded by `activeSourceReference == reference` after the await.

## Plan
Add an EditHistoryCoordinator that owns that state and the editStore I/O (history, currentRevision, selectRevision, snapshot, virtual copy), including the stale-reference guard and the persistence-flush-before-select barrier. The root supplies the active source reference, a flush closure, and an apply-restored-document closure, and keeps `undo`/`redo`/`applyHistoryDocument`/`resetPhoto` (the document restore sequencer documented in APP_ARCHITECTURE.md) untouched. Tests use a fake store: refresh ignored after the active reference changes, restore flushes first and aborts on flush failure, error paths clear state.

## Out of scope
In-memory undo/redo (EditorDocumentCoordinator), `applyHistoryDocument`, comparison-baseline reset duplication between `resetPhoto` and `applyHistoryDocument` (note as a follow-up if worthwhile).

Acceptance: (1) new/extended coordinator owns the listed state and logic; (2) focused tests that do not construct AppViewModel; (3) AppViewModel keeps thin forwarders only, with no behavior change; (4) docs/APP_ARCHITECTURE.md ownership table and the line count in its AppViewModel paragraph updated, and the PackageSettingsTests ceiling lowered to just above the new size; (5) swift build and scripts/ci-tests.sh fast pass, plus scripts/ci-tests.sh serial if render/UI paths are touched. Do not run the display-bound capture benchmarks (CLAUDE.md).


### Comment — claude @ 2026-10-11T19:40:40.216Z

Commit f841d98c. EditHistoryCoordinator owns durable history state + refresh/restore/snapshot/virtual-copy I/O (stale-ref fence, flush-before-write); AppViewModel 5,148 -> 5,117 lines, ceiling 5,150; docs updated; 11 fake-store tests. ci-tests fast passes. Serial: 2 failures in render kernels this change does not touch (ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth, MetalKernelParityTests.testHSLMixerMatchesGolden) - not verified against a clean tree. Follow-up candidate: comparison-baseline reset duplication between resetPhoto and applyHistoryDocument.

## Agent log

- 2026-10-11T19:57:30.355Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EditHistoryCoordinator owns durable history state and the history, restore, snapshot, and virtual-copy store operations. (pass) — Reviewed the narrow store protocol, closure-based root boundary, stale-reference fencing, and flush-before-restore/write behavior.
- [x] Focused coordinator tests use a fake store without constructing AppViewModel. (pass) — Fake-store coverage includes refresh, stale references, restore ordering/failure, snapshots, and virtual copies.
- [x] AppViewModel keeps thin forwarders and remains the published EditDocument owner. (pass) — Root wiring and restore sequencing remain in AppViewModel; undo/redo and applyHistoryDocument were not extracted.
- [x] Architecture docs and AppViewModel line-count guard reflect the extraction. (pass) — docs/APP_ARCHITECTURE.md reports 5,105 lines; PackageSettingsTests sets a 5,120 ceiling.
- [x] Required build and fast checks pass; serial runs if render or UI paths are touched. (pass) — Build and fast lane passed. Serial was not applicable because the change touches coordinator logic and tests, not render or UI implementation paths.
Checks run:
- swift build — passed (exit 0)
- scripts/ci-tests.sh fast — passed (exit 0; 1,707 tests)
- git diff --check — passed
Findings:
- Fixed during verification: a failed history read from a stale source could clear durable history state after the active source changed. Stale failures in restore, snapshot, and virtual-copy paths could also publish status to the wrong photo.
Fixes:
- Added active-reference guards to stale error and status paths and before virtual-copy creation proceeds after the persistence flush.
- Added a fake-store regression test proving a stale refresh failure does not clear existing history.
Verification commits:
- a437630268dbea13ea18ed2930d867cb910f7ceb
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV48S0V88HU2PC22
Summary: Independent verification passed. swift build and ci-tests fast passed; fixed stale-source failure handling with a regression test.
