---
id: KRMA-644
title: Share reset-button row layout across color and effects inspectors
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Both inspectors use one shared implementation for the reset-button row layout.
      result: pass
      notes: ColorInspectorView and EffectsInspectorView both call the new InspectorSectionResetButton view (7 call sites total); the duplicated private sectionResetButton(title:disabled:action:) methods were removed from both files.
    - criterion: Button title, action, link styling, and disabled behavior remain unchanged in both inspectors.
      result: pass
      notes: "New view body is a byte-for-byte match of the removed helpers: HStack { Spacer(); Button(title, action: action).buttonStyle(.link).disabled(disabled) }. All call-site title/action/disabled arguments carried over unchanged."
    - criterion: Keep the change limited to the duplicated reset-button presentation; do not merge the separate color and effects value-row implementations.
      result: pass
      notes: Diff touches only the reset-button helper extraction; ColorInspectorView.valueRow and EffectsInspectorView value-row implementations are untouched and remain separate.
  checks_run:
    - swift build -- pass
    - scripts/ci-tests.sh warning-gate -- pass (swift build --build-tests -Xswiftc -warnings-as-errors, confirms zero-diagnostic Swift 6 mode compile)
    - scripts/ci-tests.sh fast -- pass (1253/1253 deterministic/model/fake-engine tests passed)
    - grep -rn sectionResetButton Sources/ Tests/ -- pass (no stray references to the removed private helper remain)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T04:14:20.974Z
  session: 01MUJAV39GDE8BDLCB
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cleanup
created: 2026-09-27T02:57:00.603Z
updated: 2026-09-27T04:14:20.976Z
blockers: []
order: a0
board: product
---

## Objective

Remove the identical reset-button row implementation duplicated between the color and effects inspectors.

## Context

`ColorInspectorView.sectionResetButton` and `EffectsInspectorView.sectionResetButton` both build the same trailing link-style button row with a disabled state. A small shared view/helper can keep this repeated presentation detail consistent.

Relevant code: `Sources/KromoraKit/Views/ColorInspectorView.swift` and `Sources/KromoraKit/Views/EffectsInspectorView.swift`.

## Acceptance criteria

- [ ] Both inspectors use one shared implementation for the reset-button row layout.
- [ ] Button title, action, link styling, and disabled behavior remain unchanged in both inspectors.
- [ ] Keep the change limited to the duplicated reset-button presentation; do not merge the separate color and effects value-row implementations.

## Implementation notes

Choose the smallest shared SwiftUI abstraction that fits the existing view structure. This is a minor maintainability cleanup.

### Comment — codex @ 2026-09-27T04:09:39.061Z

Implemented shared InspectorSectionResetButton for color and effects section reset rows; titles, actions, link styling, and disabled states are preserved. Verified with swift build. Commit: 7f7deac.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T04:14:20.974Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Both inspectors use one shared implementation for the reset-button row layout. (pass) — ColorInspectorView and EffectsInspectorView both call the new InspectorSectionResetButton view (7 call sites total); the duplicated private sectionResetButton(title:disabled:action:) methods were removed from both files.
- [x] Button title, action, link styling, and disabled behavior remain unchanged in both inspectors. (pass) — New view body is a byte-for-byte match of the removed helpers: HStack { Spacer(); Button(title, action: action).buttonStyle(.link).disabled(disabled) }. All call-site title/action/disabled arguments carried over unchanged.
- [x] Keep the change limited to the duplicated reset-button presentation; do not merge the separate color and effects value-row implementations. (pass) — Diff touches only the reset-button helper extraction; ColorInspectorView.valueRow and EffectsInspectorView value-row implementations are untouched and remain separate.
Checks run:
- swift build -- pass
- scripts/ci-tests.sh warning-gate -- pass (swift build --build-tests -Xswiftc -warnings-as-errors, confirms zero-diagnostic Swift 6 mode compile)
- scripts/ci-tests.sh fast -- pass (1253/1253 deterministic/model/fake-engine tests passed)
- grep -rn sectionResetButton Sources/ Tests/ -- pass (no stray references to the removed private helper remain)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJAV39GDE8BDLCB
