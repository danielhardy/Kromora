---
id: KRMA-469
title: "Stage 5: Re-inventory AppViewModel and update architecture documentation"
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-19T16:27:26.087Z
updated: 2026-09-24T15:19:44.586Z
depends_on:
  - KRMA-465
  - KRMA-466
  - KRMA-467
  - KRMA-468
  - KRMA-564
  - KRMA-565
blockers: []
order: x
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
