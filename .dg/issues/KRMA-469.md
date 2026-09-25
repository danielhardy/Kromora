---
id: KRMA-469
title: "Stage 5: Re-inventory AppViewModel and update architecture documentation"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Expected root remainder is confirmed: init/wiring, load sequencer, updateDocument/applyHistoryDocument, published chrome, and shutdown."
      result: pass
      notes: MARK-by-MARK inventory in APP_ARCHITECTURE.md matches actual AppViewModel.swift MARKs verified by grep; the four remaining root task handles (semanticCoordinatorInstallTask, lutCacheInvalidationTask, droppedPromiseTask, pendingPersistenceFlush) match exactly what the file declares, with no undocumented extras.
    - criterion: docs/APP_ARCHITECTURE.md and the R5 paragraph in docs/REPOSITORY_IMPROVEMENT_PLAN.md are updated if stale.
      result: pass
      notes: New AppViewModel root inventory section added to APP_ARCHITECTURE.md with ownership table, façade list, task-handle table, and shutdown-order narrative. R5 section rewritten to remove the stale pre-extraction line-range table and the stale AppViewModel+Masking.swift 1,309-line figure, replaced with a pointer to the durable inventory.
    - criterion: Line-count trend is recorded only as supporting evidence, never as the extraction goal.
      result: pass
      notes: AppViewModel.swift (4,293) and AppViewModel+Masking.swift (172) are stated as supporting context/evidence in both docs, matching wc -l on the actual files.
    - criterion: Focused tests for each landed stage, swift build, the relevant fast CI lane, dg validate, and git diff --check pass.
      result: pass
      notes: Docs-only diff (plus one new backlog issue file); no forwarder moved, so swift build, dg validate, and git diff --check are the applicable checks per the issue brief. All three pass; dg validate shows only pre-existing unrelated model-name/context-completeness warnings.
    - criterion: This remains a documentation/review stage; no broad refactor is started here.
      result: pass
      notes: git show --stat on commit 1ecbfaa confirms zero Sources/ files changed; only docs/APP_ARCHITECTURE.md, docs/REPOSITORY_IMPROVEMENT_PLAN.md, and the new KRMA-586.md backlog child were touched. The remaining Photos-import batch state found during inventory was correctly filed as a non-blocking backlog child (KRMA-586, depends_on KRMA-469) rather than extracted here.
  checks_run:
    - "swift build: pass"
    - "dg validate: OK (only pre-existing unrelated model-name/context-completeness warnings)"
    - "git diff --check: pass"
    - "wc -l on AppViewModel.swift (4293) and AppViewModel+Masking.swift (172): matches documented figures"
    - "grep MARK/task-handle inventory in AppViewModel.swift: matches documented ownership table and task-handle table exactly"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T05:53:47.401Z
  session: 01MUGJOCEV132JSV02
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-19T16:27:26.087Z
updated: 2026-09-25T05:53:47.403Z
depends_on:
  - KRMA-465
  - KRMA-466
  - KRMA-467
  - KRMA-468
  - KRMA-564
  - KRMA-565
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/AppViewModel+Masking.swift
  docs:
    - docs/APP_ARCHITECTURE.md
    - docs/REPOSITORY_IMPROVEMENT_PLAN.md
  issues:
    - KRMA-460
    - KRMA-466
    - KRMA-467
    - KRMA-528
    - KRMA-529
    - KRMA-551
    - KRMA-552
    - KRMA-564
    - KRMA-565
  commands:
    - swift build
    - dg validate
    - git diff --check
---

Parent: KRMA-460

## Execution brief (reviewed 2026-09-23)

Do not start until KRMA-467, KRMA-564, and KRMA-565 are `done`. KRMA-466 is already done. KRMA-465 and KRMA-468 are already satisfied elsewhere; do not re-open them.

This is a documentation and inventory pass. The only code motion allowed is a Stage-0-style move of a MARK that the inventory proves is now a pure forwarder. Do not start another coordinator here.

### What the docs already say

`docs/APP_ARCHITECTURE.md` already has ownership sections for source session, preview presentation, canvas workflow (KRMA-552), library/media and `LibraryImportCoordinator` (KRMA-551), application shell, and masking (KRMA-529). The boundaries table also names `PreviewCoordinator` as the render-admission owner.

`docs/REPOSITORY_IMPROVEMENT_PLAN.md` R5 says decomposition is **partially implemented** and points at `APP_ARCHITECTURE.md` plus KRMA-521. The later “Why AppViewModel is still approximately 5,000 lines” section is a dated baseline (it still says `AppViewModel+Masking.swift` is 1,309 lines; that file is now 172 lines of forwarders). Update that paragraph so it does not send the next reader back into finished work. Keep the “shorter file is not the goal” conclusion.

### What to record

After KRMA-467, KRMA-564, and KRMA-565, re-read `AppViewModel.swift` MARK by MARK and write the resulting table into `docs/APP_ARCHITECTURE.md`:

- owner of each remaining workflow
- which root methods are sequencers (`init` / `wireCoordinators`, `load`, `updateDocument`, `applyHistoryDocument`, `shutdown`)
- which methods are one-line forwarders
- task handles still stored on the root, and why
- shutdown order, including the new thumbnail and preview-admission shutdown calls

