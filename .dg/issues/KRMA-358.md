---
id: KRMA-358
title: Make single-image and side-by-side comparison modes consistently available
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A documented product decision selects the interaction model and defines single-image, side-by-side, V, and Space behavior.
      result: pass
      notes: docs/COMPARISON_MODE.md documents the always-both model with an explicit interaction contract table and lifecycle rules; README updated to match.
    - criterion: The chosen comparison action is consistently discoverable whenever a meaningful comparison exists; control visibility does not depend on an accidental presentation state.
      result: pass
      notes: New isComparisonPresentationAvailable (AppViewModel.swift:423-426) gates the top-bar control (ContentView.swift:267) and status hints (StatusBar.swift:72), covering both isComparisonAvailable and a retained isSideBySide preference on an identity document.
    - criterion: The alternate version is always reachable without relying on an undocumented gesture.
      result: pass
      notes: V performs toggleSideBySide() unconditionally when gated available; Space is documented as single-view-only and is now excluded while isSideBySide is true (AppViewModel.swift:4140-4148, KeyboardShortcuts.swift:182-187).
    - criterion: Edited and comparison surfaces remain correctly labeled and VoiceOver-accessible in every mode.
      result: pass
      notes: PreviewView.swift adds accessibilityLabel/accessibilityHint for both side-by-side panels and the single-view surface, including a look-name-aware label and a 'presentation only' hint.
    - criterion: Photo switching, reset-to-identity, undo/redo, and relaunch preserve or clear comparison state according to the documented model.
      result: pass
      notes: isShowingOriginal is cleared on photo switch (line 1532, pre-existing), on LUT intensity reaching identity (3153), and on undo/redo landing on identity (3815); isSideBySide preference persists via UserDefaults (pre-existing, unaffected). New tests testSpaceIsSingleViewOnly and testUndoToIdentityClearsTransientOriginal cover the new behavior.
    - criterion: Add/update comparison-mode tests for the chosen behavior, including existing ComparisonModeTests cases for first launch, photo switching, identity/reset, and settled side-by-side entry.
      result: pass
      notes: All 15 ComparisonModeTests pass, including the 2 new tests and the pre-existing first-launch/photo-switch/identity-reset/settled-entry cases.
    - criterion: Preview rendering, baseline caching, and export semantics remain unchanged; comparison presentation remains non-destructive.
      result: pass
      notes: No changes to RenderEngine, comparisonBaseline computation, or export paths; changes are confined to presentation-state gating and accessibility labels.
  checks_run:
    - swift build (clean, only pre-existing CI-kernel deprecation warnings)
    - swift test --filter ComparisonModeTests (15/15 passed)
    - scripts/ci-tests.sh fast (877/877 passed)
    - scripts/ci-tests.sh serial (334/334 passed)
    - git status --porcelain (no unexpected tracked-source changes from this review)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-11T04:13:56.397Z
  session: 01MTWFUGUMK36CBYJZ
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - comparison
  - editor
created: 2026-09-11T02:51:21.423Z
updated: 2026-09-11T04:13:56.400Z
order: a0
board: product
---

## Objective

Define and implement one consistent comparison interaction for the editor’s single-image and side-by-side views. A user should always have an obvious way to reach the alternate comparison state instead of encountering different or conditional controls depending on which presentation mode is active.

## Current behavior

- Single-image view displays the edited image; holding Space temporarily shows the comparison/original image.
- Side-by-side view displays the comparison baseline and edited image together.
- The top-bar comparison control is conditionally rendered when comparison is available or a retained side-by-side preference is active.
- `V` toggles side-by-side, while Space handles a temporary original view.

This creates an interaction-model question: should the experience always be a toggle between the two versions, or should both versions always be offered as an explicit side-by-side option?

## Product decision

Choose and document one of these coherent models before implementation:

1. **Always-toggle model:** the primary comparison action consistently switches the active single-image presentation to the other version, with side-by-side available as an explicit secondary option.
2. **Always-both model:** whenever a meaningful comparison exists, side-by-side is consistently available as the primary comparison presentation, with single-image viewing as the alternate.

The selected model must define the roles of the top-bar control, `V`, and Space, including what happens after photo switching, reset, undo, or comparison becomes unavailable.

## Acceptance criteria

