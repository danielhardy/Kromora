---
id: KRMA-853
title: "Failing: LightInspectorTests tone curve reset source assertion broken by ResetIconButton change"
type: bug
status: verification
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:41.164Z
updated: 2026-10-11T13:56:49.385Z
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
