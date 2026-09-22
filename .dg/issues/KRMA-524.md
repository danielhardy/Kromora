---
id: KRMA-524
title: Migrate deprecated CIKL kernels to Metal and precompile shaders
type: task
status: ready
priority: high
agent: pi
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - stability
  - rendering
  - metal
created: 2026-09-21T20:33:05.437Z
updated: 2026-09-21T21:55:15.883Z
depends_on:
  - KRMA-522
  - KRMA-523
estimate: 8
order: zq
board: product
---

## Objective

Remove deprecated runtime CIKernel source compilation and compile/load the render shaders through a verified Metal library without changing pixels.

## Context and evidence

Nine CI kernel source calls, in RenderPipeline, LocalMaskRenderer, and ToneCurveFilterCache, produce deprecation warnings and compile at runtime. PreviewSurface also compiles PreviewSurface.metal from source at runtime, adding first-frame latency. The plan requires a build-time or checked-in metallib path compatible with SwiftPM and CI, with golden-pixel coverage before deleting the old source.

## Scope

- Port each CIKernel/CIColorKernel to .ci.metal functions and load via CIKernel(functionName:fromMetalLibraryData:).
- Choose a maintainable SwiftPM-compatible build approach: checked build step/resource generation or build-tool plugin if it avoids third-party dependencies.
- Precompile PreviewSurface.metal and load it without first-frame source compilation.
- Add a golden-pixel test per migrated kernel, with documented tolerance and representative edge/ROI inputs.
- Keep a clear CI failure when the metallib is missing, stale, or not included in the app/resource bundle.

## Acceptance criteria

- [ ] Sources has zero CIKernel(source:) or CIColorKernel(source:) deprecation warnings.
- [ ] Golden-pixel parity tests pass for each migrated kernel, including crop/ROI edge cases where relevant.
- [ ] First-frame path performs no runtime shader source compilation.
- [ ] Clean and release builds include the required metallib resources on supported macOS targets.
- [ ] Fast and serial lanes plus render/mask tests pass.

## Dependencies and coordination

Independent implementation, but CQ-17 depends on its warning cleanup. Coordinate with CQ-07 and CQ-08 on shared RenderEngine/LocalMaskRenderer boundaries; avoid bundling unrelated render refactors.

## Likely files and checks

RenderPipeline.swift, LocalMaskRenderer.swift, ToneCurveFilterCache.swift, PreviewSurface.swift, .metal/.ci.metal resources, Package.swift/build scripts, resource validation, and pixel tests.
