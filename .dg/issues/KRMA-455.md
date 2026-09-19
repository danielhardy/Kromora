---
id: KRMA-455
title: Fix ResolutionPlanner.plan calling ResolutionPlan.roi via wrong Self
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: ResolutionPlanner.plan calls ResolutionPlan.roi without duplicating the helper
      result: pass
      notes: Sources/KromoraKit/Models/ResolutionPlanner.swift uses ResolutionPlan.roi at the complete-presented-photo check; the fix is present in b26624f4a9ce115dd8750452d2173f45bc87114.
    - criterion: ROI and hysteresis behavior remains correct
      result: pass
      notes: The existing ResolutionPlan.roi predicate and planner hysteresis logic are unchanged; CropROITests fit/zoom coverage passed.
    - criterion: Builds under the available Swift 6 SDK
      result: pass
      notes: swift build passed with Swift 6.4, Xcode 27.0, macOS 27.0 SDK. No SDK-27-only API was introduced.
  checks_run:
    - swift build
    - swift test --filter CropROITests (8 passed, 0 failures)
    - xcrun --show-sdk-version (27.0)
    - xcodebuild -version (Xcode 27.0)
    - git diff --check
    - dg validate (OK; pre-existing model-name warnings only)
  findings: []
  fixes: []
  verification_commits:
    - b26624f4a9ce115dd8750452d2173f45bc87114
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-19T01:43:13.917Z
  session: 01MU7Q1ZERHJBBMEGW
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - build
  - preview
  - resolution
  - correctness
created: 2026-09-18T22:41:00.748Z
updated: 2026-09-19T01:43:13.919Z
order: zh
board: product
commits:
  - b26624f4a9ce115dd8750452d2173f45bc87114
---

## Objective

Unblock Release / packaged-app compilation by fixing the `ResolutionPlanner.plan` call that references `Self.roi`, which does not exist on `ResolutionPlanner` — the helper lives on `ResolutionPlan`.

## Context

### Failure (blocking)

`./scripts/build-macos-app.sh` fails compiling `KromoraKit` with:

```
Sources/KromoraKit/Models/ResolutionPlanner.swift:147:43: error: type 'ResolutionPlanner' has no member 'roi'
        let completePresentedPhoto = Self.roi(
            visibleSourceRect, coversCrop: rect, nativeExtent: native
        )
```

### Type layout (easy to misread)

In `Sources/KromoraKit/Models/ResolutionPlanner.swift`:

| Type | Role |
|------|------|
| `ResolutionPlan` (struct, ~line 20) | Immutable plan result for one canvas request |
| `ResolutionPlanner` (struct, ~line 93) | Stateful hysteresis planner; `plan(...)` returns a `ResolutionPlan` |

`static func roi(_ roi: CGRect, coversCrop cropRect: CGRect, nativeExtent: CGSize) -> Bool` is defined on **`ResolutionPlan`** (~line 62), not on `ResolutionPlanner`.

Inside `ResolutionPlan.coversPresentedPhoto(nativeExtent:)` the correct call already exists:

```swift
Self.roi(visibleSourceRect, coversCrop: cropRect, nativeExtent: nativeExtent)
```

There `Self` is `ResolutionPlan`. Inside `ResolutionPlanner.plan`, `Self` is `ResolutionPlanner`, so the same spelling is a compile error.

### What the call is trying to do

Around lines 135–155, after computing `visibleSourceRect`, the planner detects whether the viewport shows the **complete presented photo** (fit / full-crop coverage). If so, and the hysteresis `selectedLevel` is still ≥2 levels above the adequate fit level, it clears hysteresis (`current: nil`) so fit does not keep an oversized native decode that can fail and leave blank edges under the fit transform. Semantics must stay identical — only the type qualification is wrong.

### Sibling build breakers (separate tickets — do not fix here)

- MainActor loss on `LUTLibrary.starterCategoryPrecedes` in `BundledLookLibrary`.
- `EffectsInspectorView` `NeutralOriginSlider` argument order.

`CIKernel` deprecation warnings in the same log are out of scope.

### Compatibility (required)

Must compile and behave correctly when building with **both** the macOS 26 SDK (Xcode 26 / CI `macos-26`) and the macOS 27 SDK (Xcode beta / local `MacOSX27.0.sdk`). Deployment target remains **macOS 14** per `Package.swift`. This change must not introduce `#available(macOS 27, …)`-only APIs or SDK-27-only symbols — it is a Swift/source fix with no OS API dependency. Verify with `swift build` (or the packaging script) on whichever SDKs are available; if only one SDK is present in the agent environment, reason from API surface (none) and note which SDK was used in the handoff comment.

