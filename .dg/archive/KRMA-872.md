---
id: KRMA-872
title: "Light inspector: remove the Auto helper text under the title"
type: task
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The Light tab shows no explanatory line under its title.
      result: pass
      notes: The Light header now contains only the title and reset button; the helper string is absent from Sources and Tests.
    - criterion: The reset icon and its accessibility label and hint are unchanged.
      result: pass
      notes: The reset button title, hint, disabled state, and action match the pre-change implementation.
  checks_run:
    - swift test --filter LightInspectorTests — 27/28 passed; testToneCurveResetUsesAccessibleTrailingDisclosureAction failed at LightInspectorTests.swift:160. This is the known unrelated KRMA-853 failure described in the handoff.
    - swift test --filter MenuCommandTests — passed; 11 tests, 0 failures.
    - swift test --filter InfoInspectorViewTests — passed; 1 test, 0 failures.
    - Searched Sources and Tests for the helper string and reset accessibility text — helper absent; reset title and hint remain present in LightInspectorView.swift.
  findings:
    - The unrelated testToneCurveResetUsesAccessibleTrailingDisclosureAction assertion fails in the LightInspector suite; the handoff attributes it to KRMA-853.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:12:59.677Z
  session: 01MV38Z6R8CIIZC7IG
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-11T01:11:23.889Z
updated: 2026-10-11T03:12:59.680Z
blockers: []
order: zy
board: product
commits:
  - 297981a5877c207c3d8cb3f8cd94618c7fc8b7fa
---

## Objective

Remove the helper line under the Light inspector title: "Auto replaces global Light and Color values; other edits stay unchanged." It is not needed there.

## Work done

`LightInspectorView.header` (Sources/KromoraKit/Views/LightInspectorView.swift) is now just the title and the reset icon; the text and its wrapping `VStack` are gone. Nothing else referenced the string. The LightInspector tests that run are unchanged by this; the one failing assertion in that suite is KRMA-853.

## Acceptance criteria

- The Light tab shows no explanatory line under its title.
- The reset icon and its accessibility label and hint are unchanged.


### Comment — claude @ 2026-10-11T01:13:17.517Z

Handoff to verification (implementer: claude; reporter has reviewed). Commit 297981a5. Removed the helper text 'Auto replaces global Light and Color values; other edits stay unchanged.' from the Light inspector header; LightInspectorView.header is now the title and reset icon only. The string was referenced nowhere else. Tests: LightInspectorTests/InfoInspector/MenuCommandTests run; the only failure is the pre-existing KRMA-853.


### Comment — claude @ 2026-10-11T01:13:26.725Z

Commits for KRMA-872 (oldest first; review with git show <sha>):
- 297981a5877c207c3d8cb3f8cd94618c7fc8b7fa KRMA-872: remove the Auto helper text from the Light inspector header

## Agent log

- 2026-10-11T03:12:59.677Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The Light tab shows no explanatory line under its title. (pass) — The Light header now contains only the title and reset button; the helper string is absent from Sources and Tests.
- [x] The reset icon and its accessibility label and hint are unchanged. (pass) — The reset button title, hint, disabled state, and action match the pre-change implementation.
Checks run:
- swift test --filter LightInspectorTests — 27/28 passed; testToneCurveResetUsesAccessibleTrailingDisclosureAction failed at LightInspectorTests.swift:160. This is the known unrelated KRMA-853 failure described in the handoff.
- swift test --filter MenuCommandTests — passed; 11 tests, 0 failures.
- swift test --filter InfoInspectorViewTests — passed; 1 test, 0 failures.
- Searched Sources and Tests for the helper string and reset accessibility text — helper absent; reset title and hint remain present in LightInspectorView.swift.
Findings:
- The unrelated testToneCurveResetUsesAccessibleTrailingDisclosureAction assertion fails in the LightInspector suite; the handoff attributes it to KRMA-853.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38Z6R8CIIZC7IG
Summary: Verified removal of Light inspector helper text; declared suites pass apart from the known unrelated KRMA-853 tone-curve accessibility failure.
