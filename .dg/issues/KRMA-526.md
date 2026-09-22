---
id: KRMA-526
title: Delete unreferenced symbols and compatibility shims
type: task
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - dead-code
  - hygiene
created: 2026-09-21T20:33:07.206Z
updated: 2026-09-21T23:41:30.474Z
estimate: 5
order: zx
board: product
---

## Objective

Remove verified zero-reference functions, typealiases, views, properties, and test-only production façades while preserving any symbol that is actually used by SwiftUI entry points, protocols, key paths, or tests.

## Context and evidence

The cleanup plan identified symbols with no references in Sources or Tests after hand review, including compatibility aliases, unused views/types, unused AppViewModel helpers, unused properties, and a deprecated PhotosImportCoordinator initializer/shim. EditorDocumentCoordinator.removeSessions is an exception: session retention may represent an unbounded-history issue and should be wired to deletion/budgeting or explicitly addressed before deletion.

The candidate list is in .context/CODE_QUALITY_CLEANUP_PLAN.md under CQ-11; do not invent additional deletions from a blind grep.

## Scope

- Remove the listed unused aliases/types/views/functions/properties in small compile-safe groups.
- Keep PhotoAnalysisInspectSection and any Release test users; confirm AdjustInspectorView is truly not intended to be wired before deleting.
- Treat removeSessions as a design decision: implement bounded eviction or deletion integration, or leave it with a written rationale/follow-up.
- Remove AppViewModel's test-only Photos façade only after CQ-02 migrates tests to PhotosImportCoordinator.
- Remove the deprecated PhotosImportCoordinator initializer/shim if CQ-02 has not already done so.
- Run swift build --build-tests after each group because SwiftUI selectors/key paths can hide uses.

## Acceptance criteria

- [ ] All removed symbols are listed in the ticket completion comment with the search/compile evidence.
- [ ] No behavior change occurs; all fast and serial lanes pass.
- [ ] No test-only façade remains in shipping Sources unless it has a documented production caller.
- [ ] removeSessions has an explicit bounded-history or deliberate-retention outcome.
- [ ] No replacement symbol is added merely to preserve an unused compatibility API.

## Dependencies and coordination

Independent except for overlap with CQ-02 for Photos import shims. Coordinate with CQ-05 if legacy-mode deletions remove some candidates first.

## Likely files and checks

ColorMixerAdjustments.swift, EditClipboard.swift, PortablePhotoIdentity.swift, PhotoAsset.swift, LibraryQueryController.swift, AnalysisDebugPanel.swift, AdjustInspectorView.swift, AppViewModel extensions, EditorDocumentCoordinator.swift, EditDocumentStore.swift, MaskInteractionState.swift, mask math, InfoInspectorView.swift, PreviewSurface.swift, and tests.
