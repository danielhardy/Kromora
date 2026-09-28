---
id: KRMA-650
title: Implement content-aware heal (texture synthesis) distinct from Clone
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Heal produces a texture-synthesized or otherwise content-aware fill that differs perceptibly from Clone's plain translated-patch result for the same source/destination.
      result: pass
      notes: healTexture kernel recombines the sampled patch's high-frequency detail with the destination's Gaussian-blurred low-frequency appearance; verified by testHealPreservesDestinationAppearanceWhileCloneCopiesSampledPatch.
    - criterion: The distinction stays inside the render boundary (RetouchRenderer), keeping RetouchSpot/RetouchSettings Codable and Core-Image-object-free.
      result: pass
      notes: RetouchSpot/RetouchSettings/RetouchMode remain Codable+Sendable with no CI types; the kernel is now loaded through CIKernelLibrary and confined to RetouchRenderer, consistent with the rest of the render pipeline.
    - criterion: Regression coverage that Heal and Clone produce different pixels for the same spot geometry.
      result: pass
      notes: testHealPreservesDestinationAppearanceWhileCloneCopiesSampledPatch builds identical-geometry Heal and Clone spots and asserts XCTAssertNotEqual on rendered bytes; passes.
  checks_run:
    - swift build
    - swift test --filter RenderPipelineTests|MetalKernelParityTests|PackageSettingsTests (64 tests, 2 skipped for missing RAW fixture, 0 failures)
    - scripts/ci-tests.sh fast (1277 tests, 0 failures)
    - scripts/ci-tests.sh serial (431 tests, 1 skipped, 0 failures)
    - scripts/build-metal-libraries.sh --check (metallib/source checksum verification)
  findings:
    - "Architecture regression (fixed): Heal's kernel used CIKernel.kernels(withMetalString:), reintroducing runtime shader-source compilation that KRMA-524 deliberately migrated away from project-wide (see CIKernelLibrary.swift and MetalKernelParityTests doc comments). A try? silently returned nil on compile failure, so under any environment restricting that path Heal would silently degrade to Clone's identical output with nothing catching it. Fixed by moving healTexture into KromoraCIKernels.ci.metal / the precompiled .metallib, loaded via CIKernelLibrary like every other kernel."
    - "Efficiency (non-blocking, filed as KRMA-657): RetouchRenderer.healedPatch runs CIGaussianBlur over the full image extent for both source and destination on every heal spot, so per-spot cost scales with total image resolution rather than spot size. Output is pixel-correct; only cost is affected. Not fixed here -- filed as a verification-labeled child ticket (KRMA-657, low priority) per the localized-fix scope for this pass."
  fixes:
    - Added healTexture to Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal and Sources/KromoraKit/Support/CIKernelLibrary.swift's expectedKernelNames, rebuilt KromoraCIKernels.ci.metallib and its sha256 via scripts/build-metal-libraries.sh, and switched RetouchRenderer.swift to load it via CIKernelLibrary.kernel(named:) instead of compiling Metal source at runtime with CIKernel.kernels(withMetalString:).
  verification_commits:
    - 96a14e9
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T17:38:09.795Z
  session: 01MUK3D0ZXL00GC7O7
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T07:14:01.020Z
updated: 2026-09-27T17:38:09.797Z
parent: KRMA-599
blockers: []
order: a0
board: product
commits:
  - 96a14e9
---

## Objective

Give Heal a content-aware texture synthesis result, distinct from Clone's plain sampled patch,
matching the acceptance criteria in KRMA-599 (parent).

## Context

KRMA-599 added editable per-photo spot recipes (`RetouchSpot`, `RetouchRenderer`) with a `heal`
and a `clone` mode. Both modes currently render through the same code path in
`Sources/KromoraKit/Models/RetouchRenderer.swift`: a feathered sampled patch translated from
`sourceOffset` onto the destination, blended with `CIBlendWithMask`. `RetouchSpot.feather`
defaults differently per mode (0.35 heal / 0.5 clone) but the sampling/compositing math is
identical.

KRMA-599's acceptance criteria call for "content-aware heal and clone spots," and its own
implementation comment and `docs/RETOUCH.md` both explicitly disclose that Heal is not yet
content-aware: "Heal currently uses a feathered sampled patch like Clone; full content-aware
texture synthesis is not implemented."

