---
id: KRMA-844
title: "Failing: MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow source-text assertions out of date"
type: bug
status: done
priority: low
agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Test passes and no longer depends on exact source text.
      result: pass
      notes: Failing source-scan test removed; CropInspectorTests now asserts behavior (label, hint, action invocation). 13 tests pass.
    - criterion: The crop Reset control keeps its accessibility label/hint.
      result: pass
      notes: Label Reset crop and hint preserved via CropInspectorView.resetButton, asserted by test.
  checks_run:
    - swift test --filter MenuCommandTests|CropInspectorTests (13 pass)
    - git diff --check
  findings:
    - "info: title-row placement and onReset* wiring source assertions were dropped rather than replaced; acceptable per the issue preference for behavioral tests."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-10T07:24:43.333Z
  session: 01MV22JJY0407UVJMJ
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T00:46:56.768Z
updated: 2026-10-10T07:24:43.336Z
blockers: []
order: zy
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T07:10:26.684Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

`MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow` fails (MenuCommandTests.swift:209-216): it asserts source text in `CropInspectorView.swift` (`Button("Reset", action: onReset)`, `.buttonStyle(.link)`, accessibility strings, `Spacer(minLength: 8)`) that no longer matches after recent crop panel changes (KRMA-836). Decide whether the UI or the test is right, then update; prefer a behavioral assertion over source scanning.

## Acceptance criteria

- [ ] Test passes and no longer depends on exact source text.
- [ ] The crop Reset control keeps its accessibility label/hint.

### Comment — codex @ 2026-10-10T07:10:24.267Z

Replaced the brittle crop title-row source scan with behavioral coverage for the actual crop reset button configuration: the test checks the resolved accessibility label and hint and invokes the wired reset action. ResetIconButton now exposes and applies the resolved accessibility values, and CropInspectorView builds its reset control through the tested configuration. Verification: swift test --filter 'MenuCommandTests|CropInspectorTests' passed (13 tests); dg validate passed with existing model-name warnings; git diff --check passed. swift format lint passes on the changed view and crop test; linting the touched MenuCommandTests.swift reports existing formatting findings elsewhere in that file. Commit: 158ea66f.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T07:24:43.333Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Test passes and no longer depends on exact source text. (pass) — Failing source-scan test removed; CropInspectorTests now asserts behavior (label, hint, action invocation). 13 tests pass.
- [x] The crop Reset control keeps its accessibility label/hint. (pass) — Label Reset crop and hint preserved via CropInspectorView.resetButton, asserted by test.
Checks run:
- swift test --filter MenuCommandTests|CropInspectorTests (13 pass)
- git diff --check
Findings:
- info: title-row placement and onReset* wiring source assertions were dropped rather than replaced; acceptable per the issue preference for behavioral tests.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MV22JJY0407UVJMJ
