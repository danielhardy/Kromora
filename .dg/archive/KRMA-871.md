---
id: KRMA-871
title: "Masks panel: mask-kind buttons should be neutral, not copper"
type: task
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The empty Masks panel shows the eleven kind buttons with default (non-copper) labels and icons.
      result: pass
      notes: Each button applies .tint(nil) after .buttonStyle(.bordered), following the established Crop control pattern that clears inherited window tint.
    - criterion: Masking panel tests pass (61 related tests do).
      result: pass
      notes: 114 selected mask-related and menu tests passed with zero failures, including MaskingPanelTests (5), MaskingWorkspaceTests (45), and MenuCommandTests (11).
  checks_run:
    - swift test --filter (MaskingPanelTests|MaskingWorkspaceTests|MaskingWorkflowCoordinatorTests|MaskPresentationPolicyTests|MaskRefinementTests|SmartMaskTests|LocalMaskTests|RegionMaskTests|MenuCommandTests) — 114 tests passed
    - git show --check --oneline 0669dfbb7cbae2d2f96196f902b23aa8a28a1afb — passed
    - dg validate — OK; existing model-name warnings reported
  findings:
    - Sixteen other bordered-button call sites inherit the window-wide copper tint; tracked in child issue KRMA-873, labeled verification and linked to KRMA-871.
    - No correctness, security, or performance defect found in the scoped change.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:12:13.812Z
  session: 01MV38XK5SVACPTTAH
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-11T01:10:25.691Z
updated: 2026-10-11T03:12:13.815Z
blockers: []
order: zx
board: product
commits:
  - 0669dfbb7cbae2d2f96196f902b23aa8a28a1afb
---

## Objective

The mask-kind buttons in the Masks panel (Subject, Person, Face, Foreground, Background, Brush, Linear Gradient, Radial Gradient, Luminance Range, Color Range, Depth Range) rendered with copper labels and icons. They are one-shot choices, not a selected state, so they should look like ordinary buttons and leave the copper accent for what is on.

## Cause

`ContentView` applies `.tint(KromoraTheme.primaryAccent)` to the whole window, and `.buttonStyle(.bordered)` picks the tint up for its label. The chooser in `MaskingWorkspace.emptyMaskChooser` set no tint of its own.

## Work done

`.tint(nil)` on the chooser buttons (Sources/KromoraKit/Views/MaskingWorkspace.swift), the same approach as the Crop Rotate buttons (KRMA-866). The Flip toggles already use `.tint(nil)` when off and render neutral inside the same window, which is the evidence it overrides the inherited tint. An offscreen render cannot show the difference (an inactive window draws bordered buttons neutral regardless), so this has not been seen in the running app.

## Acceptance criteria

- The empty Masks panel shows the eleven kind buttons with default (non-copper) labels and icons.
- Masking panel tests pass (61 related tests do).

## Follow-up for the owner

Sixteen other `.buttonStyle(.bordered)` call sites inherit the same copper (Library grid and culling bar, Look and Color inspectors, Crop, onboarding, preview). Decide whether bordered buttons should be neutral app-wide (one shared style or a tint reset at the window level) rather than fixing them one at a time.


### Comment — claude @ 2026-10-11T01:13:17.264Z

Handoff to verification (implementer: claude; reporter has reviewed). Commit 0669dfbb. The Masks panel kind buttons rendered copper because ContentView sets .tint(KromoraTheme.primaryAccent) window-wide and .bordered buttons use it for their labels; added .tint(nil) in MaskingWorkspace.emptyMaskChooser so they read as ordinary buttons. Evidence it overrides the inherited tint: the Crop Flip toggles use .tint(nil) when off and render neutral in the same window. Tests: MaskingPanelTests and MenuCommandTests pass (61 related). Open question recorded in the ticket: sixteen other .buttonStyle(.bordered) sites inherit the same copper, so a single app-wide rule may be better than one-by-one fixes.


### Comment — claude @ 2026-10-11T01:13:26.473Z

Commits for KRMA-871 (oldest first; review with git show <sha>):
- 0669dfbb7cbae2d2f96196f902b23aa8a28a1afb KRMA-871: make the Masks panel kind buttons neutral instead of copper

## Agent log

- 2026-10-11T03:12:13.812Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The empty Masks panel shows the eleven kind buttons with default (non-copper) labels and icons. (pass) — Each button applies .tint(nil) after .buttonStyle(.bordered), following the established Crop control pattern that clears inherited window tint.
- [x] Masking panel tests pass (61 related tests do). (pass) — 114 selected mask-related and menu tests passed with zero failures, including MaskingPanelTests (5), MaskingWorkspaceTests (45), and MenuCommandTests (11).
Checks run:
- swift test --filter (MaskingPanelTests|MaskingWorkspaceTests|MaskingWorkflowCoordinatorTests|MaskPresentationPolicyTests|MaskRefinementTests|SmartMaskTests|LocalMaskTests|RegionMaskTests|MenuCommandTests) — 114 tests passed
- git show --check --oneline 0669dfbb7cbae2d2f96196f902b23aa8a28a1afb — passed
- dg validate — OK; existing model-name warnings reported
Findings:
- Sixteen other bordered-button call sites inherit the window-wide copper tint; tracked in child issue KRMA-873, labeled verification and linked to KRMA-871.
- No correctness, security, or performance defect found in the scoped change.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38XK5SVACPTTAH
Summary: Verified neutral tint override and targeted mask behavior; broader bordered-button tint audit tracked in KRMA-873.
