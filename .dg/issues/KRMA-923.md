---
id: KRMA-923
title: Color-manage the editing canvas (set MTKView layer color space)
type: task
status: done
priority: urgent
agent: codex
verification_agent: claude
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Canvas colorspace set to WorkingSpace.current.cgColorSpace in makeNSView, persists across updates
      result: pass
    - criterion: New PreviewSurfaceTests test asserts non-nil colorspace equal by name
      result: pass
      notes: Covers creation and a real SwiftUI update.
    - criterion: Presentation tests still pass / serial lane
      result: pass
      notes: "PreviewSurfaceTests re-run: 53 tests, 0 failures. Full serial lane per implementer: exit 0."
    - criterion: ENGINEERING_GUIDE paragraph
      result: pass
    - criterion: Review comment states manual Digital Color Meter check
      result: pass
      notes: Not performed; honestly stated.
    - criterion: Build warning-free, Swift 6 clean
      result: pass
      notes: One-line change; no escape hatches.
    - criterion: ci-tests fast
      result: pass
      notes: Only the known StoredEditAdoption test failed; isolated rerun passed per implementer.
  checks_run:
    - git show 4a0abae2 diff review
    - swift test --filter PreviewSurfaceTests (53 pass)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: unknown
  completed_at: 2026-10-13T15:12:38.213Z
  session: 01MV6TKNFRPKN1U4FF
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - color
  - preview
created: 2026-10-13T14:47:34.254Z
updated: 2026-10-13T15:12:38.216Z
parent: KRMA-922
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T15:12:02.564Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make the Edit canvas (`MTKView`) color-managed so a photo looks the same on the canvas as in grid
thumbnails, exported files, and Preview.app on a Display P3 Mac.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M1.

- `Sources/KromoraKit/Views/PreviewSurface.swift` (~L1154-1185, `makeNSView`) creates a
  `PreviewMTKView`, sets `view.colorPixelFormat = .bgra8Unorm`, and never sets a color space.
- `Sources/KromoraKit/Resources/PreviewSurface.metal` samples the preview texture straight through.
- With a nil `CAMetalLayer.colorspace`, Core Animation does not color-match, so sRGB-encoded pixels
  reach a P3 panel unconverted and look over-saturated next to color-managed `NSImage`/`CGImage`.
- The render pipeline's output space is `WorkingSpace.current` (`Sources/KromoraKit/Models/
  WorkingSpace.swift`, currently `.sRGB`); `WorkingSpace.cgColorSpace` gives the `CGColorSpace`.
  The canvas must be tagged with the SAME space the pixels are encoded in, so flipping
  `WorkingSpace.current` later (ticket "Move preview to Display P3") stays a one-line change.
- `MTKView` is backed by a `CAMetalLayer`; `MTKView.colorspace` (or `(view.layer as?
  CAMetalLayer)?.colorspace`) sets it.

## Acceptance criteria

- [ ] The canvas `MTKView`'s layer color space is set to `WorkingSpace.current.cgColorSpace` in
      `makeNSView` (not hard-coded sRGB), and stays set across `updateNSView`.
- [ ] A new test in `Tests/KromoraKitTests/PreviewSurfaceTests.swift` (serial lane; find how other
      tests there build a surface/view) asserts the created view's `colorspace` is non-nil and equals
      `WorkingSpace.current.cgColorSpace` (compare by `CGColorSpace.name`).
- [ ] The presentation path still passes its existing tests (`PreviewSurfaceTests`,
      `PreviewTextureEdgeCoverageTests`, `PreviewCutoverTests`): `scripts/ci-tests.sh serial` exits 0.
- [ ] `docs/ENGINEERING_GUIDE.md` has one short paragraph under the preview/presentation section
      stating the canvas is tagged with `WorkingSpace.current`.
- [ ] A review comment states the manual check a human should do (Digital Color Meter on a saturated
      photo: canvas vs grid thumbnail vs exported JPEG opened in Preview.app should now agree). You
      cannot run it; say so rather than claiming it.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## Implementation notes

Do NOT change `WorkingSpace.current`, the Metal shader, or the pixel format; this ticket only tags
the layer. Do NOT run `scripts/run-kromora-capture.sh` (display-bound; see CLAUDE.md).


### Comment — codex @ 2026-10-13T15:11:59.340Z

Implemented in commit 4a0abae2 (KRMA-923: color-manage the editing canvas). PreviewSurfaceView.makeNSView now sets MTKView.colorspace to WorkingSpace.current.cgColorSpace. A hosted-view regression test compares CGColorSpace.name at creation and after a real SwiftUI update, confirming that the existing canvas retains the tag. Added the presentation contract to docs/ENGINEERING_GUIDE.md. WorkingSpace.current, the Metal shader, and the pixel format are unchanged.

Validation: swift build exited 0 without warnings; scripts/ci-tests.sh serial exited 0 (527 tests, zero failures, including PreviewSurfaceTests and PreviewCutoverTests). scripts/ci-tests.sh fast exited 1 after all 1779 cases, with only StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto failing at its existing line-364 assertion. Its required isolated rerun, swift test --filter StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto, exited 0 (1 test, 1.402 seconds). This is the separately tracked exception permitted by the issue; no changes were made to that test. PreviewTextureEdgeCoverageTests and PackageSettingsTests had no reported failures, including Swift 6 language-mode and concurrency-escape-hatch invariants. Test compilation reported the pre-existing ColorMixerTests.swift:193 unused-name warning from release-review finding M4. git diff --cached --check passed. All started commands finished and their final output and exit statuses were inspected.

Manual check for a human: on a Display P3 Mac, use Digital Color Meter on the same saturated photo region in the Edit canvas, grid thumbnail, and exported JPEG opened in Preview.app; the readings should agree. I cannot perform this hands-on comparison and have not claimed it passed. No display-bound capture was run.

## Agent log

- 2026-10-13T15:12:38.213Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Canvas colorspace set to WorkingSpace.current.cgColorSpace in makeNSView, persists across updates (pass)
- [x] New PreviewSurfaceTests test asserts non-nil colorspace equal by name (pass) — Covers creation and a real SwiftUI update.
- [x] Presentation tests still pass / serial lane (pass) — PreviewSurfaceTests re-run: 53 tests, 0 failures. Full serial lane per implementer: exit 0.
- [x] ENGINEERING_GUIDE paragraph (pass)
- [x] Review comment states manual Digital Color Meter check (pass) — Not performed; honestly stated.
- [x] Build warning-free, Swift 6 clean (pass) — One-line change; no escape hatches.
- [x] ci-tests fast (pass) — Only the known StoredEditAdoption test failed; isolated rerun passed per implementer.
Checks run:
- git show 4a0abae2 diff review
- swift test --filter PreviewSurfaceTests (53 pass)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: unknown
Pickup session: 01MV6TKNFRPKN1U4FF
