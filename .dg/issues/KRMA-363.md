---
id: KRMA-363
title: Prevent Auto toolbar icon changes from reflowing the toolbar
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Auto button width and height remain unchanged before, during, and after an Auto action, including loading, success, no-op, and failure states.
      result: pass
      notes: AutoToolbarButton layers idle and in-progress Labels in a ZStack with .fixedSize(); regression test testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState asserts equal NSHostingView fittingSize for both states. Only two visual states exist (idle/in-progress); success/no-op/failure return to idle without a distinct icon, so geometry is unaffected.
    - criterion: Neighboring toolbar controls retain their positions when the Auto icon changes; the toolbar does not reflow or visibly jump.
      result: pass
      notes: Fixed footprint of the Auto button means SwiftUI toolbar layout for sibling items is unaffected; toolbar order/spacing unchanged in the diff.
    - criterion: All Auto state icons remain centered, visually legible, and un-clipped at supported toolbar/window widths.
      result: pass
      notes: ZStack centers both Label overlays by default; fixedSize sizes to the widest state so neither is clipped.
    - criterion: Existing Auto interaction, disabled/progress behavior, tooltips, accessibility labels, and keyboard/menu affordances remain correct.
      result: pass
      notes: action closure, .accessibilityLabel/.accessibilityHint, .help, and .disabled(!viewModel.canRunAutoAdjustment) modifiers are preserved on the call site (ContentView.swift:240-246); inner Labels are accessibilityHidden so VoiceOver only announces the outer label/hint once.
    - criterion: Focus/pressed/hover states do not change the button footprint or cause a second layout shift.
      result: pass
      notes: Footprint is fixed by fixedSize() on the ZStack independent of Button interaction state; no state-dependent frame/padding was introduced.
    - criterion: Add a regression test or layout-level verification covering the icon-state transitions and stable button geometry.
      result: pass
      notes: MenuCommandTests.testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState added and passing.
    - criterion: Other toolbar controls and the existing toolbar spacing/order remain unchanged.
      result: pass
      notes: Diff is localized to the Auto button extraction; no other toolbar items touched.
  checks_run:
    - swift build
    - swift test --filter MenuCommandTests
    - scripts/ci-tests.sh fast (880 tests, 0 failures)
    - git status --porcelain (clean aside from pre-existing unrelated dg/docs untracked files)
    - dg validate (OK, only pre-existing unknown-model warnings)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-11T21:12:38.790Z
  session: 01MTXG9XLIUUYNMVUN
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - toolbar
  - ux
  - macos
created: 2026-09-11T20:35:32.804Z
updated: 2026-09-11T21:12:38.792Z
order: a0
board: product
---

## Objective

Keep the editor toolbar spatially stable when the Auto button changes its icon after activation.

## Observed behavior

Clicking Auto correctly changes the button icon to reflect the new state, but the replacement icon has a different intrinsic width. The Auto button therefore changes width and causes a subtle horizontal shift/reflow in neighboring toolbar controls. This makes the toolbar feel unstable during a normal interaction.

## Desired behavior

The Auto button may swap icons, show progress, or reflect completion/error state, but its layout footprint must remain constant. Neighboring toolbar items should not move when Auto changes state. The icon can be centered within a fixed-size frame, or the states can be layered so the widest state determines a stable footprint.

## Acceptance criteria

- [ ] Auto button width and height remain unchanged before, during, and after an Auto action, including loading, success, no-op, and failure states.
- [ ] Neighboring toolbar controls retain their positions when the Auto icon changes; the toolbar does not reflow or visibly jump.
- [ ] All Auto state icons remain centered, visually legible, and un-clipped at supported toolbar/window widths.
- [ ] Existing Auto interaction, disabled/progress behavior, tooltips, accessibility labels, and keyboard/menu affordances remain correct.
- [ ] Focus/pressed/hover states do not change the button footprint or cause a second layout shift.
- [ ] Add a regression test or layout-level verification covering the icon-state transitions and stable button geometry.
- [ ] Other toolbar controls and the existing toolbar spacing/order remain unchanged.

## Implementation notes

Inspect the Auto control in `Sources/KromoraKit/Views/ContentView.swift` and any reusable toolbar button/style. Prefer a fixed layout frame or stable overlay/alignment for the state icons over a visual-only spacing hack. Verify compact and normal editor widths and keep the fix local to the Auto control.


### Comment — codex @ 2026-09-11T21:10:12.851Z

Implemented and committed as 11908b2. AutoToolbarButton now layers the idle wand label and in-progress hourglass label in a shared fixed-size ZStack, so icon/title changes do not alter the toolbar footprint; existing action, disabled/progress behavior, tooltip, accessibility, keyboard/menu affordances, and toolbar order remain unchanged. Added a rendered NSHostingView regression test comparing idle and in-progress fitting sizes. Verification: focused layout test passed; swift test passed (1,267 passed, 48 expected skips); swift build -c release passed; git diff --check passed; dg validate passed with only pre-existing unknown-model warnings. No blockers or follow-up tickets needed.

## Agent log

- 2026-09-11T21:12:38.790Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Auto button width and height remain unchanged before, during, and after an Auto action, including loading, success, no-op, and failure states. (pass) — AutoToolbarButton layers idle and in-progress Labels in a ZStack with .fixedSize(); regression test testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState asserts equal NSHostingView fittingSize for both states. Only two visual states exist (idle/in-progress); success/no-op/failure return to idle without a distinct icon, so geometry is unaffected.
- [x] Neighboring toolbar controls retain their positions when the Auto icon changes; the toolbar does not reflow or visibly jump. (pass) — Fixed footprint of the Auto button means SwiftUI toolbar layout for sibling items is unaffected; toolbar order/spacing unchanged in the diff.
- [x] All Auto state icons remain centered, visually legible, and un-clipped at supported toolbar/window widths. (pass) — ZStack centers both Label overlays by default; fixedSize sizes to the widest state so neither is clipped.
- [x] Existing Auto interaction, disabled/progress behavior, tooltips, accessibility labels, and keyboard/menu affordances remain correct. (pass) — action closure, .accessibilityLabel/.accessibilityHint, .help, and .disabled(!viewModel.canRunAutoAdjustment) modifiers are preserved on the call site (ContentView.swift:240-246); inner Labels are accessibilityHidden so VoiceOver only announces the outer label/hint once.
- [x] Focus/pressed/hover states do not change the button footprint or cause a second layout shift. (pass) — Footprint is fixed by fixedSize() on the ZStack independent of Button interaction state; no state-dependent frame/padding was introduced.
- [x] Add a regression test or layout-level verification covering the icon-state transitions and stable button geometry. (pass) — MenuCommandTests.testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState added and passing.
- [x] Other toolbar controls and the existing toolbar spacing/order remain unchanged. (pass) — Diff is localized to the Auto button extraction; no other toolbar items touched.
Checks run:
- swift build
- swift test --filter MenuCommandTests
- scripts/ci-tests.sh fast (880 tests, 0 failures)
- git status --porcelain (clean aside from pre-existing unrelated dg/docs untracked files)
- dg validate (OK, only pre-existing unknown-model warnings)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTXG9XLIUUYNMVUN
Summary: Independent review confirms the Auto toolbar button's fixed-footprint ZStack fix is correct, localized, and covered by a passing regression test; full fast suite (880 tests) and dg validate pass with a clean tree.
