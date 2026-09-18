---
id: KRMA-456
title: Fix NeutralOriginSlider argument order in EffectsInspectorView
type: bug
status: ready
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - build
  - ui
  - effects
  - correctness
created: 2026-09-18T22:41:01.171Z
updated: 2026-09-18T22:41:29.303Z
order: zq
board: product
---

## Objective

Unblock Release / packaged-app compilation by fixing the `NeutralOriginSlider` call in `EffectsInspectorView` so labeled arguments match the initializer’s declaration order (`neutral` before `step`).

## Context

### Failure (blocking)

`./scripts/build-macos-app.sh` fails compiling `KromoraKit` with:

```
Sources/KromoraKit/Views/EffectsInspectorView.swift:182:17: error: argument 'neutral' must precede argument 'step'
                step: 1,
                neutral: neutral,
```

### Correct initializer signature

`Sources/KromoraKit/Views/NeutralOriginSlider.swift` (~lines 37–45):

```swift
init(
    value: Binding<Double>,
    in range: ClosedRange<Double>,
    neutral: Double,
    step: Double? = nil,
    trackStyle: SliderTrackStyle = .neutral,
    accessibilityTitle: String? = nil,
    accessibilityReadout: String? = nil,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
)
```

Swift requires call-site arguments in declaration order. `neutral:` must appear before `step:`.

### Broken call site

`EffectsValueRow` in `Sources/KromoraKit/Views/EffectsInspectorView.swift` (~178–189) currently passes `step:` then `neutral:`. That is the only known compile error of this shape; other inspectors (e.g. `DevelopInspectorView`) already pass `neutral:` in the correct position (often omitting `step`).

### Sibling build breakers (separate tickets — do not fix here)

- MainActor loss on `LUTLibrary.starterCategoryPrecedes` in `BundledLookLibrary`.
- `ResolutionPlanner` / `Self.roi` vs `ResolutionPlan.roi`.

`CIKernel` deprecation warnings in the same log are out of scope.

### Compatibility (required)

Must compile and behave correctly when building with **both** the macOS 26 SDK (Xcode 26 / CI `macos-26`) and the macOS 27 SDK (Xcode beta / local `MacOSX27.0.sdk`). Deployment target remains **macOS 14** per `Package.swift`. This change must not introduce `#available(macOS 27, …)`-only APIs or SDK-27-only symbols — it is a Swift/source fix with no OS API dependency. Verify with `swift build` (or the packaging script) on whichever SDKs are available; if only one SDK is present in the agent environment, reason from API surface (none) and note which SDK was used in the handoff comment.

## Acceptance criteria

- [ ] `EffectsValueRow`’s `NeutralOriginSlider` call compiles with arguments in declaration order: after `in:`, pass `neutral:` then `step:` (then accessibility / `onEditingChanged` as today).
- [ ] Effects inspector sliders still snap with `step: 1` and still use the row’s `neutral` for fill origin.
- [ ] No API redesign of `NeutralOriginSlider` (do not reorder the initializer to match the broken call; fix the call site).
- [ ] Grep confirms no remaining `NeutralOriginSlider(` call sites pass `step:` before `neutral:`.
- [ ] `swift build` succeeds for this diagnostic.

- [ ] Compiles cleanly under Swift 6 against the macOS 26 **and** macOS 27 SDKs (or documents which SDK was verified if only one is available); no macOS 27-only APIs.

## Out of scope

- Redesigning slider stepping / fill behavior.
- Migrating other inspectors to pass `step` unless they already need it.
- The other two Release compile errors from the same log.

## Implementation notes

1. In `EffectsInspectorView.swift` `EffectsValueRow.body`, reorder to:

   ```swift
   NeutralOriginSlider(
       value: $value,
       in: range,
       neutral: neutral,
       step: 1,
       accessibilityTitle: title,
       accessibilityReadout: readout(value),
       onEditingChanged: { editing in
           if editing { beginInteraction() }
           else { endInteraction() }
       }
   )
   ```

2. Run a quick repo grep for `step:` immediately above `neutral:` in `NeutralOriginSlider(` call sites; fix any stragglers the same way.
3. Do not change `NeutralOriginSlider`’s parameter order — other call sites and docs already assume `neutral` then `step`.
4. Constraints: Swift 6, macOS 14+, no third-party deps.

## Verification

- Note SDK used (`xcrun --show-sdk-version` / `xcodebuild -version`); both 26 and 27 are in scope for this fix.

- `swift build` — argument-order error gone.
- Optional: open Effects inspector in the app and nudge a stepped control (grain/vignette-style whole-number rows) to confirm snap + neutral fill still feel right.
- `git diff --check`
- `rg -n 'NeutralOriginSlider\(' -A6 Sources/KromoraKit/Views` and confirm argument order.

### Comment — cursor @ 2026-09-18T22:41:02.105Z

Part of a three-issue Release compile unblock set from ./scripts/build-macos-app.sh (2026-09-18). Siblings: KRMA-454 (MainActor starterCategoryPrecedes), KRMA-455 (ResolutionPlan.roi Self). Fix only the EffectsInspectorView argument order here.

### Comment — cursor @ 2026-09-18T22:41:29.303Z

Compatibility clarified: this fix is Swift call-site argument order only — must work on macOS 26 and 27 SDKs; no OS-version-gated APIs.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