## Acceptance criteria

- [ ] Heal produces a texture-synthesized or otherwise content-aware fill that differs
      perceptibly from Clone's plain translated-patch result for the same source/destination.
- [ ] The distinction stays inside the render boundary (`RetouchRenderer`), keeping
      `RetouchSpot`/`RetouchSettings` Codable and Core-Image-object-free.
- [ ] Regression coverage that Heal and Clone produce different pixels for the same spot
      geometry (they currently produce identical results other than the default feather).

## Implementation notes

### Comment — codex @ 2026-09-27T17:27:22.450Z

Implemented Heal as frequency-separated sampled texture over the destination's local low-frequency appearance; Clone remains a translated patch. Added a same-geometry Heal/Clone pixel regression and updated docs/RETOUCH.md. Checks: swift test --filter RenderPipelineTests (44 tests, 2 skipped for missing local RAW fixture, 0 failures). Commit: aed117d.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T17:38:09.795Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Heal produces a texture-synthesized or otherwise content-aware fill that differs perceptibly from Clone's plain translated-patch result for the same source/destination. (pass) — healTexture kernel recombines the sampled patch's high-frequency detail with the destination's Gaussian-blurred low-frequency appearance; verified by testHealPreservesDestinationAppearanceWhileCloneCopiesSampledPatch.
- [x] The distinction stays inside the render boundary (RetouchRenderer), keeping RetouchSpot/RetouchSettings Codable and Core-Image-object-free. (pass) — RetouchSpot/RetouchSettings/RetouchMode remain Codable+Sendable with no CI types; the kernel is now loaded through CIKernelLibrary and confined to RetouchRenderer, consistent with the rest of the render pipeline.
- [x] Regression coverage that Heal and Clone produce different pixels for the same spot geometry. (pass) — testHealPreservesDestinationAppearanceWhileCloneCopiesSampledPatch builds identical-geometry Heal and Clone spots and asserts XCTAssertNotEqual on rendered bytes; passes.
Checks run:
- swift build
- swift test --filter RenderPipelineTests|MetalKernelParityTests|PackageSettingsTests (64 tests, 2 skipped for missing RAW fixture, 0 failures)
- scripts/ci-tests.sh fast (1277 tests, 0 failures)
- scripts/ci-tests.sh serial (431 tests, 1 skipped, 0 failures)
- scripts/build-metal-libraries.sh --check (metallib/source checksum verification)
Findings:
- Architecture regression (fixed): Heal's kernel used CIKernel.kernels(withMetalString:), reintroducing runtime shader-source compilation that KRMA-524 deliberately migrated away from project-wide (see CIKernelLibrary.swift and MetalKernelParityTests doc comments). A try? silently returned nil on compile failure, so under any environment restricting that path Heal would silently degrade to Clone's identical output with nothing catching it. Fixed by moving healTexture into KromoraCIKernels.ci.metal / the precompiled .metallib, loaded via CIKernelLibrary like every other kernel.
- Efficiency (non-blocking, filed as KRMA-657): RetouchRenderer.healedPatch runs CIGaussianBlur over the full image extent for both source and destination on every heal spot, so per-spot cost scales with total image resolution rather than spot size. Output is pixel-correct; only cost is affected. Not fixed here -- filed as a verification-labeled child ticket (KRMA-657, low priority) per the localized-fix scope for this pass.
Fixes:
- Added healTexture to Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal and Sources/KromoraKit/Support/CIKernelLibrary.swift's expectedKernelNames, rebuilt KromoraCIKernels.ci.metallib and its sha256 via scripts/build-metal-libraries.sh, and switched RetouchRenderer.swift to load it via CIKernelLibrary.kernel(named:) instead of compiling Metal source at runtime with CIKernel.kernels(withMetalString:).
Verification commits:
- 96a14e9
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK3D0ZXL00GC7O7
Summary: Heal texture synthesis verified: content-aware fill differs from Clone, models stay Codable/CI-object-free, regression test passes. Fixed an architecture regression where the heal kernel used runtime Metal-source compilation (reintroducing the pattern KRMA-524 removed); moved it into the precompiled CI kernel library. Filed KRMA-657 (verification, low priority, non-blocking) for the full-image-extent blur cost per heal spot.
