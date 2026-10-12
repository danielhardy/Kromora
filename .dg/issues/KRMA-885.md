---
id: KRMA-885
title: Extract stored-edit adoption on photo load from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Stored-edit adoption state and decision logic are owned by a coordinator that returns value outcomes while AppViewModel remains the sole published EditDocument owner.
      result: pass
      notes: StoredEditAdoptionCoordinator owns per-source resolution and early-adoption state; AppViewModel applies its outcomes.
    - criterion: Focused tests cover the early-versus-late race and in-memory-session-wins cases without constructing AppViewModel.
      result: pass
      notes: StoredEditAdoptionCoordinatorTests cover early adoption, late adoption, edits during loading, and existing in-memory sessions.
    - criterion: AppViewModel remains a thin integration layer with no behavior change, including the LUMO-317 corrective-preview ordering rule.
      result: pass
      notes: The root applies coordinator outcomes and corrective previews still use scheduleCorrectivePreview().
    - criterion: Architecture ownership documentation and the AppViewModel line-count guard are updated to the extracted size.
      result: pass
      notes: The current source is 5,148 lines and the guard is 5,190; corrected docs/APP_ARCHITECTURE.md, which had a stale 4,293-line count.
    - criterion: Declared build and fast CI checks pass; serial CI is run only if render or UI paths are touched.
      result: pass
      notes: The change does not touch render or UI paths, so the serial lane was not required.
  checks_run:
    - swift build (passed, exit 0)
    - scripts/ci-tests.sh fast (passed, exit 0)
    - git diff --check (passed, exit 0)
    - wc -l Sources/KromoraKit/ViewModels/AppViewModel.swift (5,148 lines)
  findings:
    - docs/APP_ARCHITECTURE.md recorded 4,293 lines for AppViewModel.swift; the current file has 5,148 lines. Corrected the stale count.
  fixes:
    - Updated the AppViewModel line count in docs/APP_ARCHITECTURE.md to 5,148.
  verification_commits:
    - 0167da52c0e436e2563fcef14e350f2c23151007
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T19:31:22.288Z
  session: 01MV47UITDXH57Y7TX
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T17:09:52.038Z
updated: 2026-10-11T19:31:22.292Z
blockers: []
order: zy
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T18:22:04.900Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 0167da52c0e436e2563fcef14e350f2c23151007
---

Child of KRMA-460. AppViewModel.swift is 5,403 lines (ceiling test: PackageSettingsTests.testAppViewModelDoesNotRegrow at 5,500). Extract workflow *ownership*, not just a file split. Keep AppViewModel the composition root and sole owner of the published EditDocument (docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference: the new type takes a narrow protocol or closures and returns value outcomes that the root applies (pattern: LookSelectionCoordinator, ExportWorkflowCoordinator). Locate code by function name; line numbers drift. Run serially with other KRMA-460 children, since they edit the same file.

## Scope
When a photo loads, stored edits race with provisional/first-frame work. The adoption rules live on the root (~130 lines): `adoptStoredDocumentValues`, `adoptStoredEdits`, `applyStoredLoadStatus`, `resolveProvisionalSourceGeometry`, plus the state `earlyStoredAdoption` and `storedEditsResolvedSourceRevision`.

## Plan
Move the *decision* logic into a coordinator: given the stored EditDocumentLoadResult, the SourceSessionCoordinator.Request (hadInMemorySession, editSessionRevision, sourceRevision), current in-memory revision, and early-adoption state, return an outcome value (adopt or not, documentChanged, whether a corrective preview / deferred-settled resume / histogram re-admit / canonical frame write is needed, status banner). AppViewModel applies the outcome to document, collection crop, preview admission and thumbnails. Behavior, including the LUMO-317 rule that the corrective preview queues behind the speculative render, must not change. Cover the early-vs-late adoption race and the in-memory-session-wins cases in tests.

## Out of scope
`load`/`beginLoad` sequencing, embedded/provisional frame presentation (separate ticket), SourceSessionCoordinator internals.

Acceptance: (1) new/extended coordinator owns the listed state and logic; (2) focused tests that do not construct AppViewModel; (3) AppViewModel keeps thin forwarders only, with no behavior change; (4) docs/APP_ARCHITECTURE.md ownership table and the line count in its AppViewModel paragraph updated, and the PackageSettingsTests ceiling lowered to just above the new size; (5) swift build and scripts/ci-tests.sh fast pass, plus scripts/ci-tests.sh serial if render/UI paths are touched. Do not run the display-bound capture benchmarks (CLAUDE.md).

## Agent log

- 2026-10-11T19:31:22.288Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Stored-edit adoption state and decision logic are owned by a coordinator that returns value outcomes while AppViewModel remains the sole published EditDocument owner. (pass) — StoredEditAdoptionCoordinator owns per-source resolution and early-adoption state; AppViewModel applies its outcomes.
- [x] Focused tests cover the early-versus-late race and in-memory-session-wins cases without constructing AppViewModel. (pass) — StoredEditAdoptionCoordinatorTests cover early adoption, late adoption, edits during loading, and existing in-memory sessions.
- [x] AppViewModel remains a thin integration layer with no behavior change, including the LUMO-317 corrective-preview ordering rule. (pass) — The root applies coordinator outcomes and corrective previews still use scheduleCorrectivePreview().
- [x] Architecture ownership documentation and the AppViewModel line-count guard are updated to the extracted size. (pass) — The current source is 5,148 lines and the guard is 5,190; corrected docs/APP_ARCHITECTURE.md, which had a stale 4,293-line count.
- [x] Declared build and fast CI checks pass; serial CI is run only if render or UI paths are touched. (pass) — The change does not touch render or UI paths, so the serial lane was not required.
Checks run:
- swift build (passed, exit 0)
- scripts/ci-tests.sh fast (passed, exit 0)
- git diff --check (passed, exit 0)
- wc -l Sources/KromoraKit/ViewModels/AppViewModel.swift (5,148 lines)
Findings:
- docs/APP_ARCHITECTURE.md recorded 4,293 lines for AppViewModel.swift; the current file has 5,148 lines. Corrected the stale count.
Fixes:
- Updated the AppViewModel line count in docs/APP_ARCHITECTURE.md to 5,148.
Verification commits:
- 0167da52c0e436e2563fcef14e350f2c23151007
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV47UITDXH57Y7TX
Summary: Independent verification passed; corrected the architecture line count and recorded the verification commit.
