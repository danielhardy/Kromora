---
id: KRMA-458
title: Fix double-nested Resources path breaks bundled Look loading (StarterLooks resource lookup)
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: BundledLookLibrary.validate() and .load() find StarterLooks/manifest.json in both the SwiftPM test bundle (.module) and the packaged app's Kromora_KromoraKit.bundle.
      result: pass
      notes: resourceSubdirectory changed to "Resources/StarterLooks" in f17db90, matching the double-nested layout SwiftPM actually produces via .copy("Resources"). Confirmed manifest.json exists at that path in .build's .module bundle, debug/release Kromora_KromoraKit.bundle, and the packaged .build/Kromora.app bundle.
    - criterion: swift test --filter BundledLookTests passes without modifying the test's expectations.
      result: pass
      notes: "Ran swift test --filter BundledLookTests: 6/6 tests passed, 0 failures. Test file itself untouched (git diff shows only BundledLookLibrary.swift changed)."
    - criterion: No behavior change to Look content/category naming (out of scope per KRMA-454).
      result: pass
      notes: Diff is a 4-line change confined to the resourceSubdirectory constant plus a comment; no changes to category/manifest parsing logic. Verified other KromoraKitResourceBundle.bundle consumers (PreviewSurface.swift, MaskOverlayPrototype.swift) look up root-level resources ("PreviewSurface", "MaskOverlay") unaffected by this subdirectory change.
  checks_run:
    - swift test --filter BundledLookTests (6/6 passed)
    - git show f17db90 -- Sources/KromoraKit/Models/BundledLookLibrary.swift (diff review)
    - grep for other KromoraKitResourceBundle.bundle consumers to confirm no collateral impact
    - find .build for Resources/StarterLooks/manifest.json across .module, debug/release Kromora_KromoraKit.bundle, and packaged Kromora.app bundle layouts
    - git status --porcelain to confirm no unintended tracked-file changes from this verification pass
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-19T02:34:10.437Z
  session: 01MU7RWL32BOOMMCUC
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - build
  - looks
created: 2026-09-19T01:40:47.537Z
updated: 2026-09-19T02:34:10.440Z
parent: KRMA-454
order: a0
board: product
---

## Objective

Fix double-nested Resources path breaks bundled Look loading (StarterLooks resource lookup)

## Context

Found during KRMA-454 verification (MainActor isolation fix for `LUTLibrary.starterCategoryPrecedes`).
Unrelated to that fix, but a real, currently-active bug:

`Package.swift` declares KromoraKit's resources as `resources: [.copy("Resources")]`, which copies the
whole `Sources/KromoraKit/Resources/` directory into the resource bundle *preserving the `Resources/`
prefix*. `BundledLookLibrary.load`/`.validate` (`Sources/KromoraKit/Models/BundledLookLibrary.swift`)
look up `resourceSubdirectory = "StarterLooks"` directly (no `Resources/` prefix), so the lookup fails
with `missingResource("StarterLooks/manifest.json")`.

Verified this is not just a test artifact — inspecting `.build/Kromora.app/Contents/Resources/Kromora_KromoraKit.bundle/Contents/Resources/`
shows the manifest lives at `Resources/StarterLooks/manifest.json`, i.e. the same double-nesting exists
in the packaged app bundle, not only the SwiftPM test bundle. `KromoraKitResourceBundle.bundle` falls
back to `.module` when no app-bundle-relative `Kromora_KromoraKit.bundle` is found (dev/`swift run`),
which has the identical layout, so the bug is not confined to CI/test bundling either.

Net effect: `BundledLookLibrary.load()` currently returns zero starter Looks and a `missingResource`
warning in every configuration checked (`swift test`, `.build` debug/release app bundles) — the Starter
Looks feature is silently empty rather than crashing, so it may not have been noticed.

Reproduced via: `swift test --filter BundledLookTests` — 11 of 6 tests' assertions fail with
`XCTAssertEqual failed: ("0") is not equal to ("13")` and `caught error: "missingResource("StarterLooks/manifest.json")"`.

## Acceptance criteria

- [ ] `BundledLookLibrary.validate()` and `.load()` find `StarterLooks/manifest.json` in both the
      SwiftPM test bundle (`.module`) and the packaged app's `Kromora_KromoraKit.bundle`.
- [ ] `swift test --filter BundledLookTests` passes without modifying the test's expectations.
- [ ] No behavior change to Look content/category naming (out of scope per KRMA-454).

## Implementation notes

Likely fix is either changing `Package.swift`'s resource rule to `.copy("Resources/StarterLooks")` (and
adjusting `resourceSubdirectory` accordingly) or changing `resourceSubdirectory` to `"Resources/StarterLooks"`
to match the actual copied layout — confirm which keeps `PreviewSurface.swift`/`MaskOverlayPrototype.swift`
(other `KromoraKitResourceBundle.bundle` consumers, which look up different resource names outside
`StarterLooks`) unaffected before picking one.

### Comment — codex @ 2026-09-19T02:33:23.389Z

Implemented in f17db90. BundledLookLibrary now looks up Resources/StarterLooks, matching both SwiftPM .module and packaged Kromora_KromoraKit.bundle layouts; root-level PreviewSurface.metal and MaskOverlay.metal lookups remain unchanged. Verification: swift test --filter BundledLookTests passed (6/6); scripts/build-macos-app.sh passed and produced a verified app with Resources/StarterLooks/manifest.json; git diff --check passed; dg validate --json passed with pre-existing unknown-model warnings. Full swift test reached the broader suite but terminated in unrelated PreviewSurfaceTests with XCTest signal 6 (Metal vertexFunction must not be nil). SDK verified: Xcode 27.0, macOS SDK 27.0; no SDK-specific API added.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-19T02:34:10.437Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] BundledLookLibrary.validate() and .load() find StarterLooks/manifest.json in both the SwiftPM test bundle (.module) and the packaged app's Kromora_KromoraKit.bundle. (pass) — resourceSubdirectory changed to "Resources/StarterLooks" in f17db90, matching the double-nested layout SwiftPM actually produces via .copy("Resources"). Confirmed manifest.json exists at that path in .build's .module bundle, debug/release Kromora_KromoraKit.bundle, and the packaged .build/Kromora.app bundle.
- [x] swift test --filter BundledLookTests passes without modifying the test's expectations. (pass) — Ran swift test --filter BundledLookTests: 6/6 tests passed, 0 failures. Test file itself untouched (git diff shows only BundledLookLibrary.swift changed).
- [x] No behavior change to Look content/category naming (out of scope per KRMA-454). (pass) — Diff is a 4-line change confined to the resourceSubdirectory constant plus a comment; no changes to category/manifest parsing logic. Verified other KromoraKitResourceBundle.bundle consumers (PreviewSurface.swift, MaskOverlayPrototype.swift) look up root-level resources ("PreviewSurface", "MaskOverlay") unaffected by this subdirectory change.
Checks run:
- swift test --filter BundledLookTests (6/6 passed)
- git show f17db90 -- Sources/KromoraKit/Models/BundledLookLibrary.swift (diff review)
- grep for other KromoraKitResourceBundle.bundle consumers to confirm no collateral impact
- find .build for Resources/StarterLooks/manifest.json across .module, debug/release Kromora_KromoraKit.bundle, and packaged Kromora.app bundle layouts
- git status --porcelain to confirm no unintended tracked-file changes from this verification pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU7RWL32BOOMMCUC
