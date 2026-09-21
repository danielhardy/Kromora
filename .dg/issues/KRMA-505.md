---
id: KRMA-505
title: Remove the stray toolbar separator beside Export
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No standalone dash or unintended separator appears between Import and Export.
      result: pass
      notes: The Divider() between the Import menu and Export button in the toolbar group was removed in 90e5d60. Remaining Divider() calls are inside Menu content.
    - criterion: Import and Export remain visible and invoke the same actions.
      result: pass
      notes: Import menu and Export button (shareDialog, disabled when no sourceImage, help text) are untouched.
    - criterion: Toolbar grouping and spacing remain coherent at normal and narrow window widths.
      result: pass
      notes: Static review only; the change removes a single item and leaves the surrounding ToolbarItemGroup structure intact. No visual run was performed.
    - criterion: Toolbar/menu contract tests and dg validate pass.
      result: pass
      notes: MenuCommandTests 9/9 pass; dg validate ok with only pre-existing unknown-model warnings.
  checks_run:
    - swift test --filter MenuCommandTests (9/9 pass)
    - dg validate --json (ok, warnings only)
    - Manual diff review of 90e5d60
  findings:
    - "Info, non-blocking: the new regression test inspects ContentView.swift source text rather than the rendered toolbar, so it is brittle to reformatting. It matches the existing source-contract tests in MenuCommandTests."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T04:41:53.143Z
  session: 01MUARCO81KQRMRQHK
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - toolbar
  - ui
  - ux
created: 2026-09-21T02:40:14.388Z
updated: 2026-09-21T04:41:53.145Z
order: a0
board: product
---

## Objective

Remove the stray dash or separator shown between Import and Export in the main toolbar.

## Context

The toolbar currently shows an unwanted dash immediately to the left of the Export icon, between the Import and Export controls. The toolbar should use its intended logical groups and spacing without rendering a standalone separator glyph.

## Requirements

1. Remove the stray dash/separator from the toolbar.
2. Preserve the Import and Export controls, their actions, labels, shortcuts, and enabled states.
3. Restore or retain the intended toolbar grouping and spacing so the controls remain visually organized without the unwanted mark.
4. Do not remove unrelated toolbar actions or menu separators.

## Acceptance criteria

- [ ] No standalone dash or unintended separator appears between Import and Export.
- [ ] Import and Export remain visible and invoke the same actions.
- [ ] Toolbar grouping and spacing remain coherent at normal and narrow window widths.
- [ ] Toolbar/menu contract tests and dg validate pass.

## Implementation notes

Inspect the toolbar item groups and any text, divider, or conditional branch that could render a dash. Prefer fixing the grouping/layout source rather than masking the glyph with styling.


### Comment — codex @ 2026-09-21T04:41:14.249Z

Implemented in 90e5d60: removed the standalone toolbar Divider between Import and Export, preserving both controls and their existing routes/labels/states. Added a focused toolbar contract test. Verification: swift test --filter MenuCommandTests (9/9), swift build, git diff --check, and dg validate --json all pass; dg validation has only pre-existing unknown-model warnings.

## Agent log

- 2026-09-21T04:41:53.143Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No standalone dash or unintended separator appears between Import and Export. (pass) — The Divider() between the Import menu and Export button in the toolbar group was removed in 90e5d60. Remaining Divider() calls are inside Menu content.
- [x] Import and Export remain visible and invoke the same actions. (pass) — Import menu and Export button (shareDialog, disabled when no sourceImage, help text) are untouched.
- [x] Toolbar grouping and spacing remain coherent at normal and narrow window widths. (pass) — Static review only; the change removes a single item and leaves the surrounding ToolbarItemGroup structure intact. No visual run was performed.
- [x] Toolbar/menu contract tests and dg validate pass. (pass) — MenuCommandTests 9/9 pass; dg validate ok with only pre-existing unknown-model warnings.
Checks run:
- swift test --filter MenuCommandTests (9/9 pass)
- dg validate --json (ok, warnings only)
- Manual diff review of 90e5d60
Findings:
- Info, non-blocking: the new regression test inspects ContentView.swift source text rather than the rendered toolbar, so it is brittle to reformatting. It matches the existing source-contract tests in MenuCommandTests.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUARCO81KQRMRQHK
Summary: Verified: stray toolbar Divider between Import and Export removed; controls, actions, labels and disabled state unchanged.
