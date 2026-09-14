---
id: KRMA-424
title: Preserve per-photo LUT state across navigation and relaunch
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Applying a Look/LUT remains associated with the correct photo when navigating away and back.
      result: pass
      notes: AppViewModel now selects persistence identity by source kind; navigation and in-memory edit sessions remain photo-scoped, including referenced files with identical bytes.
    - criterion: Save, reload, and relaunch restore the same LUT identity and intensity for that photo.
      result: pass
      notes: LUTWorkflowTests verifies durable destination state before relaunch and restores LUT identity/intensity after relaunch.
    - criterion: A late load or thumbnail completion cannot overwrite the LUT with another photo or a default document.
      result: pass
      notes: Existing source-revision, asset, source-reference, and thumbnail generation fences remain active; EditPersistenceIntegrationTests late-store and ThumbnailSwitchLifecycleTests stale-completion coverage pass.
    - criterion: The test verifies the persisted document and the active presentation after each navigation/relaunch boundary.
      result: pass
      notes: Copy/paste asserts the persisted destination document before relaunch; navigation/relaunch tests assert active source, LUT identity, and intensity.
    - criterion: Focused LUT workflow tests pass repeatedly and full serial/fast lanes no longer report this failure.
      result: pass
      notes: LUTWorkflowTests 7/7 and lifecycle neighbors 31/31 pass; serial lane 375/375 and fast lane 1000/1000 pass.
  checks_run:
    - swift test --filter LUTWorkflowTests (7/7 passed)
    - swift test --no-parallel --filter LUTWorkflowTests|ThumbnailSwitchLifecycleTests|EditPersistenceIntegrationTests (31/31 passed)
    - scripts/ci-tests.sh serial (375/375 passed)
    - scripts/ci-tests.sh fast (1000/1000 passed)
    - dg validate --json (passed; existing model/context warnings only)
    - git diff --cached --check (passed)
  findings: []
  fixes: []
  verification_commits:
    - f068372
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T17:27:32.753Z
  session: 01MU02NQFCKNJCT11V
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - lut
  - persistence
created: 2026-09-13T15:50:11.472Z
updated: 2026-09-13T17:27:32.755Z
order: zzzzzzq
board: product
commits:
  - f068372
---

## Objective

Preserve a photo Look/LUT across navigation and relaunch without losing the durable per-photo association.

## Evidence

The full serial run on 2026-09-13 failed:
- LUTWorkflowTests/testLUTSurvivesNavigationAndRelaunchForItsPhoto
- The failure was an XCTAssertTrue at Tests/KromoraKitTests/LUTWorkflowTests.swift:74.

## Acceptance criteria

- Applying a Look/LUT remains associated with the correct photo when navigating away and back.
- Save, reload, and relaunch restore the same LUT identity and intensity for that photo.
- A late load or thumbnail completion cannot overwrite the LUT with another photo or a default document.
- The test verifies the persisted document and the active presentation after each navigation/relaunch boundary.
- Focused LUT workflow tests pass repeatedly and the full serial/fast lanes no longer report this failure.

## Verification

Run the named regression and complete LUTWorkflow/navigation neighbors repeatedly, then the full serial and fast CI lanes.

## Agent log

- 2026-09-13T17:27:32.753Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Applying a Look/LUT remains associated with the correct photo when navigating away and back. (pass) — AppViewModel now selects persistence identity by source kind; navigation and in-memory edit sessions remain photo-scoped, including referenced files with identical bytes.
- [x] Save, reload, and relaunch restore the same LUT identity and intensity for that photo. (pass) — LUTWorkflowTests verifies durable destination state before relaunch and restores LUT identity/intensity after relaunch.
- [x] A late load or thumbnail completion cannot overwrite the LUT with another photo or a default document. (pass) — Existing source-revision, asset, source-reference, and thumbnail generation fences remain active; EditPersistenceIntegrationTests late-store and ThumbnailSwitchLifecycleTests stale-completion coverage pass.
- [x] The test verifies the persisted document and the active presentation after each navigation/relaunch boundary. (pass) — Copy/paste asserts the persisted destination document before relaunch; navigation/relaunch tests assert active source, LUT identity, and intensity.
- [x] Focused LUT workflow tests pass repeatedly and full serial/fast lanes no longer report this failure. (pass) — LUTWorkflowTests 7/7 and lifecycle neighbors 31/31 pass; serial lane 375/375 and fast lane 1000/1000 pass.
Checks run:
- swift test --filter LUTWorkflowTests (7/7 passed)
- swift test --no-parallel --filter LUTWorkflowTests|ThumbnailSwitchLifecycleTests|EditPersistenceIntegrationTests (31/31 passed)
- scripts/ci-tests.sh serial (375/375 passed)
- scripts/ci-tests.sh fast (1000/1000 passed)
- dg validate --json (passed; existing model/context warnings only)
- git diff --cached --check (passed)
Findings:
- None
Fixes:
- None
Verification commits:
- f068372
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU02NQFCKNJCT11V
Summary: Preserved per-photo LUT identity across navigation, reload, and relaunch; added identical-referenced-photo and durable copy/paste regressions.
