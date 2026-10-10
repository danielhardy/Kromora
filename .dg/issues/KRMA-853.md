---
id: KRMA-853
title: "Failing: LightInspectorTests tone curve reset source assertion broken by ResetIconButton change"
type: bug
status: backlog
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:41.164Z
updated: 2026-10-10T13:02:45.233Z
blockers: []
order: zzq
board: product
---

## Objective

`LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction` fails on main (`Tests/KromoraKitTests/LightInspectorTests.swift:160`) and fails the fast CI lane. KRMA-846 repaired this test, but commit 158ea66f (KRMA-844) later changed `Sources/KromoraKit/Views/ResetIconButton.swift` to use `resolvedAccessibilityLabel`, so the test's source-text assertion `.accessibilityLabel(accessibilityLabel ?? title)` no longer matches.

## Work needed

Repair the test. Prefer asserting behavior (the reset control exposes an accessibility label equal to its `accessibilityLabel` or `title`) over exact source text; KRMA-846's verifier already noted these source-text assertions are brittle. Check `CropInspectorTests` and `InfoInspectorPresentationTests` for the same fragility.

## Acceptance criteria

- `LightInspectorTests` passes and does not depend on the exact spelling of `ResetIconButton`'s modifier chain.
- `scripts/ci-tests.sh fast` has no failures from this test.
- Related: KRMA-844, KRMA-846.
