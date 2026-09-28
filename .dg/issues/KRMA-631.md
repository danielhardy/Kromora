---
id: KRMA-631
title: Toggle a film-inspired photo metadata overlay
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A keyboard shortcut toggles the photo information overlay on and off while the photo preview is active; use plain I unless implementation discovers a concrete conflict.
      result: pass
      notes: Plain I posts .toggleCaptureMetadataOverlay only when a photo is loaded and no conflicting modifier/text-input context is active; ⌘I remains the Info Inspector shortcut. Covered by KeyMonitorTests.testPlainIAndOnlyPlainIWithAnOpenPhotoTogglesCaptureOverlay.
    - criterion: The overlay sits in a bottom corner of the preview and shows ISO, shutter speed, aperture, and focal length when available.
      result: pass
      notes: CaptureMetadataOverlay is pinned bottom-leading in PreviewView; rows come from ImageMetadata.captureOverlayRows (ISO, Shutter, Aperture, Focal length).
    - criterion: Styling is restrained and legible over both bright and dark images with a film-inspired feel.
      result: pass
      notes: Semi-opaque black background, thin white border, monospaced uppercase labels; consistent with existing ComparisonBadge treatment. Visual judgment call, not independently pixel-tested.
    - criterion: Missing metadata is omitted cleanly without placeholders.
      result: pass
      notes: captureOverlayRows uses compactMap over optional fields; overlay is not shown at all when rows is empty. Covered by CaptureMetadataOverlayTests.
    - criterion: Toggling the overlay does not change photo edits, selection, or Info Inspector state.
      result: pass
      notes: isCaptureOverlayVisible is local @State on PreviewView, independent of EditDocument/selection/inspector state.
    - criterion: Shortcut and toggle are discoverable via the View menu with accessibility labels.
      result: pass
      notes: MenuCommands adds "Capture Info Overlay (I)" with accessibilityLabel "Toggle capture information overlay"; overlay itself exposes an accessibility label/value.
    - criterion: Overlay state updates when the displayed photo changes and does not remain stale.
      result: pass
      notes: viewModel.metadata is @Published and reassigned on photo transitions; captureOverlayRows recomputes from current metadata on every render.
  checks_run:
    - swift build (working tree, HEAD 91c485c) - success
    - swift test --filter 'CaptureMetadataOverlayTests|KeyMonitorTests' (working tree) - 19/19 passed
    - scripts/agent-worktree.sh create (isolated worktree at HEAD 91c485c, no uncommitted WIP) for clean-baseline verification
    - scripts/ci-tests.sh fast (isolated worktree) - 1 pre-existing unrelated failure (AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent); remaining suite passes with --skip on that suite
    - scripts/ci-tests.sh serial (isolated worktree) - 4 pre-existing unrelated failures (IdentityRegressionGateTests, PreviewCutoverTests x2, ThumbnailTests), confirmed deterministic (not flaky) via isolated re-run; KeyMonitorTests within this lane pass
    - git diff --check on the KRMA-631 commit (3c42d65) - clean
  findings:
    - "test-infra: Tests/KromoraKitTests/AutoEnhancementCoordinatorTests.swift testFrozenTargetsPreserveLowKeyIntent fails deterministically at HEAD (0.48 vs 0.25 +/- 1e-06), unrelated to KRMA-631's diff. Filed as KRMA-637."
    - "test-infra: scripts/ci-tests.sh serial has 4 pre-existing deterministic failures at HEAD (IdentityRegressionGateTests, PreviewCutoverTests x2, ThumbnailTests) on missing fixture files, unrelated to KRMA-631's diff. Filed as KRMA-638."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T17:28:15.756Z
  session: 01MUINFD1D278EEX15
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
created: 2026-09-26T14:39:57.424Z
updated: 2026-09-28T14:41:37.307Z
blockers: []
order: udvdjhhk
board: product
---

## Objective

Let a user reveal a compact set of capture settings over the photo preview, then hide it again immediately with a keyboard shortcut.

## Context

The Info Inspector already exposes EXIF metadata, including aperture, shutter speed, ISO, exposure bias, and focal length. The preview has no glanceable metadata display today. A discreet, well-composed overlay should feel like camera information printed on a professional film contact sheet or viewfinder, while keeping the photo primary.

The user suggested `I` as a shortcut. The app currently assigns `⌘I` to Info Inspector; the plain `I` key is not assigned in the global shortcut handler.

## Acceptance criteria

