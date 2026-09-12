---
id: KRMA-380
title: Move native file dialogs and drop classification out of feature views
type: task
status: backlog
priority: medium
labels:
  - architecture
  - macos
  - ui
created: 2026-09-12T15:24:46.179Z
updated: 2026-09-12T15:24:46.786Z
order: zx
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
