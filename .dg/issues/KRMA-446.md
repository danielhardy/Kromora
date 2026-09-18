---
id: KRMA-446
title: Remove the Reset Texture / Clarity / Dehaze reset link
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The "Reset Texture / Clarity / Dehaze" button/link no longer appears in the Effects inspector's detail section.
      result: pass
      notes: sectionResetButton call removed from detailSection in EffectsInspectorView.swift; no remaining 'Reset Texture' button string anywhere in Sources.
    - criterion: The top-level "Reset Effects" button continues to reset texture/clarity/dehaze along with the rest of the effects.
      result: pass
      notes: resetAllEffects() sets document.effects = .neutral; EffectsAdjustments.neutral defaults texture/clarity/dehaze to 0 (EffectsAdjustments.swift:135,156-164), so no loss of reset capability.
    - criterion: Remove now-dead code (sectionResetButton call, and resetAllDetailEffects/hasDetailEffects if unused) rather than leaving orphaned code.
      result: pass
      notes: resetAllDetailEffects() fully removed from AppViewModel+Effects.swift with no remaining references. hasDetailEffects retained since it is still used by hasEffects (AppViewModel+Effects.swift:94) which backs the top-level Reset Effects button's disabled state -- correctly kept, not orphaned. sectionResetButton helper retained since still used by ColorInspectorView and by the Vignette/Grain sections of EffectsInspectorView (out of scope per issue).
  checks_run:
    - git show 4e20866 (reviewed full diff)
    - rg for resetAllDetailEffects/hasDetailEffects/sectionResetButton/'Reset Texture' across Sources/ and Tests/ to confirm no orphaned references
    - manual trace of resetAllEffects() -> EffectsAdjustments.neutral to confirm texture/clarity/dehaze reset semantics preserved
    - git status --porcelain (no changes introduced by verification; pre-existing unrelated working-tree modifications from other in-progress issues left untouched)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-18T19:45:20.146Z
  session: 01MU7DAKCDCI8MSOEL
labels:
  - ui
  - editor
created: 2026-09-18T02:23:05.137Z
updated: 2026-09-18T19:45:20.148Z
order: a0
board: product
---

## Objective

Remove the "Reset Texture / Clarity / Dehaze" link/button from the Effects inspector. It's redundant with the top-level "Reset Effects" control and adds clutter.

## Context

- `Sources/KromoraKit/Views/EffectsInspectorView.swift:45-49` — inside `detailSection`: `sectionResetButton(title: "Reset Texture / Clarity / Dehaze", disabled: !viewModel.hasDetailEffects, action: viewModel.resetAllDetailEffects)`. This is the exact element to remove — distinct from the top-level `"Reset Effects"` button at ~line 35, which stays.
- Confirm `viewModel.resetAllDetailEffects` (`Sources/KromoraKit/ViewModels/AppViewModel.swift` or wherever it's defined) and `hasDetailEffects` aren't used elsewhere before deleting them outright, or leave them in place and just remove the UI call site if they're still meaningfully used by the top-level reset path.

## Acceptance criteria

- [ ] The "Reset Texture / Clarity / Dehaze" button/link no longer appears in the Effects inspector's detail section.
- [ ] The top-level "Reset Effects" button continues to reset texture/clarity/dehaze along with the rest of the effects (i.e. no loss of the ability to reset these values — just removal of the redundant, narrower control).
- [ ] Remove now-dead code (`sectionResetButton` call, and `resetAllDetailEffects`/`hasDetailEffects` if they become unused) rather than leaving orphaned code behind.

## Out of scope

- Any other per-group reset buttons elsewhere in the inspectors (e.g. for Vignette/Grain) unless the user asks to remove those too — this is specifically the Texture/Clarity/Dehaze one.


### Comment — codex @ 2026-09-18T17:04:17.765Z

Implemented in 4e20866. Removed the redundant Reset Texture / Clarity / Dehaze link from EffectsInspectorView and deleted its now-unused resetAllDetailEffects() method. Retained hasDetailEffects and resetAllEffects(), so the top-level Reset Effects control still resets texture, clarity, dehaze, vignette, and grain. Verification: dg validate passed; rg confirmed no remaining detail-reset references; git diff --check passed with the direct Xcode Git binary. swift test could not run because the machine has not accepted the Xcode license.

## Agent log

- 2026-09-18T19:45:20.146Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The "Reset Texture / Clarity / Dehaze" button/link no longer appears in the Effects inspector's detail section. (pass) — sectionResetButton call removed from detailSection in EffectsInspectorView.swift; no remaining 'Reset Texture' button string anywhere in Sources.
- [x] The top-level "Reset Effects" button continues to reset texture/clarity/dehaze along with the rest of the effects. (pass) — resetAllEffects() sets document.effects = .neutral; EffectsAdjustments.neutral defaults texture/clarity/dehaze to 0 (EffectsAdjustments.swift:135,156-164), so no loss of reset capability.
- [x] Remove now-dead code (sectionResetButton call, and resetAllDetailEffects/hasDetailEffects if unused) rather than leaving orphaned code. (pass) — resetAllDetailEffects() fully removed from AppViewModel+Effects.swift with no remaining references. hasDetailEffects retained since it is still used by hasEffects (AppViewModel+Effects.swift:94) which backs the top-level Reset Effects button's disabled state -- correctly kept, not orphaned. sectionResetButton helper retained since still used by ColorInspectorView and by the Vignette/Grain sections of EffectsInspectorView (out of scope per issue).
Checks run:
- git show 4e20866 (reviewed full diff)
- rg for resetAllDetailEffects/hasDetailEffects/sectionResetButton/'Reset Texture' across Sources/ and Tests/ to confirm no orphaned references
- manual trace of resetAllEffects() -> EffectsAdjustments.neutral to confirm texture/clarity/dehaze reset semantics preserved
- git status --porcelain (no changes introduced by verification; pre-existing unrelated working-tree modifications from other in-progress issues left untouched)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU7DAKCDCI8MSOEL