Expected remainder, if 466 and 467 did what their briefs say: init/wiring, `load()` sequencing, the one document commit path, published chrome, export/Look dialogs, and `shutdown()`. If a large state machine is still in the root, file a new backlog child with the same shape as the KRMA-466 brief (symbols, fences, tests, out of scope). Do not extract it in this ticket.

Record the `AppViewModel.swift` line count only as supporting evidence next to the ownership table.

### Checks

- `swift build` if any forwarder file moved; otherwise a docs-only diff needs `git diff --check` and `dg validate`
- Re-run the focused suites named in KRMA-466 and KRMA-467 if this ticket moved code
- Do not claim success from line count alone

## Objective

After Stages 1–4 land, re-inventory `AppViewModel` and update the durable architecture documentation to match actual ownership.

## Ownership contract

- State owned: no new workflow state; record the resulting root boundary and any final thin-façade moves justified by completed ownership extractions.
- Admitted commands: documentation/review of remaining root methods and only façade moves justified by the completed extractions.
- Published values: document the single published active `EditDocument`, source chrome, navigation policy, and status/error presentation as root-owned.
- Revision checks: verify source/document/display fences and the one `updateDocument` commit path remain unchanged.
- Task handles: inventory remaining root task handles; assign extracted workflow handles to their collaborators or explicitly justify any root remainder.
- Shutdown behavior: document composition, cancellation, persistence flush/discard, and collaborator teardown ordering.
- Resource limits: record scheduler/cache/GPU ownership and ensure no duplicate renderer, event bus, document store, or unbounded worker was introduced.

## Scope and acceptance

- [ ] Expected root remainder is confirmed: init/wiring, load sequencer, updateDocument/applyHistoryDocument, published chrome, and shutdown.
- [ ] `docs/APP_ARCHITECTURE.md` and the R5 paragraph in `docs/REPOSITORY_IMPROVEMENT_PLAN.md` are updated if stale.
- [ ] Line-count trend is recorded only as supporting evidence, never as the extraction goal.
- [ ] Focused tests for each landed stage, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.
- [ ] This remains a documentation/review stage; no broad refactor is started here.

### Comment — cursor @ 2026-09-24T01:13:35.664Z

Triage 2026-09-23: this stays a docs/inventory pass after KRMA-466 and KRMA-467. APP_ARCHITECTURE.md already documents the finished extractions.

### Comment — codex @ 2026-09-25T05:52:58.462Z

Re-inventoried AppViewModel MARKs and documented current workflow ownership, root sequencing, façade forwarders, retained task handles, revision fences, and shutdown order in APP_ARCHITECTURE.md. Updated R5 to remove stale extraction proposals and masking line count; AppViewModel.swift is 4,293 lines and AppViewModel+Masking.swift is 172 lines (supporting evidence only). The remaining Photos import batch state is tracked in backlog child KRMA-586, dependent on this inventory. Docs-only checks: dg validate passed with existing model-name/context-completeness warnings; git diff --check passed. Commit: 1ecbfaa.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-25T05:53:47.401Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Expected root remainder is confirmed: init/wiring, load sequencer, updateDocument/applyHistoryDocument, published chrome, and shutdown. (pass) — MARK-by-MARK inventory in APP_ARCHITECTURE.md matches actual AppViewModel.swift MARKs verified by grep; the four remaining root task handles (semanticCoordinatorInstallTask, lutCacheInvalidationTask, droppedPromiseTask, pendingPersistenceFlush) match exactly what the file declares, with no undocumented extras.
- [x] docs/APP_ARCHITECTURE.md and the R5 paragraph in docs/REPOSITORY_IMPROVEMENT_PLAN.md are updated if stale. (pass) — New AppViewModel root inventory section added to APP_ARCHITECTURE.md with ownership table, façade list, task-handle table, and shutdown-order narrative. R5 section rewritten to remove the stale pre-extraction line-range table and the stale AppViewModel+Masking.swift 1,309-line figure, replaced with a pointer to the durable inventory.
- [x] Line-count trend is recorded only as supporting evidence, never as the extraction goal. (pass) — AppViewModel.swift (4,293) and AppViewModel+Masking.swift (172) are stated as supporting context/evidence in both docs, matching wc -l on the actual files.
- [x] Focused tests for each landed stage, swift build, the relevant fast CI lane, dg validate, and git diff --check pass. (pass) — Docs-only diff (plus one new backlog issue file); no forwarder moved, so swift build, dg validate, and git diff --check are the applicable checks per the issue brief. All three pass; dg validate shows only pre-existing unrelated model-name/context-completeness warnings.
- [x] This remains a documentation/review stage; no broad refactor is started here. (pass) — git show --stat on commit 1ecbfaa confirms zero Sources/ files changed; only docs/APP_ARCHITECTURE.md, docs/REPOSITORY_IMPROVEMENT_PLAN.md, and the new KRMA-586.md backlog child were touched. The remaining Photos-import batch state found during inventory was correctly filed as a non-blocking backlog child (KRMA-586, depends_on KRMA-469) rather than extracted here.
Checks run:
- swift build: pass
- dg validate: OK (only pre-existing unrelated model-name/context-completeness warnings)
- git diff --check: pass
- wc -l on AppViewModel.swift (4293) and AppViewModel+Masking.swift (172): matches documented figures
- grep MARK/task-handle inventory in AppViewModel.swift: matches documented ownership table and task-handle table exactly
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGJOCEV132JSV02
