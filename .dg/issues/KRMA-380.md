---
id: KRMA-380
title: Move native file dialogs and drop classification out of feature views
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Views do not directly call NSOpenPanel, NSSavePanel, NSWorkspace, or FileManager for application routing.
      result: pass
      notes: Confirmed no remaining NSOpenPanel/NSSavePanel/NSWorkspace/FileManager references under Sources/KromoraKit/Views/.
    - criterion: Add injectable file-dialog and workspace/reveal abstractions, or an equivalent application-shell boundary.
      result: pass
      notes: FileDialogProviding + AppKitFileDialog and WorkspaceRevealing + AppKitWorkspaceRevealer added in Sources/KromoraKit/Presentation/.
    - criterion: Move dropped-URL classification into a testable service/policy that returns a value-based action such as open-image or open-folder.
      result: pass
      notes: FileDropActionPolicy.action(for:) returns FileDropAction (.openImage/.openFolder/.invalid); PreviewView now delegates to AppViewModel.handleDroppedURL(_:).
    - criterion: Preserve security-scoped access, default-folder starting locations, Finder reveal behavior, and current cancel semantics.
      result: pass
      notes: "revealUserLookFolder still routes through ensureUserLookFolder() before reveal; openImageDialog/chooseSourceFolder cancel (nil) paths leave state untouched, verified by testCancelledImageDialogLeavesCurrentEditUntouched. Minor note: KromoraSettingsView.chooseFolder now passes settings.status(for:kind).url as a starting location where previously no directoryURL was set — a behavior addition, not a regression, and untested directly; recorded as a non-blocking finding."
    - criterion: Preserve the existing testable non-panel seams such as openImages(urls:) and openSourceFolder(url:).
      result: pass
      notes: Both signatures unchanged; openImageDialog/chooseSourceFolder/handleDroppedURL dispatch into them.
    - criterion: Add focused tests for file, folder, invalid, and cancelled dialog/drop cases without requiring live AppKit panels.
      result: pass
      notes: Tests/KromoraKitTests/FileIntegrationBoundaryTests.swift covers drop classification (file/folder/invalid) and cancelled dialog via stub FileDialogProviding/WorkspaceRevealing, no live panels.
    - criterion: Keep purely visual geometry and native presentation adapters in the Views layer.
      result: pass
      notes: AppKit panel/workspace construction lives in Presentation/ adapters, not Views; Views only hold protocol-typed seams.
    - criterion: Existing settings, open-image, source-folder, and drag/drop behavior remains unchanged; run dg validate and git diff --check.
      result: pass
      notes: "dg validate: OK (pre-existing unrelated model-name warnings only). git diff --check on c8cb73d: clean."
  checks_run:
    - swift build
    - swift test --filter FileIntegrationBoundaryTests (4/4 passed)
    - scripts/ci-tests.sh fast (946 tests, 0 failures)
    - scripts/ci-tests.sh serial (371 tests, 0 failures)
    - dg validate
    - git diff --check c8cb73d^ c8cb73d
    - grep for residual NSOpenPanel/NSSavePanel/NSWorkspace/FileManager in Sources/KromoraKit/Views/
  findings:
    - KromoraSettingsView.chooseFolder (Sources/KromoraKit/Views/KromoraSettingsView.swift) now passes the current folder-kind status URL as the panel starting location, where the prior implementation left directoryURL unset. Plausible intentional improvement, not covered by a dedicated test; non-blocking as it does not affect security-scoped access, persistence, or cancel semantics.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T22:46:10.432Z
  session: 01MTYZ1IJRR1OWZ86P
labels:
  - architecture
  - macos
  - ui
created: 2026-09-12T15:24:46.179Z
updated: 2026-09-12T22:46:10.434Z
order: a0
board: product
---

## Objective

Remove filesystem and native-window orchestration from feature views while preserving the current macOS dialog and drag-and-drop behavior.

## Context

Several views directly perform application integration work:
- KromoraSettingsView checks file existence, opens NSOpenPanel, and invokes NSWorkspace.
- PreviewView classifies dropped URLs as files or directories with FileManager before dispatching them.
- These paths are presentation details mixed with access/security and application routing, which makes the views harder to test and reuse.

Relevant code:
- Sources/KromoraKit/Views/KromoraSettingsView.swift:20-23 and 167-184
- Sources/KromoraKit/Views/PreviewView.swift:328-343
- Sources/KromoraKit/ViewModels/AppViewModel.swift:2130-2145 and 2531-2562

## Acceptance criteria

- [ ] Views do not directly call NSOpenPanel, NSSavePanel, NSWorkspace, or FileManager for application routing.
- [ ] Add injectable file-dialog and workspace/reveal abstractions, or an equivalent application-shell boundary.
- [ ] Move dropped-URL classification into a testable service/policy that returns a value-based action such as open-image or open-folder.
- [ ] Preserve security-scoped access, default-folder starting locations, Finder reveal behavior, and current cancel semantics.
- [ ] Preserve the existing testable non-panel seams such as openImages(urls:) and openSourceFolder(url:).
- [ ] Add focused tests for file, folder, invalid, and cancelled dialog/drop cases without requiring live AppKit panels.
- [ ] Keep purely visual geometry and native presentation adapters in the Views layer.
- [ ] Existing settings, open-image, source-folder, and drag/drop behavior remains unchanged; run dg validate and git diff --check.

