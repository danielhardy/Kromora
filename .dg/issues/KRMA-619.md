---
id: KRMA-619
title: Improve first-run onboarding and contextual learning
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Provide a welcome flow, licensed sample library, first-import action, and short Library/Edit/Export tour.
      result: pass
      notes: WelcomeView (ContentView.swift) offers Import photos, Import from Photos, and a bundled CC0 sample library (StarterSampleLibrary, manifest.json with provenance/license); WorkflowTourView walks Library/Edit/Export with real navigation/actions. Verified by OnboardingTests.testBundledSampleLibraryHasTwoReadablePhotosAndLicenseManifest.
    - criterion: Give empty surfaces a clear next action, including no library, no selection, no results, no Looks, and completed export.
      result: pass
      notes: No-library and no-selection actions are new (LibraryGridView/LibraryEmptyState, PreviewView empty state); no-results (filter clear) and no-Looks (LookInspectorEmptyState) already existed and remain intact; completed-export banner added to PreviewView.
    - criterion: Add guided-edit cards that apply annotated, undoable steps through the existing edit/preview path.
      result: pass
      notes: GuidedEditCards routes each step through AppViewModel.updateDocument (the existing non-destructive edit path), so history/undo/persistence/preview are all the normal pipeline. Verified by OnboardingTests.testGuidedEditStepsMakeBoundedSingleDocumentAdjustments.
    - criterion: Explain controls in place and expose a searchable in-app shortcut reference.
      result: pass
      notes: LightControl.explanation surfaced via .help() on LightInspectorView rows; KeyboardShortcutReferenceView adds a filterable shortcut list reachable from the toolbar. Verified by OnboardingTests.testLightControlsHaveContextualExplanations.
  checks_run:
    - swift build (clean, full package) - passed
    - swift test --filter OnboardingTests - 3/3 passed (run with two untracked, unrelated in-progress retouch-feature files temporarily moved out of the tree and restored afterward, since they do not compile against the current EditDocument and block whole-target compilation independent of this change)
    - swift test --filter PackageSettingsTests - 4/4 passed (same isolation as above), confirming Swift 6 mode / zero-escape-hatch invariants still hold
    - scripts/ci-tests.sh fast (deterministic/model lane) - ran to completion with the shared working tree as-is; only failure was AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent, confirmed pre-existing and unrelated to this issue by re-running it with an unrelated staged in-progress change (AppViewModel/PreviewAdmissionCoordinator histogram work) temporarily stashed and restored - it fails identically either way and touches no onboarding code
    - git diff --check on the onboarding commit's changed files - clean
  findings:
    - "Low/non-blocking (maintainability): Sources/KromoraKit/Views/PreviewView.swift's completed-export banner triggers on viewModel.statusMessage.hasPrefix(\"Exported\") rather than a structured completion signal. If ExportCoordinator status text is ever reworded/localized, or another status path starts with \"Exported\" for an unrelated reason, the banner would silently stop appearing or misfire, with no compiler or test signal. Currently correct against all existing ExportCoordinator status strings."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T17:57:25.244Z
  session: 01MUIOR57GV7D4KND1
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:42.006Z
updated: 2026-09-26T17:57:25.246Z
blockers: []
order: zx
board: product
---

## Objective

Help new users move from a blank install to a confident first edit and discover existing controls.

## Context

The app already has rich editing and keyboard actions, but the evaluation found onboarding and discoverability gaps.

Derived from §11 Ease of use in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a welcome flow, licensed sample library, first-import action, and short Library/Edit/Export tour.
- [ ] Give empty surfaces a clear next action, including no library, no selection, no results, no Looks, and completed export.
- [ ] Add guided-edit cards that apply annotated, undoable steps through the existing edit/preview path.
- [ ] Explain controls in place and expose a searchable in-app shortcut reference.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-26T17:44:33.556Z

Implemented first-run welcome actions, a Library/Edit/Export tour, bundled CC0 sample photos with provenance, undoable guided Light edits, contextual Light help, actionable empty states, export follow-ups, and searchable keyboard shortcuts. Added OnboardingTests and docs/ONBOARDING.md. Verification: swift build and git diff --check passed. swift test --filter OnboardingTests was blocked by pre-existing RetouchModelTests compile errors referencing missing EditDocument.retouch.

## Agent log

- 2026-09-26T17:57:25.244Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Provide a welcome flow, licensed sample library, first-import action, and short Library/Edit/Export tour. (pass) — WelcomeView (ContentView.swift) offers Import photos, Import from Photos, and a bundled CC0 sample library (StarterSampleLibrary, manifest.json with provenance/license); WorkflowTourView walks Library/Edit/Export with real navigation/actions. Verified by OnboardingTests.testBundledSampleLibraryHasTwoReadablePhotosAndLicenseManifest.
- [x] Give empty surfaces a clear next action, including no library, no selection, no results, no Looks, and completed export. (pass) — No-library and no-selection actions are new (LibraryGridView/LibraryEmptyState, PreviewView empty state); no-results (filter clear) and no-Looks (LookInspectorEmptyState) already existed and remain intact; completed-export banner added to PreviewView.
- [x] Add guided-edit cards that apply annotated, undoable steps through the existing edit/preview path. (pass) — GuidedEditCards routes each step through AppViewModel.updateDocument (the existing non-destructive edit path), so history/undo/persistence/preview are all the normal pipeline. Verified by OnboardingTests.testGuidedEditStepsMakeBoundedSingleDocumentAdjustments.
- [x] Explain controls in place and expose a searchable in-app shortcut reference. (pass) — LightControl.explanation surfaced via .help() on LightInspectorView rows; KeyboardShortcutReferenceView adds a filterable shortcut list reachable from the toolbar. Verified by OnboardingTests.testLightControlsHaveContextualExplanations.
Checks run:
- swift build (clean, full package) - passed
- swift test --filter OnboardingTests - 3/3 passed (run with two untracked, unrelated in-progress retouch-feature files temporarily moved out of the tree and restored afterward, since they do not compile against the current EditDocument and block whole-target compilation independent of this change)
- swift test --filter PackageSettingsTests - 4/4 passed (same isolation as above), confirming Swift 6 mode / zero-escape-hatch invariants still hold
- scripts/ci-tests.sh fast (deterministic/model lane) - ran to completion with the shared working tree as-is; only failure was AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent, confirmed pre-existing and unrelated to this issue by re-running it with an unrelated staged in-progress change (AppViewModel/PreviewAdmissionCoordinator histogram work) temporarily stashed and restored - it fails identically either way and touches no onboarding code
- git diff --check on the onboarding commit's changed files - clean
Findings:
- Low/non-blocking (maintainability): Sources/KromoraKit/Views/PreviewView.swift's completed-export banner triggers on viewModel.statusMessage.hasPrefix("Exported") rather than a structured completion signal. If ExportCoordinator status text is ever reworded/localized, or another status path starts with "Exported" for an unrelated reason, the banner would silently stop appearing or misfire, with no compiler or test signal. Currently correct against all existing ExportCoordinator status strings.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIOR57GV7D4KND1
Summary: Verified first-run onboarding: build clean, OnboardingTests and PackageSettingsTests pass in isolation from unrelated in-progress work sharing the tree, all four acceptance criteria met; one pre-existing unrelated Auto test failure confirmed out of scope.