## Acceptance criteria

- [ ] `ResolutionPlanner.plan` compiles: the complete-presented-photo check calls `ResolutionPlan.roi(...)` (or an equivalent that does not invent a second predicate).
- [ ] Behavior unchanged: when the visible ROI matches the presented crop in native space (within existing epsilon in `ResolutionPlan.rect(_:matches:)`), `completePresentedPhoto` is true and the ≥2-level hysteresis reset still applies.
- [ ] Existing ROI / crop tests still pass (`Tests/KromoraKitTests/CropROITests.swift` already exercises `coversPresentedPhoto` — keep that path green).
- [ ] No duplicate `roi` helper copied onto `ResolutionPlanner`; reuse `ResolutionPlan.roi`.
- [ ] `swift build` succeeds for this diagnostic; the “no member 'roi'” error is gone.

- [ ] Compiles cleanly under Swift 6 against the macOS 26 **and** macOS 27 SDKs (or documents which SDK was verified if only one is available); no macOS 27-only APIs.

## Out of scope

- Changing detail scales, hysteresis constants, or ROI math.
- The other two Release compile errors from the same log.
- PreviewSurface / Metal presentation changes beyond restoring the intended call.

## Implementation notes

1. In `ResolutionPlanner.plan` (~line 147), replace `Self.roi(...)` with `ResolutionPlan.roi(...)`.
2. Optionally, for clarity, call `ResolutionPlan(...).coversPresentedPhoto` only if you can construct a temporary plan without changing semantics — **prefer the direct `ResolutionPlan.roi` call**; do not invent a half-built `ResolutionPlan` just for the check.
3. Leave `coversPresentedPhoto` on `ResolutionPlan` as-is; it is the public-facing API tests use.
4. Constraints: Swift 6, no isolation opt-outs; keep `Sendable` / `Equatable` as today.

## Verification

- Note SDK used (`xcrun --show-sdk-version` / `xcodebuild -version`); both 26 and 27 are in scope for this fix.

- `swift build` (or compile `ResolutionPlanner.swift` path) — error at line 147 gone.
- `swift test --filter CropROITests` (or full fast suite if cheap).
- `git diff --check`
- Mentally: zoomed ROI → `completePresentedPhoto == false`; fit covering crop → `true`.

### Comment — cursor @ 2026-09-18T22:41:01.966Z

Part of a three-issue Release compile unblock set from ./scripts/build-macos-app.sh (2026-09-18). Siblings: KRMA-454 (MainActor starterCategoryPrecedes), KRMA-456 (EffectsInspectorView NeutralOriginSlider order). Fix only the Self.roi → ResolutionPlan.roi call here.

### Comment — cursor @ 2026-09-18T22:41:29.166Z

Compatibility clarified: this fix is a type-qualification typo only — must work on macOS 26 and 27 SDKs; no OS-version-gated APIs.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-19T01:43:13.917Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] ResolutionPlanner.plan calls ResolutionPlan.roi without duplicating the helper (pass) — Sources/KromoraKit/Models/ResolutionPlanner.swift uses ResolutionPlan.roi at the complete-presented-photo check; the fix is present in b26624f4a9ce115dd8750452d2173f45bc87114.
- [x] ROI and hysteresis behavior remains correct (pass) — The existing ResolutionPlan.roi predicate and planner hysteresis logic are unchanged; CropROITests fit/zoom coverage passed.
- [x] Builds under the available Swift 6 SDK (pass) — swift build passed with Swift 6.4, Xcode 27.0, macOS 27.0 SDK. No SDK-27-only API was introduced.
Checks run:
- swift build
- swift test --filter CropROITests (8 passed, 0 failures)
- xcrun --show-sdk-version (27.0)
- xcodebuild -version (Xcode 27.0)
- git diff --check
- dg validate (OK; pre-existing model-name warnings only)
Findings:
- None
Fixes:
- None
Verification commits:
- b26624f4a9ce115dd8750452d2173f45bc87114
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU7Q1ZERHJBBMEGW
Summary: Verified the existing ResolutionPlan.roi qualification fix from b26624f; no additional source change was needed because the requested correction is already present on the current branch.
