---
id: KRMA-714
title: Investigate and fix ineffective Noise Reduction
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce with deterministic noisy image
      result: pass
      notes: Generated 96x64 float RGBA fixture in regression test.
    - criterion: Root cause identified
      result: pass
      notes: max() aliasing of luminance/color controls plus weak 0.1 cap and double attenuation.
    - criterion: Luma/chroma NR reduce noise, zero neutral, detail kept
      result: pass
      notes: "Pixel assertions in RenderPipelineTests pass. Caveat: CINoiseReduction is not chroma-specific, so Color NR is a second general pass."
    - criterion: RAW decoder capability/defaults
      result: pass
      notes: No RAW change needed; real RAW checks skipped (no licensed fixture).
    - criterion: Persistence/preview/export consistency
      result: pass
      notes: Shared pipeline; cache version bumped to 34; local mask routed through one pass.
    - criterion: Focused regression coverage
      result: pass
    - criterion: Scope limited to NR
      result: pass
    - criterion: Handoff records cause/fix/verification
      result: pass
  checks_run:
    - swift test --filter RenderPipelineTests (48 run, 2 skipped, 0 failures)
    - git diff --check cdbe484~1 cdbe484
  findings:
    - "Non-blocking: CINoiseReduction operates on RGB, not chroma-only, so Color NR does not truly isolate chroma; consider a chroma-domain denoise later."
    - Two full-frame passes when both controls are set may cost performance on large previews.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T20:13:51.563Z
  session: 01MUN464ZDP2WA674L
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - rendering
  - quality
created: 2026-09-29T16:42:37.311Z
updated: 2026-09-29T20:13:51.565Z
blockers: []
order: a0
board: product
---

## Objective

Determine why the Noise Reduction controls appear to have little or no effect, identify the root cause, and correct the rendering behavior. The global Noise Reduction section in the Effects inspector is the primary reported surface; check local-mask Noise Reduction if it shares the failing path.

## User report

The current Noise Reduction (NR) does not seem to do anything. No source image, format, slider values, or reproduction steps were supplied, so establish a controlled reproduction before choosing a fix.

## Context

Noise controls are represented by luminance and color values in `DetailAdjustments`. The Effects inspector exposes Luminance NR and Color NR through `DetailControl`. The shared detail stage in `RenderPipeline.applyDetailControls` currently derives a combined noise amount and applies Core Image `CINoiseReduction`; RAW develop settings also have per-image luminance and color NR properties that are applied to `CIRAWFilter` when supported. Trace the actual value path from the controls through persistence, capability handling, rendering, and preview publication before attributing the issue to a particular stage.

Related completed work: KRMA-598 added sharpening, noise, and moiré controls. Treat it as implementation history, not evidence that the current behavior is correct.

## Acceptance criteria

- [ ] Reproduce the report with a deterministic noisy image and record the source format, control values, render path, and observed result.
- [ ] Identify and document the root cause, including whether it is in control binding, value mapping, persistence, RAW capability/default handling, filter execution, render/cache invalidation, or presentation.
- [ ] On a suitable noisy raster fixture, demonstrate that increasing Luminance NR reduces luminance noise and increasing Color NR reduces chroma noise; verify zero remains neutral and detail loss stays reasonable.
- [ ] For RAW files, verify the decoder capability and default behavior, and confirm supported NR values reach the RAW filter and affect the rendered result. Where the decoder does not support a control, ensure the UI does not imply that a no-op adjustment was applied.
- [ ] Confirm adjustments persist and update the visible preview, comparison output, and export consistently; include local-mask behavior if the shared implementation is implicated.
- [ ] Add focused regression coverage at the narrowest useful rendering boundary, using measurable pixel/noise assertions and a meaningful detail-preservation check. Record any RAW-fixture limitation if full RAW coverage is opt-in.
- [ ] Keep changes scoped to Noise Reduction; do not alter sharpening, moiré reduction, grain, or unrelated image rendering behavior.
- [ ] Record the root cause, fix, and verification commands/results in the implementation handoff.

## Investigation notes

Compare zero, moderate, and strong settings on controlled luminance-noisy and chroma-noisy inputs. Inspect the rendered pixels rather than relying only on slider movement or filter construction. Check preview/cache keys and the settling path so a correct render is not hidden by a stale frame. Include a RAW fixture when available and distinguish decoder-native RAW NR from post-decode raster NR.


### Comment — codex @ 2026-09-29T20:13:17.912Z

Root cause: RenderPipeline.applyDetailControls collapsed luminanceNoise and colorNoise with max(), so both controls drove one filter pass and the lower setting was ignored. The mapping also capped CINoiseReduction noiseLevel at 0.1 and attenuated the result again, leaving moderate settings weak. The separate RAW develop path already gates both decoder controls by their is*Supported capabilities, preserves nil decoder defaults, and disables unsupported inspector rows; no RAW path change was needed. Fix: independently map each raster control to its own CINoiseReduction pass (0...0.2 threshold), use each control's Detail/Contrast values, route the single local-mask NR control through one pass, and bump the render cache version. Preview, comparison, and export use this shared pipeline. Reproduction: generated deterministic 96x64 floating-point RGBA input with hard luminance edge plus either luminance-only or chroma-only high-frequency noise; each control at 70. Pixel assertions require at least 20% noise-energy reduction and at least 80% edge contrast retention; zero is pixel-neutral. Results: focused regression passed; RenderPipelineTests 48 passed, 2 skipped; RAWDevelopSettingsTests 4 passed, 2 skipped. Real RAW decoder/apply checks skipped because no local licensed RAW fixture is configured. Commands: swift test --filter RenderPipelineTests/testNoiseReductionReducesLuminanceAndChromaNoiseWithoutLosingTheEdge; swift test --filter RenderPipelineTests; swift test --filter RAWDevelopSettingsTests; git diff --check for changed files. Commit cdbe484.

## Agent log

- 2026-09-29T20:13:51.563Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce with deterministic noisy image (pass) — Generated 96x64 float RGBA fixture in regression test.
- [x] Root cause identified (pass) — max() aliasing of luminance/color controls plus weak 0.1 cap and double attenuation.
- [x] Luma/chroma NR reduce noise, zero neutral, detail kept (pass) — Pixel assertions in RenderPipelineTests pass. Caveat: CINoiseReduction is not chroma-specific, so Color NR is a second general pass.
- [x] RAW decoder capability/defaults (pass) — No RAW change needed; real RAW checks skipped (no licensed fixture).
- [x] Persistence/preview/export consistency (pass) — Shared pipeline; cache version bumped to 34; local mask routed through one pass.
- [x] Focused regression coverage (pass)
- [x] Scope limited to NR (pass)
- [x] Handoff records cause/fix/verification (pass)
Checks run:
- swift test --filter RenderPipelineTests (48 run, 2 skipped, 0 failures)
- git diff --check cdbe484~1 cdbe484
Findings:
- Non-blocking: CINoiseReduction operates on RGB, not chroma-only, so Color NR does not truly isolate chroma; consider a chroma-domain denoise later.
- Two full-frame passes when both controls are set may cost performance on large previews.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN464ZDP2WA674L
Summary: Verification passed: independent luminance/color NR passes, tests green.
