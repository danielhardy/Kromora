---
id: KRMA-695
title: Remove pre-Tahoe availability guards and dead fallback paths
type: task
status: backlog
priority: high
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - tahoe
  - cleanup
  - swift6
created: 2026-09-28T22:19:34.496Z
updated: 2026-09-28T22:20:13.085Z
depends_on:
  - KRMA-694
blockers: []
order: w
board: product
---

## Objective

Delete every pre-Tahoe availability workaround that becomes dead code once the floor is macOS 26. No `#available(macOS 12/13/14/15)` gates, no always-true `if #available(macOS 26)` branches, no "deploys to 14" comments. The code must read as if it was always Tahoe-only.

Parent: KRMA-693. Sequencing: after KRMA-694 (floor raise) so the compiler enforces direct API use.

## Context

Exact sites (verified 2026-09-28):

- `Sources/KromoraKit/Models/RenderEngine.swift:2451` — `if #available(macOS 26, *)` around `filter.isHighlightRecoverySupported` in `captureCapabilities`; `:2570`, `:2657` — same guard in snapshot/apply paths.
- `Sources/KromoraKit/Models/RAWDevelopSettings.swift:73-80,144-156` — comments naming the macOS 14 deployment target; `:154` — `if let highlightRecoveryEnabled, #available(macOS 26, *), ...`.
- `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift:8,242-243` ("available on macOS 14"), `:463` (`guard #available(macOS 12.0, *)` person segmentation).
- `Sources/KromoraKit/Models/PhotoAnalysis/AppleEnhancementReference.swift:10,953-958` — `if #available(macOS 13, *) { return true }` with "on the macOS 14 deployment target the gate is always open" comment.
- `Sources/KromoraKit/Models/RAWCapabilities.swift:148` — "Always false below macOS 26" comment.
- `Sources/KromoraKit/Models/AdjustmentControl.swift:129,148` — macOS 26 SDK probe comments (keep the probe, drop floor language if stale).
- `Tests/KromoraKitTests/Support/VisionAestheticsDiagnostics.swift:12-14` — `guard #available(macOS 15, *) else { return nil }`; `Tests/KromoraKitTests/AutoPerformanceDiagnosticsTests.swift:15,197,205,332` — macOS 14/15 nil-path expectations.
- `Tests/KromoraKitTests/RAWDevelopSettingsTests.swift:164,200,289-301` — asserts the `#available` guard string exists; must be rewritten to assert direct use.
- `Tests/KromoraKitTests/AppleEnhancementReferenceTests.swift:158` — "deployment target postdates the availability gate" expectation.
- `Tests/KromoraKitTests/RAWCapabilitiesTests.swift:669` — environment note (keep if still accurate).
- `Sources/KromoraKit/Views/ContentView.swift:59,70` — duplicated `#available(macOS 26.0, *)` toolbar branches (mechanical collapse belongs here if the toolbar ticket does not take it; coordinate to avoid overlap — preferred: toolbar ticket owns ContentView guards).
- `Sources/KromoraKit/Views/CropInspectorView.swift:221-235` — runtime `NSImage(systemSymbolName:)` probe that falls back from `flip.horizontal` to `arrow.left.and.right` / `arrow.up.and.down`. This is not an `#available` gate, so the grep below will not find it. On macOS 26 use `flip.horizontal` directly and delete `isSystemImageAvailable`.

## Acceptance criteria

- [ ] `grep -rn "#available(macOS 1[2345]" Sources/ Tests/` returns nothing; `grep -rn "macOS 14" Sources/ --include="*.swift"` returns nothing except deliberately historical notes with justification.
- [ ] `CropInspectorView` uses `flip.horizontal` directly; the `NSImage(systemSymbolName:)` availability probe and arrow-symbol fallback are gone.
- [ ] Always-true `if #available(macOS 26, *)` branches collapsed to direct calls (highlight-recovery read/write, capability capture).
- [ ] `RAWDevelopSettings.apply(to:)` reads as straight-line per-knob code; stale "only knob newer than the deployment target" comments rewritten to describe capability (`isHighlightRecoverySupported`) rather than OS version.
- [ ] Vision providers call `VNGenerateForegroundInstanceMaskRequest` / `VNGeneratePersonSegmentationRequest` directly; error paths cover unsupported revisions/models, not unsupported OS versions.
- [ ] Guard-assertion tests rewritten (not deleted without replacement): highlight-recovery coverage still proves the capability-gated write path; aesthetics diagnostics still prove the Vision-declined nil path.
- [ ] `swift build` zero warnings; `scripts/ci-tests.sh fast` + `serial` clean; Swift 6 zero escape hatches preserved.

## Implementation notes

One mechanical pass, one reviewer-friendly diff. Do not redesign capability probing (`isHighlightRecoverySupported`, `supportedRevisions`) — that stays. Do not touch toolbar grouping or window layout; those are sibling tickets. Update `docs/AUTO_PERFORMANCE.md:63-64` if KRMA-694 left it.
