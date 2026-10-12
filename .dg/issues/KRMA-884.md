---
id: KRMA-884
title: Extract package folder, removable-media and Photos-drop import orchestration from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A coordinator owns folder, removable-media, and Photos-drop package import orchestration.
      result: pass
      notes: PackageSourceImportCoordinator owns these workflows and uses a narrow destination.
    - criterion: Focused tests cover operation-ID supersession, imported and duplicate-only success, failure, and security-scoped release when no files are found.
      result: pass
      notes: Focused coordinator tests cover each case.
    - criterion: AppViewModel keeps thin forwarders, with behavior unchanged.
      result: pass
    - criterion: Architecture ownership and the AppViewModel line-count guard are updated.
      result: pass
    - criterion: swift build and scripts/ci-tests.sh fast pass; serial runs only if render/UI paths are touched.
      result: pass
      notes: Build and fast lane passed; render/UI paths were not changed.
    - criterion: No display-bound capture benchmark is run.
      result: pass
  checks_run:
    - swift build — passed (exit 0)
    - scripts/ci-tests.sh fast — passed (1,672 required-fast tests; exit 0)
    - git diff --check — passed (exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T18:11:15.556Z
  session: 01MV44ZKWURDGWM6BY
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T17:09:50.626Z
updated: 2026-10-11T18:11:15.559Z
blockers: []
order: zv
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T17:56:34.382Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

Child of KRMA-460. AppViewModel.swift is 5,403 lines (ceiling test: PackageSettingsTests.testAppViewModelDoesNotRegrow at 5,500). Extract workflow *ownership*, not just a file split. Keep AppViewModel the composition root and sole owner of the published EditDocument (docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference: the new type takes a narrow protocol or closures and returns value outcomes that the root applies (pattern: LookSelectionCoordinator, ExportWorkflowCoordinator). Locate code by function name; line numbers drift. Run serially with other KRMA-460 children, since they edit the same file.

## Scope
KRMA-874 was closed as stale: removable-media *selection/scan/admission* state already lives in LibraryMediaWorkflowCoordinator. What remains on the root is the package-import orchestration that follows it (~220 lines): `importRemovableMedia`, `openSourceFolder`, `supportedImageURLs(in:)`, `observePortableImport`, and the `.promises` branch of `handleDrop` (drop-directory lifecycle, `droppedPromiseTask`). These duplicate one shape: start import via LibraryImportCoordinator, observe, reload collection, open first imported/duplicate asset, report an ImportOutcomeSummary.

## Plan
Extend LibraryImportCoordinator (or add a sibling) to own that shape once, parameterized by prefix and total. It reports outcomes through a narrow destination (reload collection, open asset, present outcome, finish media-workflow import); it must not hold AppViewModel. `beginImportOperation`/`isCurrentImport` operation-ID fencing must be preserved exactly. `presentImportOutcome`/`pendingImportOutcome` (deferred while a photo is loading) stay on the root unless they move cleanly behind the destination.

## Out of scope
Photos-library import (PhotosImportCoordinator), selection/scan state, deletion.

Acceptance: (1) new/extended coordinator owns the listed state and logic; (2) focused tests that do not construct AppViewModel; (3) AppViewModel keeps thin forwarders only, with no behavior change; (4) docs/APP_ARCHITECTURE.md ownership table and the line count in its AppViewModel paragraph updated, and the PackageSettingsTests ceiling lowered to just above the new size; (5) swift build and scripts/ci-tests.sh fast pass, plus scripts/ci-tests.sh serial if render/UI paths are touched. Do not run the display-bound capture benchmarks (CLAUDE.md). Add tests for operation-ID supersession, success with imported vs duplicate-only results, failure, and security-scoped access release on the no-files path.

## Agent log

- 2026-10-11T18:11:15.556Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A coordinator owns folder, removable-media, and Photos-drop package import orchestration. (pass) — PackageSourceImportCoordinator owns these workflows and uses a narrow destination.
- [x] Focused tests cover operation-ID supersession, imported and duplicate-only success, failure, and security-scoped release when no files are found. (pass) — Focused coordinator tests cover each case.
- [x] AppViewModel keeps thin forwarders, with behavior unchanged. (pass)
- [x] Architecture ownership and the AppViewModel line-count guard are updated. (pass)
- [x] swift build and scripts/ci-tests.sh fast pass; serial runs only if render/UI paths are touched. (pass) — Build and fast lane passed; render/UI paths were not changed.
- [x] No display-bound capture benchmark is run. (pass)
Checks run:
- swift build — passed (exit 0)
- scripts/ci-tests.sh fast — passed (1,672 required-fast tests; exit 0)
- git diff --check — passed (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV44ZKWURDGWM6BY
Summary: Verification passed: implementation review and required checks are clean.