- [ ] A documented product decision selects the interaction model and defines single-image, side-by-side, `V`, and Space behavior.
- [ ] The chosen comparison action is consistently discoverable whenever a meaningful comparison exists; control visibility does not depend on an accidental presentation state.
- [ ] The alternate version is always reachable without relying on an undocumented gesture.
- [ ] Edited and comparison surfaces remain correctly labeled and VoiceOver-accessible in every mode.
- [ ] Photo switching, reset-to-identity, undo/redo, and relaunch preserve or clear comparison state according to the documented model.
- [ ] Add/update comparison-mode tests for the chosen behavior, including the current `ComparisonModeTests` cases for first launch, photo switching, identity/reset, and settled side-by-side entry.
- [ ] Preview rendering, baseline caching, and export semantics remain unchanged; comparison presentation remains non-destructive.

## Implementation notes

Relevant code: `Sources/KromoraKit/Views/ContentView.swift` comparison control, `Sources/KromoraKit/Views/PreviewView.swift` single/side-by-side branches, `Sources/KromoraKit/Views/StatusBar.swift`, `Sources/KromoraKit/Views/KeyboardShortcuts.swift`, and `AppViewModel` comparison state. Existing comparison contracts and baseline semantics are covered by KRMA-047 and `Tests/KromoraKitTests/ComparisonModeTests.swift`. Keep this separate from KRMA-356, which only removes the persistent masking workspace button.,


### Comment — codex @ 2026-09-11T04:10:18.287Z

Implemented and committed as 27a863c. Selected and documented the always-both comparison model: the top-bar control and V consistently toggle side-by-side and single view; Space is single-view-only and temporarily shows Original. Made comparison discoverability consistent for retained identity/reset states, cleared transient Original state on identity undo/redo and zero-intensity Look, added VoiceOver labels for Original/Edited surfaces, and expanded ComparisonModeTests. Validation: swift test passed (1,257 tests, 48 expected skips); git diff --cached --check passed. Repository format check remains red on pre-existing violations across untouched code.

## Agent log

- 2026-09-11T04:13:56.397Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A documented product decision selects the interaction model and defines single-image, side-by-side, V, and Space behavior. (pass) — docs/COMPARISON_MODE.md documents the always-both model with an explicit interaction contract table and lifecycle rules; README updated to match.
- [x] The chosen comparison action is consistently discoverable whenever a meaningful comparison exists; control visibility does not depend on an accidental presentation state. (pass) — New isComparisonPresentationAvailable (AppViewModel.swift:423-426) gates the top-bar control (ContentView.swift:267) and status hints (StatusBar.swift:72), covering both isComparisonAvailable and a retained isSideBySide preference on an identity document.
- [x] The alternate version is always reachable without relying on an undocumented gesture. (pass) — V performs toggleSideBySide() unconditionally when gated available; Space is documented as single-view-only and is now excluded while isSideBySide is true (AppViewModel.swift:4140-4148, KeyboardShortcuts.swift:182-187).
- [x] Edited and comparison surfaces remain correctly labeled and VoiceOver-accessible in every mode. (pass) — PreviewView.swift adds accessibilityLabel/accessibilityHint for both side-by-side panels and the single-view surface, including a look-name-aware label and a 'presentation only' hint.
- [x] Photo switching, reset-to-identity, undo/redo, and relaunch preserve or clear comparison state according to the documented model. (pass) — isShowingOriginal is cleared on photo switch (line 1532, pre-existing), on LUT intensity reaching identity (3153), and on undo/redo landing on identity (3815); isSideBySide preference persists via UserDefaults (pre-existing, unaffected). New tests testSpaceIsSingleViewOnly and testUndoToIdentityClearsTransientOriginal cover the new behavior.
- [x] Add/update comparison-mode tests for the chosen behavior, including existing ComparisonModeTests cases for first launch, photo switching, identity/reset, and settled side-by-side entry. (pass) — All 15 ComparisonModeTests pass, including the 2 new tests and the pre-existing first-launch/photo-switch/identity-reset/settled-entry cases.
- [x] Preview rendering, baseline caching, and export semantics remain unchanged; comparison presentation remains non-destructive. (pass) — No changes to RenderEngine, comparisonBaseline computation, or export paths; changes are confined to presentation-state gating and accessibility labels.
Checks run:
- swift build (clean, only pre-existing CI-kernel deprecation warnings)
- swift test --filter ComparisonModeTests (15/15 passed)
- scripts/ci-tests.sh fast (877/877 passed)
- scripts/ci-tests.sh serial (334/334 passed)
- git status --porcelain (no unexpected tracked-source changes from this review)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTWFUGUMK36CBYJZ
Summary: Verified: always-both comparison model correctly implemented and documented; all acceptance criteria met; fast+serial test lanes pass (877+334 tests); no findings.
