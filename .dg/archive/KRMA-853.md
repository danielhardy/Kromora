---
id: KRMA-853
title: "Failing: LightInspectorTests tone curve reset source assertion broken by ResetIconButton change"
type: bug
status: done
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LightInspectorTests passes and does not depend on the exact spelling of ResetIconButton's modifier chain.
      result: pass
      notes: The test constructs ResetIconButton and asserts its resolved accessibility label equals the reset title; it no longer asserts modifier-chain source text.
    - criterion: scripts/ci-tests.sh fast has no failures from this test.
      result: pass
      notes: Fast lane exited 0 after running all 1,618 required tests.
  checks_run:
    - "swift test --filter LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction: exit 0; 1 test passed, 0 failures."
    - "scripts/ci-tests.sh fast: exit 0; all 1,618 required tests completed."
    - Reviewed CropInspectorTests and InfoInspectorPresentationTests for the same fragile ResetIconButton modifier-chain assertion; none found.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T14:36:36.036Z
  session: 01MV3XBB0SNFVV08R8
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:41.164Z
updated: 2026-10-11T14:36:36.040Z
blockers: []
order: v
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T13:56:48.728Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

`LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction` fails on main (`Tests/KromoraKitTests/LightInspectorTests.swift:160`) and fails the fast CI lane. KRMA-846 repaired this test, but commit 158ea66f (KRMA-844) later changed `Sources/KromoraKit/Views/ResetIconButton.swift` to use `resolvedAccessibilityLabel`, so the test's source-text assertion `.accessibilityLabel(accessibilityLabel ?? title)` no longer matches.

## Work needed

Repair the test. Prefer asserting behavior (the reset control exposes an accessibility label equal to its `accessibilityLabel` or `title`) over exact source text; KRMA-846's verifier already noted these source-text assertions are brittle. Check `CropInspectorTests` and `InfoInspectorPresentationTests` for the same fragility.

## Acceptance criteria

- `LightInspectorTests` passes and does not depend on the exact spelling of `ResetIconButton`'s modifier chain.
- `scripts/ci-tests.sh fast` has no failures from this test.
- Related: KRMA-844, KRMA-846.


### Comment — claude @ 2026-10-11T13:11:13.077Z

Confirmed still valid 2026-10-11: ResetIconButton uses resolvedAccessibilityLabel but the test asserts the old modifier text. Highest-priority open item; consider promoting to ready.


### Comment — codex @ 2026-10-11T13:56:48.213Z

Replaced the brittle ResetIconButton modifier source assertion with a behavioral accessibility-label assertion. Verified the focused LightInspector test and scripts/ci-tests.sh fast (1,612 tests passed). Commit: d2d1c72b.

## Agent log

- 2026-10-11T14:36:36.036Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LightInspectorTests passes and does not depend on the exact spelling of ResetIconButton's modifier chain. (pass) — The test constructs ResetIconButton and asserts its resolved accessibility label equals the reset title; it no longer asserts modifier-chain source text.
- [x] scripts/ci-tests.sh fast has no failures from this test. (pass) — Fast lane exited 0 after running all 1,618 required tests.
Checks run:
- swift test --filter LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction: exit 0; 1 test passed, 0 failures.
- scripts/ci-tests.sh fast: exit 0; all 1,618 required tests completed.
- Reviewed CropInspectorTests and InfoInspectorPresentationTests for the same fragile ResetIconButton modifier-chain assertion; none found.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3XBB0SNFVV08R8