- [ ] A keyboard shortcut toggles the photo information overlay on and off while the photo preview is active; use plain `I` unless implementation discovers a concrete conflict.
- [ ] The overlay sits in a bottom corner of the preview and shows available exposure details: ISO, shutter speed, and aperture. Include focal length when available.
- [ ] Styling is restrained and legible over both bright and dark images, with clear typographic hierarchy and a professional analog-camera or film-inspired feel.
- [ ] Missing metadata is omitted cleanly, without placeholders or empty labels; the overlay handles photos with partial or no capture metadata.
- [ ] Toggling the overlay does not change photo edits, selection, or the existing Info Inspector state.
- [ ] The shortcut and overlay toggle are discoverable through the View menu or equivalent accessible UI. Controls expose meaningful accessibility labels.
- [ ] Overlay state updates when the displayed photo changes and does not remain stale from the prior photo.

## Implementation notes

Reuse `ImageMetadata` values where practical instead of parsing EXIF a second time. Review interactions with preview modes (including comparison and crop) so the overlay remains predictable and does not obstruct core editing. Add focused regression coverage for shortcut routing and metadata visibility behavior.


### Comment — codex @ 2026-09-26T17:09:36.030Z

Implemented the plain I capture overlay toggle, View menu entry, and compact optional exposure readout. Added focused shortcut and metadata visibility tests. Verification: swift build and git diff --check pass; filtered swift test is blocked at compilation by pre-existing RetouchModelTests.swift references to missing EditDocument.retouch.

## Agent log

- 2026-09-26T17:28:15.757Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A keyboard shortcut toggles the photo information overlay on and off while the photo preview is active; use plain I unless implementation discovers a concrete conflict. (pass) — Plain I posts .toggleCaptureMetadataOverlay only when a photo is loaded and no conflicting modifier/text-input context is active; ⌘I remains the Info Inspector shortcut. Covered by KeyMonitorTests.testPlainIAndOnlyPlainIWithAnOpenPhotoTogglesCaptureOverlay.
- [x] The overlay sits in a bottom corner of the preview and shows ISO, shutter speed, aperture, and focal length when available. (pass) — CaptureMetadataOverlay is pinned bottom-leading in PreviewView; rows come from ImageMetadata.captureOverlayRows (ISO, Shutter, Aperture, Focal length).
- [x] Styling is restrained and legible over both bright and dark images with a film-inspired feel. (pass) — Semi-opaque black background, thin white border, monospaced uppercase labels; consistent with existing ComparisonBadge treatment. Visual judgment call, not independently pixel-tested.
- [x] Missing metadata is omitted cleanly without placeholders. (pass) — captureOverlayRows uses compactMap over optional fields; overlay is not shown at all when rows is empty. Covered by CaptureMetadataOverlayTests.
- [x] Toggling the overlay does not change photo edits, selection, or Info Inspector state. (pass) — isCaptureOverlayVisible is local @State on PreviewView, independent of EditDocument/selection/inspector state.
- [x] Shortcut and toggle are discoverable via the View menu with accessibility labels. (pass) — MenuCommands adds "Capture Info Overlay (I)" with accessibilityLabel "Toggle capture information overlay"; overlay itself exposes an accessibility label/value.
- [x] Overlay state updates when the displayed photo changes and does not remain stale. (pass) — viewModel.metadata is @Published and reassigned on photo transitions; captureOverlayRows recomputes from current metadata on every render.
Checks run:
- swift build (working tree, HEAD 91c485c) - success
- swift test --filter 'CaptureMetadataOverlayTests|KeyMonitorTests' (working tree) - 19/19 passed
- scripts/agent-worktree.sh create (isolated worktree at HEAD 91c485c, no uncommitted WIP) for clean-baseline verification
- scripts/ci-tests.sh fast (isolated worktree) - 1 pre-existing unrelated failure (AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent); remaining suite passes with --skip on that suite
- scripts/ci-tests.sh serial (isolated worktree) - 4 pre-existing unrelated failures (IdentityRegressionGateTests, PreviewCutoverTests x2, ThumbnailTests), confirmed deterministic (not flaky) via isolated re-run; KeyMonitorTests within this lane pass
- git diff --check on the KRMA-631 commit (3c42d65) - clean
Findings:
- test-infra: Tests/KromoraKitTests/AutoEnhancementCoordinatorTests.swift testFrozenTargetsPreserveLowKeyIntent fails deterministically at HEAD (0.48 vs 0.25 +/- 1e-06), unrelated to KRMA-631's diff. Filed as KRMA-637.
- test-infra: scripts/ci-tests.sh serial has 4 pre-existing deterministic failures at HEAD (IdentityRegressionGateTests, PreviewCutoverTests x2, ThumbnailTests) on missing fixture files, unrelated to KRMA-631's diff. Filed as KRMA-638.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUINFD1D278EEX15
Summary: Verified: capture metadata overlay (plain I toggle, View menu entry, bottom-corner overlay) meets all acceptance criteria; two unrelated pre-existing test failures found and filed as child tickets KRMA-637/KRMA-638.