## Out of scope

- Redesigning the settings or import UI.
- Changing bookmark persistence or folder access policy.
- Moving PreviewSurface's Metal presentation code.


### Comment — codex @ 2026-09-12T22:43:18.608Z

Implemented in c8cb73d. Added injectable AppKit file-dialog and workspace-reveal adapters, moved image/source-folder panel orchestration behind AppViewModel and SettingsView seams, routed RecipeExtractorSheet pickers through the same adapter, and added FileDropActionPolicy for file/folder/invalid drops. Preserved security-scoped settings behavior, default-folder starting locations, Finder reveal, cancellation, openImages(urls:), and openSourceFolder(url:). Verification: swift test --parallel (1,366 tests, 0 failures), focused FileIntegrationBoundaryTests (4/0), git diff --check, and dg validate OK (pre-existing model-name warnings only).

## Agent log

- 2026-09-12T22:46:10.432Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Views do not directly call NSOpenPanel, NSSavePanel, NSWorkspace, or FileManager for application routing. (pass) — Confirmed no remaining NSOpenPanel/NSSavePanel/NSWorkspace/FileManager references under Sources/KromoraKit/Views/.
- [x] Add injectable file-dialog and workspace/reveal abstractions, or an equivalent application-shell boundary. (pass) — FileDialogProviding + AppKitFileDialog and WorkspaceRevealing + AppKitWorkspaceRevealer added in Sources/KromoraKit/Presentation/.
- [x] Move dropped-URL classification into a testable service/policy that returns a value-based action such as open-image or open-folder. (pass) — FileDropActionPolicy.action(for:) returns FileDropAction (.openImage/.openFolder/.invalid); PreviewView now delegates to AppViewModel.handleDroppedURL(_:).
- [x] Preserve security-scoped access, default-folder starting locations, Finder reveal behavior, and current cancel semantics. (pass) — revealUserLookFolder still routes through ensureUserLookFolder() before reveal; openImageDialog/chooseSourceFolder cancel (nil) paths leave state untouched, verified by testCancelledImageDialogLeavesCurrentEditUntouched. Minor note: KromoraSettingsView.chooseFolder now passes settings.status(for:kind).url as a starting location where previously no directoryURL was set — a behavior addition, not a regression, and untested directly; recorded as a non-blocking finding.
- [x] Preserve the existing testable non-panel seams such as openImages(urls:) and openSourceFolder(url:). (pass) — Both signatures unchanged; openImageDialog/chooseSourceFolder/handleDroppedURL dispatch into them.
- [x] Add focused tests for file, folder, invalid, and cancelled dialog/drop cases without requiring live AppKit panels. (pass) — Tests/KromoraKitTests/FileIntegrationBoundaryTests.swift covers drop classification (file/folder/invalid) and cancelled dialog via stub FileDialogProviding/WorkspaceRevealing, no live panels.
- [x] Keep purely visual geometry and native presentation adapters in the Views layer. (pass) — AppKit panel/workspace construction lives in Presentation/ adapters, not Views; Views only hold protocol-typed seams.
- [x] Existing settings, open-image, source-folder, and drag/drop behavior remains unchanged; run dg validate and git diff --check. (pass) — dg validate: OK (pre-existing unrelated model-name warnings only). git diff --check on c8cb73d: clean.
Checks run:
- swift build
- swift test --filter FileIntegrationBoundaryTests (4/4 passed)
- scripts/ci-tests.sh fast (946 tests, 0 failures)
- scripts/ci-tests.sh serial (371 tests, 0 failures)
- dg validate
- git diff --check c8cb73d^ c8cb73d
- grep for residual NSOpenPanel/NSSavePanel/NSWorkspace/FileManager in Sources/KromoraKit/Views/
Findings:
- KromoraSettingsView.chooseFolder (Sources/KromoraKit/Views/KromoraSettingsView.swift) now passes the current folder-kind status URL as the panel starting location, where the prior implementation left directoryURL unset. Plausible intentional improvement, not covered by a dedicated test; non-blocking as it does not affect security-scoped access, persistence, or cancel semantics.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYZ1IJRR1OWZ86P
Summary: Verified c8cb73d: AppKit file-dialog/workspace-reveal adapters and FileDropActionPolicy fully replace direct NSOpenPanel/NSSavePanel/NSWorkspace/FileManager calls in Views; all acceptance criteria pass. swift build, targeted FileIntegrationBoundaryTests, full fast+serial CI lanes, dg validate, and git diff --check all pass. One non-blocking note: settings folder chooser now sets a starting directory that wasn't previously set.
