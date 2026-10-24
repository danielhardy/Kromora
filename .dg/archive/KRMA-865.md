---
id: KRMA-865
title: Crop inspector Landscape button has no icon (rectangle.landscape is not an SF Symbol)
type: bug
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Crop inspector shows an icon on both orientation buttons.
      result: pass
      notes: Both button names resolve as SF Symbols and are passed to the buttons' systemImage parameters.
    - criterion: CropInspectorTests pass.
      result: pass
      notes: All 3 CropInspectorTests passed.
  checks_run:
    - swift test --filter CropInspectorTests — passed (3 tests, 0 failures)
  findings: []
  fixes: []
  verification_commits:
    - a9607f31b349983ae2b577141363cc2978344104
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:04:28.718Z
  session: 01MV38OO5O0D9JHL0E
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T18:46:48.709Z
updated: 2026-10-11T03:04:28.722Z
blockers: []
order: w
board: product
commits:
  - a9607f31b349983ae2b577141363cc2978344104
  - a9607f31b349983ae2b577141363cc2978344104
---

## Objective

The Landscape orientation button in the Crop inspector (shown for aspect presets that support orientation) has no icon.

## Root cause

`CropInspectorView.landscapeOrientationSystemImage` returned `"rectangle.landscape"`, which is not an SF Symbol. `rectangle.portrait` exists; the landscape rectangle is plain `rectangle`. Verified with `NSImage(systemSymbolName:)` on this macOS 27.2 Mac. A missing symbol draws nothing, so the button rendered blank.

## Work done

- `landscapeOrientationSymbol` is now `"rectangle"` and `portraitOrientationSymbol` stays `"rectangle.portrait"`, exposed as static constants on `CropInspectorView`.
- Added `CropInspectorTests.testOrientationButtonsUseSymbolsThatExist`.
- Audit: every other string literal in Sources that looks like an SF Symbol name resolves; the remaining non-resolving matches are file names and identifiers. Symbols built dynamically (for example `tab.iconName`, `kind.iconName`) were not enumerated.

## Acceptance criteria

- Crop inspector shows an icon on both orientation buttons.
- CropInspectorTests pass.
- Not yet confirmed visually in the running app.


### Comment — claude @ 2026-10-11T01:13:15.769Z

Handoff to verification (implementer: claude; reporter has reviewed). Commit a9607f31. The Landscape orientation button had no icon because rectangle.landscape is not an SF Symbol (rectangle.portrait exists; landscape is plain rectangle), verified with NSImage(systemSymbolName:) on macOS 27.2. Fix: static landscapeOrientationSymbol = rectangle and portraitOrientationSymbol on CropInspectorView, plus CropInspectorTests.testOrientationButtonsUseSymbolsThatExist. I also scanned every string literal in Sources that looks like an SF Symbol name; this was the only missing one (dynamically built names such as tab.iconName were not enumerated). Check: both buttons show icons.


### Comment — claude @ 2026-10-11T01:13:24.838Z

Commits for KRMA-865 (oldest first; review with git show <sha>):
- a9607f31b349983ae2b577141363cc2978344104 KRMA-865: use a real SF Symbol for the Landscape crop orientation button

## Agent log

- 2026-10-11T03:04:28.718Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop inspector shows an icon on both orientation buttons. (pass) — Both button names resolve as SF Symbols and are passed to the buttons' systemImage parameters.
- [x] CropInspectorTests pass. (pass) — All 3 CropInspectorTests passed.
Checks run:
- swift test --filter CropInspectorTests — passed (3 tests, 0 failures)
Findings:
- None
Fixes:
- None
Verification commits:
- a9607f31b349983ae2b577141363cc2978344104
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38OO5O0D9JHL0E
Summary: Verification passed: CropInspectorTests passed and both orientation symbols resolve.
