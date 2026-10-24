---
id: KRMA-816
title: Make the color-grading wheel apply the hue under the drag handle
type: bug
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Handle drag toward painted hue applies that tint in all three zones
      result: pass
      notes: Disc rasterized through ColorGradingWheelMapping.wheel(at:) with palette mirroring the kernel gradingColor.
    - criterion: Handle position and stored hue unchanged
      result: pass
      notes: Mapping, gradingColor and gradingKernelVector untouched.
    - criterion: Center remains neutral white wash; zero saturation no-op
      result: pass
      notes: Radial wash retained; pixels with zero saturation left transparent.
    - criterion: Tests cover kernel hue, palette agreement, rendered rim pixels
      result: pass
      notes: ColorGradingTests (11) and ColorInspectorTests (10) pass.
  checks_run:
    - swift test --filter ColorGradingTests
    - swift test --filter ColorInspectorTests
    - scripts/ci-tests.sh warning-gate
    - scripts/ci-tests.sh fast
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T15:31:34.068Z
  session: 01MUTZ6HB7NS2SJDQ7
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
created: 2026-10-04T13:04:28.946Z
updated: 2026-10-04T15:31:34.072Z
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Views/ColorInspectorView.swift
    - Sources/KromoraKit/Models/ColorGradingAdjustments.swift
    - Sources/KromoraKit/Models/RenderPipeline.swift
    - Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal
    - Sources/KromoraKit/ViewModels/AppViewModel+Color.swift
    - Sources/KromoraKit/Views/NeutralOriginSlider.swift
    - Tests/KromoraKitTests/ColorGradingTests.swift
    - Tests/KromoraKitTests/ColorInspectorTests.swift
  docs:
    - CLAUDE.md
  issues: []
  commands:
    - swift test --filter ColorGradingTests
    - swift test --filter ColorInspectorTests
    - scripts/ci-tests.sh warning-gate
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T15:27:51.361Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

The color under the grading-wheel drag handle must be the hue applied to that zone. Dragging the shadows handle toward green must make shadows greener, toward blue must make them bluer, and the same must hold for midtones and highlights. This is a correctness bug. A user must not have to learn that green on this wheel means blue.

## Product requirement

Match hue, not a particular absolute layout. Red does not have to move to 12 o'clock. The color painted under the handle must be the hue the kernel applies for that stored angle. The center stays white (zero saturation). The rim is the full hue. The existing white radial wash stays.

Do not treat this as a tooltip or label problem. The numeric hue field can stay.

## What is wrong

Three pieces exist, and only the painted disc disagrees.

1. Drag mapping, `ColorGradingWheelMapping` in `Sources/KromoraKit/Models/ColorGradingAdjustments.swift`. The view flips AppKit's downward y, then `atan2(y, x)` stores degrees. 0° is the positive x axis (right, 3 o'clock). 90° is up. 180° is left. 270° is down. Angles increase counterclockwise. The handle is drawn from the inverse (`cos` / `sin`, y negated again for SwiftUI). `testWheelMappingReachesNeutralRimAndEveryCardinalHue` and `testVisualWheelBindingMapsGestureValuesAndUsesInteractivePreview` lock this. The handle already follows the finger.

2. Applied color, `gradingColor` in `Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal`, fed by `gradingKernelVector` (`hue / 360`). This is standard HSL: hue 0 is red, 120° is green, 180° is cyan, 240° is blue, 300° is magenta. `applyColorGrading` uses it for shadows, midtones, and highlights. Saved edits store this number. Do not change it.

3. The disc, `ColorGradingWheelControl` in `Sources/KromoraKit/Views/ColorInspectorView.swift`. It paints:

```swift
AngularGradient(
    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
    center: .center
)
```

SwiftUI's default angular gradient starts at the trailing edge (3 o'clock) and proceeds clockwise. The drag math proceeds counterclockwise from that same edge. Those are reflections of each other: a clockwise angle θ is stored as `(360 - θ)`.

Consequences, which match a wheel whose green produces blue:

- Right, 0° either way: painted red, kernel red. Looks correct.
- Left, 180° either way: painted cyan, kernel cyan. Looks correct.
- Clockwise 120°, where this gradient paints green: stored hue 240°, kernel blue.
- Clockwise 240°, where this gradient paints blue: stored hue 120°, kernel green.
- The same reflection swaps the yellow stop with the purple stop.

This is not an x/y swap. The view already converts to y-up, and the handle round-trips. Swapping x and y would move the handle off the finger. It is not a 90° rotation either: that would move red, which currently lands on red. Do not "fix" the mapping by swapping axes or adding 90°.

The named colors are a second error even after the direction is reversed. `.purple` is not HSL magenta at 300°, and `Color.green` is not guaranteed to be the kernel's hue 120. The disc has to be colored by the same hue function as `gradingColor`.

The hue slider in `SliderTrackStyle.hue` is a separate linear ramp (red at 0 through green at 1/3 to blue at 2/3). Leave it alone. Do not reverse it.

## Fix

Keep `ColorGradingWheelMapping` and `gradingColor` as they are, so existing documents do not change color and the handle does not move for a given stored hue.

