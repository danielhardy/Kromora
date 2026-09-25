---
id: KRMA-563
title: Simplify the masking UI and editing workflow
type: feature
status: review
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - masking
  - ui-ux
created: 2026-09-24T14:07:05.300Z
updated: 2026-09-25T03:54:20.748Z
blockers: []
order: x
board: product
---

## Objective

Improve the masking UI and editing workflow so creating, understanding, and working with masks feels clear and straightforward. The current experience feels overly complex, with layers and components obscuring the main masking tasks.

## Acceptance criteria

- The masking workspace makes the available masks, the current selection, and the effect of editing a mask easy to understand.
- Common masking tasks require fewer conceptual steps and the relevant controls are grouped in a clear, predictable way.
- Existing supported mask types and editing capabilities remain available through the revised experience.
- Remove or rework UI layers and components that add complexity without helping users complete masking tasks.
- The revised flow is reviewed in the running app for clarity and consistency with the Edit workspace.

## Context

This ticket captures the UX goal and leaves the interaction and implementation design open. No specific mask model or editing behavior is prescribed.


### Comment — claude @ 2026-09-24T14:42:35.930Z

Reworked MaskingWorkspace into task order: pointer-only canvas tools (removed Foreground/Background pseudo-tools that captured the canvas and did nothing) with a contextual hint; brush settings shown whenever Brush/Erase is active; empty state offers each mask kind directly; whole-row mask selection with type icon; selected mask shows Adjustments (incl. Amount) and Mask sections, with part combine/solo/order only for multi-part masks; overlay settings collapsed at the bottom with show/hide in the header; InspectorDisclosure sections as in the Edit inspectors. A Linear/Radial drag on a non-matching mask now draws a new gradient mask (was a silent no-op) and a stray click restores selection. All mask types and capabilities remain. Checks: swift build (zero warnings); MaskingWorkspace/MaskingPanel/SmartMask/LocalMaskRendering/KeyMonitor tests (105, 3 new); scripts/ci-tests.sh fast (1193, pass); git diff --check; dg validate. scripts/ci-tests.sh serial has 7 failures (IdentityRegressionGate relocation, 4 PreviewCutover, ThumbnailTests import) that reproduce identically on a clean HEAD worktree, so pre-existing and unrelated. NOT DONE: AC5 in-app review. The app launched with an isolated CFFIXED_USER_HOME, but this session lacks Screen Recording and Accessibility permission, and offscreen rendering drops SwiftUI text, so the flow still needs a human look in the running app. Commit 2179649.


### Comment — claude @ 2026-09-24T15:05:37.019Z

Follow-up from user feedback (erasing showed an extra eraser overlay instead of removing the wash). Commit e1660a9: overlay now always shows the selected mask's effective coverage (solo still isolates a part); the live brush/erase stroke is composited into the wash layer (erase cuts coverage out) and held until the resolved overlay arrives; brush ring shows whenever Brush/Erase is active, shows feather, dashed for Erase, hides on canvas exit; crosshair/open-hand cursor; unified white guide/knob styling for linear and radial; removed the dashed canvas frame for smart masks; mask adjustments grouped Light/Color/Effects. Checks: swift build zero warnings; masking suites pass (1 new test); scripts/ci-tests.sh fast 1194 pass; git diff --check. AC5 in-app visual review still outstanding (no Screen Recording/Accessibility permission in this session).


### Comment — claude @ 2026-09-24T15:16:51.991Z

Follow-up from user testing. 6b85358: fixed a render bug (not only overlay): LocalMaskRenderer placed 256px brush tiles at their top-down row offset in Core Image's bottom-up space, mirroring tile rows for any frame taller than one tile, so brush/erase coverage landed in the wrong band in preview, overlay, and export (the overlay jumped after each stroke; hard edges at tile boundaries). Regression test paints near the top of a multi-tile frame. d91b8e4: Option-scroll resizes the brush; plain scroll and pinch zoom the canvas again while a mask tool is active (the pointer surface was swallowing them). Checks: build zero warnings; LocalMaskRendering/MetalKernelParity/MaskingWorkspace/KeyMonitor suites pass; scripts/ci-tests.sh fast 1195 pass. Seen in the user's screenshot, out of scope here: the status bar showed PortablePackageError 9 (malformedXMP), rendered as a generic 'operation couldn't be completed' message.


### Comment — claude @ 2026-09-24T15:31:40.582Z

Follow-up from user testing (slow; erase not applied after mouse-up; brush part not visible under gradient). 1836ad4: brush rasterization was region area x samples per render size (~12 s debug for a long erase on a 2400x1600 frame; overlay and each preview size rasterize separately), so the preview lagged far behind the overlay. Now stamps each dab over its reach in sample order: byte-identical output (benchmark checksum unchanged; new per-pixel reference test), 6.5x faster. New end-to-end render test confirms an erased band is unadjusted while the rest of the mask is. 4b6fe34: multi-part masks list their parts indented under the mask row (combine glyph, icon, name, actions menu); selecting a part targets canvas gestures and shows its controls in the Mask section, which no longer repeats the part list. Checks: build zero warnings; mask suites pass; scripts/ci-tests.sh fast 1195 pass. Needs user re-test to confirm the post-erase preview now settles promptly.


### Comment — claude @ 2026-09-24T19:09:21.700Z

Follow-up (align to how a photographer thinks) 6bbf375: O toggles the mask overlay; overlay style/color/opacity moved to Settings > Masking (persisted, KromoraSettings.maskOverlayAppearance) and removed from the inspector; mask controls read in % and degrees with photographer terms (Feather, Strength, Soften edges); removed instruction paragraph, per-gradient reset buttons, duplicate per-part invert (now in part menu); Add and Subtract menus replace 'Add or Subtract...'; eye replaces the switch on mask rows and actions appear on hover. Checks: build zero warnings; settings/masking/keymonitor suites pass (2 new tests); scripts/ci-tests.sh fast pass (one run hit a flaky wall-clock test, EditPersistenceIntegrationTests.testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp, which passes 3/3 alone; rerun green).
