---
id: KRMA-725
title: Use the app primary color for the Crop Reset button
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reset button uses KromoraTheme.primaryAccent in light and dark
      result: pass
      notes: primaryAccent is a dynamic NSColor with distinct light/dark values; .tint applied to the link-style button.
    - criterion: Button remains legible, interactive, link-style; action and accessibility label/hint unchanged
      result: pass
      notes: Only one line added; link style, action, label and hint untouched.
    - criterion: Focused coverage for the color choice
      result: pass
      notes: CropInspectorTests asserts tint, link style and accessibility strings via source inspection. Textual, not rendered.
  checks_run:
    - swift test --filter CropInspectorTests (passed)
    - git diff --check -- Sources Tests (clean)
  findings:
    - "Info: test is source-text based and would not catch .link style ignoring tint at runtime; no visual check performed."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T23:06:06.224Z
  session: 01MUNABLCIQPOP3TBC
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - crop
  - ui
  - theme
  - color
created: 2026-09-29T21:47:15.106Z
updated: 2026-09-29T23:06:06.226Z
blockers: []
order: n
board: product
context:
  files:
    - Sources/KromoraKit/Views/CropInspectorView.swift
    - Sources/KromoraKit/Views/KromoraTheme.swift
  docs: []
  issues: []
  commands:
    - swift test --filter CropInspectorTests
    - git diff --check
---

## Objective

Style the Crop workspace's Reset action with Kromora's semantic primary accent so it matches the
app's established accent color instead of the default link color.

## Context

The Reset button in the Crop inspector currently uses `.buttonStyle(.link)`, which gives it the
system link color. Other selected and emphasized controls use `KromoraTheme.primaryAccent`; matching
the Reset action to that app color will make the Crop workspace feel consistent with the rest of
Kromora.

## Acceptance criteria

- [ ] The Crop inspector's Reset button uses `KromoraTheme.primaryAccent` in both light and dark
      appearances.
- [ ] The button remains legible, interactive, and consistent with the existing link-style
      treatment; crop reset behavior and accessibility label/hint are unchanged.
- [ ] Add or update focused coverage for the color choice, or document a repeatable visual check if
      the appearance cannot be asserted reliably in a unit test.

## Implementation notes

Update the Reset button styling in `CropInspectorView` to consume the existing semantic app accent
from `KromoraTheme`. Preserve its action and accessibility behavior.

### Comment — codex @ 2026-09-29T22:58:07.366Z

Implemented KRMA-725 in 9536e6a: the Crop Reset button keeps its link treatment and now uses KromoraTheme.primaryAccent. Added focused coverage for the semantic tint and unchanged accessibility label/hint. Verification: swift test --filter CropInspectorTests passed; scoped diff checks passed. Repository-wide git diff --check reports pre-existing trailing whitespace in KRMA-700.md.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T23:06:06.224Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reset button uses KromoraTheme.primaryAccent in light and dark (pass) — primaryAccent is a dynamic NSColor with distinct light/dark values; .tint applied to the link-style button.
- [x] Button remains legible, interactive, link-style; action and accessibility label/hint unchanged (pass) — Only one line added; link style, action, label and hint untouched.
- [x] Focused coverage for the color choice (pass) — CropInspectorTests asserts tint, link style and accessibility strings via source inspection. Textual, not rendered.
Checks run:
- swift test --filter CropInspectorTests (passed)
- git diff --check -- Sources Tests (clean)
Findings:
- Info: test is source-text based and would not catch .link style ignoring tint at runtime; no visual check performed.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUNABLCIQPOP3TBC
Summary: Verified: Crop Reset button tinted with KromoraTheme.primaryAccent; test passes.
