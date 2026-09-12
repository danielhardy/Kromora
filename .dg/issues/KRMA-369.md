---
id: KRMA-369
title: Toolbar should omit the left-sidebar icon and include the right editor-sidebar icon
type: feature
status: done
priority: medium
model: gpt-5.6-terra
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The toolbar does not display the left-sidebar icon/control.
      result: pass
      notes: No 'sidebar.leading' Label remains in ContentView.swift; the former Source button was replaced.
    - criterion: The toolbar displays the right editor-sidebar icon/control.
      result: pass
      notes: 'Label("Info", systemImage: "sidebar.right") routes through viewModel.toggleInspector().'
    - criterion: The right editor-sidebar control continues to open and close the editor sidebar correctly.
      result: pass
      notes: toggleInspector() toggles isInspectorPresented, which proxies inspectorState.isPresented bound to .inspector(isPresented:) on the window; guarded against no-image state consistent with disabled condition.
    - criterion: Toolbar layout remains visually coherent after the control change.
      result: pass
      notes: New disabled condition (sourceImage == nil) matches the pattern used by neighboring toolbar controls.
  checks_run:
    - swift test --filter MenuCommandTests (6 tests passed)
    - swift build (clean)
    - git diff --check 69b27e7^..69b27e7 (no whitespace issues)
    - "manual trace: toggleSourceBrowser()/isSourceBrowserPresented still reachable via Open Source Folder... menu item and NavigationStateTests, so source browsing was not dropped, only unwired from the toolbar as intended"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T02:21:08.293Z
  session: 01MTXRBWQKFGB46G50
created: 2026-09-12T02:10:00.868Z
updated: 2026-09-12T02:21:08.295Z
order: a0
board: product
---

## Objective

Adjust the toolbar sidebar controls so the toolbar omits the left-sidebar icon/control and includes the right editor-sidebar icon/control.

## Expected behavior

The toolbar should expose the right-side editor panel control while not exposing a left-sidebar control.

## Acceptance criteria

- [ ] The toolbar does not display the left-sidebar icon/control.
- [ ] The toolbar displays the right editor-sidebar icon/control.
- [ ] The right editor-sidebar control continues to open and close the editor sidebar correctly.
- [ ] Toolbar layout remains visually coherent after the control change.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-12T02:19:41.509Z

Replaced the Source toolbar control with the right-side editor inspector toggle, including state-aware accessibility text. Added regression coverage that requires the right icon, rejects the left icon, and verifies the toolbar routes through toggleInspector. Checks: swift test --filter MenuCommandTests; git diff --check. Commit: 69b27e7.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T02:21:08.293Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The toolbar does not display the left-sidebar icon/control. (pass) — No 'sidebar.leading' Label remains in ContentView.swift; the former Source button was replaced.
- [x] The toolbar displays the right editor-sidebar icon/control. (pass) — Label("Info", systemImage: "sidebar.right") routes through viewModel.toggleInspector().
- [x] The right editor-sidebar control continues to open and close the editor sidebar correctly. (pass) — toggleInspector() toggles isInspectorPresented, which proxies inspectorState.isPresented bound to .inspector(isPresented:) on the window; guarded against no-image state consistent with disabled condition.
- [x] Toolbar layout remains visually coherent after the control change. (pass) — New disabled condition (sourceImage == nil) matches the pattern used by neighboring toolbar controls.
Checks run:
- swift test --filter MenuCommandTests (6 tests passed)
- swift build (clean)
- git diff --check 69b27e7^..69b27e7 (no whitespace issues)
- manual trace: toggleSourceBrowser()/isSourceBrowserPresented still reachable via Open Source Folder... menu item and NavigationStateTests, so source browsing was not dropped, only unwired from the toolbar as intended
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTXRBWQKFGB46G50
Summary: Verified toolbar swap: left sidebar/Source button removed, right editor-sidebar (Info) toggle wired correctly; tests and build pass, no regressions found.
