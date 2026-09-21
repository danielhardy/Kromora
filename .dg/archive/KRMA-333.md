---
id: KRMA-333
title: Use C as the crop tool hotkey
type: task
status: done
priority: medium
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 777964a
  actor: pi
  resolved_model: openrouter/meta/muse-spark-1.3-contributor
  completed_at: 2026-09-10T14:17:04.744Z
  session: 01MTVLMOFS05MFOLVA
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - feature
created: 2026-09-10T04:08:36.674Z
updated: 2026-09-10T14:17:04.746Z
order: a0
board: product
commits:
  - 777964a
---

## Objective

Use `C` as the keyboard shortcut for activating the crop tool.

## Context

Cropping is a frequent editing action and should be quickly accessible from the keyboard while
working in the image editor.

## Acceptance criteria

- [ ] Pressing `C` activates the crop tool for the current image/editor context.
- [ ] The shortcut works when focus is on the canvas and does not insert text or trigger an
      unrelated command in text-entry controls.
- [ ] The existing crop toolbar control and any current activation behavior remain functional.
- [ ] Add regression coverage for the key command and its focus/context handling.

## Implementation notes

Follow the existing menu-command and keyboard-monitor conventions. Check for conflicts with current
shortcuts before wiring the command.

### Comment — codex @ 2026-09-10T14:04:30.234Z

Implemented in commit 777964a. Added plain C crop-tool routing to the existing keyboard monitor; it toggles the crop tool only with an image present, preserves modified/system shortcuts, and inherits the existing text/control focus gate. Added KeyMonitorPolicy regression coverage for plain C, case normalization, and modified-key handling. Verification: swift test --filter KeyMonitorTests (5 passed); swift test (1,061 executed, 47 skipped, 0 failures); git diff --check clean.

### Comment — pi @ 2026-09-10T14:17:01.458Z

## Verification report (counterpoint, pi) — PASS

Scope: correctness, maintainability, security, performance; independent re-run of declared checks.

Checks:
- swift test --filter KeyMonitorTests — 5 passed
- swift test — 1061 executed, 47 skipped, 0 failures (matches implementer report)
- git diff --check — clean
- Conflict sweep: no plain-C collision (culling keys are p/x/u/0-5; plain-char shortcuts g/e/b/l/r/v/[/]; menu copy/paste are Cmd+Opt+C/V, untouched by the plain-key monitor path).

Review:
- Plain C (any case, no modifiers) routes to toggleCropTool only when sourceImage != nil, mirroring the toolbar button disabled state; modified C (shift/cmd/opt/ctrl) passes through to AppKit.
- Focus handling inherits the existing gate: NSText/NSControl first responders and presented sheets keep the key, so no text insertion or control hijack.
- Key-up ignored (key-down only); toggleCropTool/beginCrop untouched, so existing toolbar behavior is preserved.
- Small pure KeyMonitorPolicy.isCropShortcut helper with direct regression coverage (plain C, case normalization, modified-key rejection).

No fixes applied; no child tickets. Acceptance criteria all met.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-10T14:17:04.744Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 777964a
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTVLMOFS05MFOLVA
Summary: Verified: plain-C crop shortcut routes to toggleCropTool with image/focus guards; KeyMonitorTests 5 passed; full suite 1061 executed, 0 failures; no shortcut conflicts.
