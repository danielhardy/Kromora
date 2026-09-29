---
id: KRMA-695
title: Remove pre-Tahoe availability guards and dead fallback paths
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: grep -rn "#available(macOS 1[2345]" Sources/ Tests/ returns nothing; grep -rn "macOS 14" Sources/ returns nothing except justified historical notes
      result: pass
      notes: Both greps return nothing repo-wide; no pre-Tahoe guards or macOS 14 references remain in Sources/ or Tests/.
    - criterion: CropInspectorView uses flip.horizontal directly; NSImage(systemSymbolName:) probe and arrow-symbol fallback are gone
      result: pass
      notes: isSystemImageAvailable helper removed; flipHorizontalSystemImage/flipVerticalSystemImage return "flip.horizontal" unconditionally, vertical rotated 90 degrees.
    - criterion: "Always-true if #available(macOS 26, *) branches collapsed to direct calls (highlight-recovery read/write, capability capture)"
      result: pass
      notes: RenderEngine.swift captureCapabilities/snapshot/apply now call filter.isHighlightRecoverySupported/isHighlightRecoveryEnabled directly.
    - criterion: RAWDevelopSettings.apply(to:) reads as straight-line per-knob code; stale deployment-target comments rewritten to describe capability
      result: pass
      notes: Guard now reads `if let highlightRecoveryEnabled, filter.isHighlightRecoverySupported`; comments reference isHighlightRecoverySupported, not OS version.
    - criterion: Vision providers call VNGenerateForegroundInstanceMaskRequest / VNGeneratePersonSegmentationRequest directly; error paths cover unsupported revisions/models, not unsupported OS versions
      result: pass
      notes: "Both #available(macOS 14/12) guards removed from VisionSemanticMaskProvider.swift; only supportedRevisions checks remain."
    - criterion: Guard-assertion tests rewritten (not deleted without replacement)
      result: pass
      notes: "RAWDevelopSettingsTests now asserts absence of #available and presence of capability check; AutoPerformanceDiagnosticsTests keeps aesthetics nil-path coverage via new VisionAestheticsDiagnostics.scores(performRequest:) injection seam plus testAestheticsDiagnosticsReturnNilWhenVisionDeclines."
    - criterion: swift build zero warnings; scripts/ci-tests.sh fast + serial clean; Swift 6 zero escape hatches preserved
      result: pass
      notes: "Independently re-ran: swift build clean, ci-tests.sh fast exit 0 (1331 tests), ci-tests.sh serial exit 0 (443 tests, 1 skipped), build-metal-libraries.sh --check exit 0, git diff --check clean."
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - scripts/build-metal-libraries.sh --check
    - git diff --check (full commit c9245a8)
    - grep -rn "#available(macOS 1[2345]" Sources/ Tests/
    - grep -rn "macOS 14" Sources/ Tests/ --include=*.swift
    - grep -rn "deploys to|deployment target|pre-Tahoe" Sources/ Tests/
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T00:09:42.317Z
  session: 01MULWUPZQL7B3D6U5
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - tahoe
  - cleanup
  - swift6
created: 2026-09-28T22:19:34.496Z
updated: 2026-09-29T00:09:42.319Z
depends_on:
  - KRMA-694
blockers: []
order: a0
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


### Comment — codex @ 2026-09-29T00:00:37.309Z

Removed pre-Tahoe availability gates and dead OS fallbacks across RAW, Vision, Core Image enhancement, and crop symbols. Kept RAW decoder capability checks, updated diagnostics and tests, and regenerated the Core Image kernel library. Verified: swift build, scripts/ci-tests.sh fast, scripts/ci-tests.sh serial, scripts/build-metal-libraries.sh --check, and git diff --check all pass. Commit: c9245a8.

## Agent log

- 2026-09-29T00:09:42.317Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] grep -rn "#available(macOS 1[2345]" Sources/ Tests/ returns nothing; grep -rn "macOS 14" Sources/ returns nothing except justified historical notes (pass) — Both greps return nothing repo-wide; no pre-Tahoe guards or macOS 14 references remain in Sources/ or Tests/.
- [x] CropInspectorView uses flip.horizontal directly; NSImage(systemSymbolName:) probe and arrow-symbol fallback are gone (pass) — isSystemImageAvailable helper removed; flipHorizontalSystemImage/flipVerticalSystemImage return "flip.horizontal" unconditionally, vertical rotated 90 degrees.
- [x] Always-true if #available(macOS 26, *) branches collapsed to direct calls (highlight-recovery read/write, capability capture) (pass) — RenderEngine.swift captureCapabilities/snapshot/apply now call filter.isHighlightRecoverySupported/isHighlightRecoveryEnabled directly.
- [x] RAWDevelopSettings.apply(to:) reads as straight-line per-knob code; stale deployment-target comments rewritten to describe capability (pass) — Guard now reads `if let highlightRecoveryEnabled, filter.isHighlightRecoverySupported`; comments reference isHighlightRecoverySupported, not OS version.
- [x] Vision providers call VNGenerateForegroundInstanceMaskRequest / VNGeneratePersonSegmentationRequest directly; error paths cover unsupported revisions/models, not unsupported OS versions (pass) — Both #available(macOS 14/12) guards removed from VisionSemanticMaskProvider.swift; only supportedRevisions checks remain.
- [x] Guard-assertion tests rewritten (not deleted without replacement) (pass) — RAWDevelopSettingsTests now asserts absence of #available and presence of capability check; AutoPerformanceDiagnosticsTests keeps aesthetics nil-path coverage via new VisionAestheticsDiagnostics.scores(performRequest:) injection seam plus testAestheticsDiagnosticsReturnNilWhenVisionDeclines.
- [x] swift build zero warnings; scripts/ci-tests.sh fast + serial clean; Swift 6 zero escape hatches preserved (pass) — Independently re-ran: swift build clean, ci-tests.sh fast exit 0 (1331 tests), ci-tests.sh serial exit 0 (443 tests, 1 skipped), build-metal-libraries.sh --check exit 0, git diff --check clean.
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- scripts/build-metal-libraries.sh --check
- git diff --check (full commit c9245a8)
- grep -rn "#available(macOS 1[2345]" Sources/ Tests/
- grep -rn "macOS 14" Sources/ Tests/ --include=*.swift
- grep -rn "deploys to|deployment target|pre-Tahoe" Sources/ Tests/
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULWUPZQL7B3D6U5
