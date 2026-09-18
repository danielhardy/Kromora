---
id: KRMA-454
title: Fix MainActor isolation on LUTLibrary.starterCategoryPrecedes for BundledLookLibrary sort
type: bug
status: ready
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - build
  - swift6
  - looks
  - correctness
created: 2026-09-18T22:41:00.336Z
updated: 2026-09-18T22:41:29.030Z
order: z
board: product
---

## Objective

Unblock Release / packaged-app compilation by fixing the Swift 6 global-actor error when `BundledLookLibrary.categories` passes `LUTLibrary.starterCategoryPrecedes` into `sorted(by:)`.

## Context

### Failure (blocking)

`./scripts/build-macos-app.sh` fails compiling `KromoraKit` with:

```
Sources/KromoraKit/Models/BundledLookLibrary.swift:45:40: error: converting function value of type '@MainActor (String, String) throws -> Bool' to '(String, String) throws -> Bool' loses global actor 'MainActor'
        return grouped.keys.sorted(by: LUTLibrary.starterCategoryPrecedes).map { category in
```

### Why it happens

- `LUTLibrary` is annotated `@MainActor` (`Sources/KromoraKit/Models/LUTLibrary.swift`).
- Nested / static members therefore inherit MainActor isolation unless marked otherwise.
- `static func starterCategoryPrecedes(_:_:) -> Bool` (around line 46) only compares two `String`s (`"Monochrome"` first, else `localizedStandardCompare`). It has **no** dependency on instance/`@Published` state.
- `BundledLookLibrary` is a `Sendable` value type; its `categories` computed property is **not** MainActor-isolated. Passing the MainActor-isolated function reference into `Sequence.sorted(by:)` is illegal under Swift 6 language mode (errors, not warnings; no `@unchecked Sendable` / isolation opt-outs — see `CLAUDE.md`).

### Call sites that must keep working

- `BundledLookLibrary.categories` — passes the function as a value: `sorted(by: LUTLibrary.starterCategoryPrecedes)`.
- `LUTLibrary.starterCategories` — uses a closure: `.sorted { Self.starterCategoryPrecedes($0.name, $1.name) }` (already fine once the method is nonisolated, or stays fine if called only on MainActor).
- Category sorting elsewhere in `LUTLibrary` (~line 360) that calls `Self.starterCategoryPrecedes`.

### Sibling build breakers (separate tickets — do not fix here)

These also fail the same `build-macos-app.sh` run and must stay out of this change:

- `ResolutionPlanner` calling missing `Self.roi` (belongs on `ResolutionPlan`).
- `EffectsInspectorView` `NeutralOriginSlider` argument order (`neutral` before `step`).

The long `CIKernel(source:)` deprecation warnings in the same log are **not** errors and are out of scope.

### Compatibility (required)

Must compile and behave correctly when building with **both** the macOS 26 SDK (Xcode 26 / CI `macos-26`) and the macOS 27 SDK (Xcode beta / local `MacOSX27.0.sdk`). Deployment target remains **macOS 14** per `Package.swift`. This change must not introduce `#available(macOS 27, …)`-only APIs or SDK-27-only symbols — it is a Swift/source fix with no OS API dependency. Verify with `swift build` (or the packaging script) on whichever SDKs are available; if only one SDK is present in the agent environment, reason from API surface (none) and note which SDK was used in the handoff comment.

## Acceptance criteria

- [ ] `BundledLookLibrary.categories` compiles under Swift 6 without MainActor conversion errors when sorting category keys with starter ordering.
- [ ] Starter category order is unchanged: `"Monochrome"` still precedes every other category name; remaining names still use `localizedStandardCompare` ascending.
- [ ] No new Swift 6 isolation opt-outs (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`).
- [ ] Prefer making the pure comparator `nonisolated static` (same spirit as existing `nonisolated static func scanSync` in `LUTLibrary`) over forcing callers onto MainActor or wrapping with unsafe casts.
- [ ] `swift build` succeeds for this file / target path; at minimum the previous error at `BundledLookLibrary.swift:45` is gone.
- [ ] If a cheap unit/model test already covers starter category ordering, extend or assert Monochrome-first; otherwise a focused test is welcome but not mandatory if behavior is obviously preserved by an isolation-only change.

- [ ] Compiles cleanly under Swift 6 against the macOS 26 **and** macOS 27 SDKs (or documents which SDK was verified if only one is available); no macOS 27-only APIs.

## Out of scope

- The other two Release compile errors from the same log (file separate tickets).
- Silencing Core Image Kernel Language deprecation warnings.
- Refactoring Look collection UX or changing category names/contents.

## Implementation notes

1. Open `Sources/KromoraKit/Models/LUTLibrary.swift` and change `starterCategoryPrecedes` to `nonisolated static func starterCategoryPrecedes(...)` (keep body identical).
2. Re-read `BundledLookLibrary.categories` — with a nonisolated comparator, `sorted(by: LUTLibrary.starterCategoryPrecedes)` should type-check without further changes.
3. Do **not** mark `BundledLookLibrary` or its `categories` `@MainActor` just to paper over this; bundled loading is intentionally Sendable / off-main-safe.
4. Do **not** duplicate the sort rules into `BundledLookLibrary`; keep one shared comparator.
5. Constraints: macOS 14+, zero third-party deps, Swift 6 mode with zero isolation escape hatches.

## Verification

- Note SDK used (`xcrun --show-sdk-version` / `xcodebuild -version`); both 26 and 27 are in scope for this fix.

- Reproduce before (optional): `./scripts/build-macos-app.sh` or compile the kit and confirm the MainActor diagnostic at line 45.
- After: `swift build` (and/or re-run packaged build once sibling tickets land).
- `git diff --check`
- Confirm Monochrome still sorts first mentally or via existing Look/LUT tests if present.

### Comment — cursor @ 2026-09-18T22:41:01.824Z

Part of a three-issue Release compile unblock set from ./scripts/build-macos-app.sh (2026-09-18). Siblings: KRMA-455 (ResolutionPlan.roi Self), KRMA-456 (EffectsInspectorView NeutralOriginSlider order). Fix only this MainActor diagnostic here; leave siblings alone.

### Comment — cursor @ 2026-09-18T22:41:29.029Z

Compatibility clarified: this fix is Swift isolation only — must work on macOS 26 and 27 SDKs; no OS-version-gated APIs.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