Replace the `AngularGradient` of named colors. Draw the disc in the mapping's own coordinates: for each pixel, convert with the same y-up math as `ColorGradingWheelControl.point(for:in:)`, and if it is inside the circle, color it with the kernel hue at that angle. A `Canvas` (or equivalent) that calls `ColorGradingWheelMapping.wheel(at:)` is the straightforward way. Another `AngularGradient` is acceptable only when the rendered pixel test below passes; the default clockwise gradient is the bug.

Put the hue-to-RGB function in Swift next to the mapping, and make it the only source for the disc. It must implement the kernel formula (hue 0 = red, 1/3 = green, 2/3 = blue), not a second approximation. Keep the white radial wash on top so the center still reads as neutral. Keep the handle where `ColorGradingWheelMapping.point(for:)` puts it.

`ColorGradingWheelControl` is `private`. Make the palette, and the disc view if the test hosts it, `internal` so `@testable import KromoraKit` can see them. Do not make them `public`.

One control serves shadows, midtones, and highlights. Fixing the disc fixes all three.

## Tests

Add these. Do not weaken the existing mapping round-trip tests.

- Kernel pixels, in `ColorGradingTests`, on a neutral gray through `RenderPipeline.applyColorGrading` at full saturation: hue 0 is red-dominant, hue 120 is green-dominant, hue 240 is blue-dominant. This records the convention you must not change. Compare the dominant channel, not equality with the bright rim color. The kernel tints toward `gradingColor` at the source luminance, so a dark pixel stays dark.
- The Swift palette matches those same hues (0, 120, 240, and 60 / 180 / 300). A drift between the Swift copy and the kernel fails this test.
- Render the disc (the fill, not the whole inspector) at a fixed size with `NSHostingView`. Sample near the rim, clear of the handle and of the white center, at the angles `ColorGradingWheelMapping` uses:
  - hue 0, point `(1, 0)`, the right edge: red-dominant
  - hue 120, point `(cos 120°, sin 120°)`: green-dominant
  - hue 240: blue-dominant
  - hue 180: cyan (green and blue both high, red low)
- A stored hue of 120 places the handle on that green sample. The existing binding test must still see an upward drag `(x: 0, y: 0.6)` as hue 90.

The rendered sample is the gate. A gradient that only looks counterclockwise in code is not done.

## Out of scope

- Changing stored hue, `gradingKernelVector`, or `gradingColor`. That would recolor every saved grade.
- Moving red to the top of the wheel, or copying another app's wheel orientation.
- The hue slider, mixer dots, and white-balance controls.
- Rewriting drag y-flip or `atan2` order.

## Acceptance criteria

- [ ] Dragging a grading handle toward the green painted on the wheel applies a green tint in that zone. Blue, cyan, red, yellow, and magenta do the same. Shadows, midtones, and highlights share the corrected disc.
- [ ] The handle still sits on the dragged point. Stored hue is unchanged: 0° is +x and is red, 120° is green, 240° is blue, increasing counterclockwise.
- [ ] The center remains the neutral white wash. Zero saturation is still an exact no-op.
- [ ] Tests cover kernel hue, palette agreement with the kernel, and rim pixels of the rendered disc at 0°, 120°, 180°, and 240°. Existing wheel-mapping tests still pass.

## Verification

Deterministic tests only. Do not run `scripts/run-kromora-capture.sh`. Before handoff: the color-grading and color-inspector suites, `scripts/ci-tests.sh warning-gate`, `scripts/ci-tests.sh fast`, `swift format lint` on changed Swift files, `git diff --check`, and `dg validate`.

Commit on the current branch with a subject that starts `KRMA-816:`. Do not push. Do not stash, reset, or revert unrelated working-tree changes. Hand off to `review` with a short comment. Do not mark the issue done.


### Comment — codex @ 2026-10-04T15:27:50.893Z

Implemented a mapping-matched HSL wheel raster and added kernel, palette, and hosted-pixel regression coverage. ColorGradingTests, ColorInspectorTests, warning-gate, and the fast lane pass (the fast lane passed on rerun after one unrelated parallel-run library assertion, which passed in isolation). Full-file strict swift-format still reports pre-existing diagnostics outside the changed sections. Commit: 12c02bc2.

## Agent log

- 2026-10-04T15:31:34.069Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Handle drag toward painted hue applies that tint in all three zones (pass) — Disc rasterized through ColorGradingWheelMapping.wheel(at:) with palette mirroring the kernel gradingColor.
- [x] Handle position and stored hue unchanged (pass) — Mapping, gradingColor and gradingKernelVector untouched.
- [x] Center remains neutral white wash; zero saturation no-op (pass) — Radial wash retained; pixels with zero saturation left transparent.
- [x] Tests cover kernel hue, palette agreement, rendered rim pixels (pass) — ColorGradingTests (11) and ColorInspectorTests (10) pass.
Checks run:
- swift test --filter ColorGradingTests
- swift test --filter ColorInspectorTests
- scripts/ci-tests.sh warning-gate
- scripts/ci-tests.sh fast
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUTZ6HB7NS2SJDQ7
Summary: Verified: wheel disc now painted via mapping-matched HSL palette; tests pass.
