---
id: KRMA-342
title: Replace CSS Auto reports with RenderEngine-backed candidate evaluation artifacts
type: feature
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings:
    - "medium/correctness: evaluate() computed the base/proposed target box from the baseline document's rotation only and reused it for both renders; when a proposal changed rotation, the real RenderEngine could produce a genuinely different pixel extent, but compare() silently returned a zero-diff measurement instead of flagging the mismatch, violating the 'never present an invalid render as a successful candidate' acceptance criterion. Fixed in commit 066b0eb."
  fixes:
    - "Record a base/proposed dimension mismatch as a 'geometry-mismatch' render failure (nil measurements/diff) instead of silently comparing mismatched-extent renders as zero-diff; added a real-RenderEngine regression test. Files: Sources/KromoraKit/Models/AutoCandidateEvaluation.swift, Tests/KromoraKitTests/AutoCandidateEvaluationTests.swift. Commit: 066b0eb."
  verification_commits:
    - 066b0eb
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T16:32:20.995Z
  session: 01MTVQSPADO58UKBZ7
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - rendering
  - testing
created: 2026-09-10T14:40:02.875Z
updated: 2026-09-10T16:32:20.997Z
depends_on:
  - KRMA-181
order: a0
board: product
commits:
  - 066b0eb
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Replace the current CSS/synthetic Auto visual report with a developer-facing evaluation artifact built from Kromora's actual `RenderEngine` output. This is the trust foundation for every later Auto decision.

## Scope

- Add a reusable evaluation seam that can render a source image/document at the analysis/evaluation scale through the real render pipeline.
- Render at least the unchanged document, a proposed document, and a complete-edit result with the correct color space and orientation.
- Produce real before/after pixels, a difference image, and actual mask overlays from the existing normalized mask/rendering path. Do not use CSS gradients or invented thumbnails as evidence.
- Make the report usable by an agent and a human: include fixture/asset identity, document revision, render scale, changed controls, confidence/reasons, validation measurements, and any render failure.
- Keep the artifact outside the committed source tree or under an ignored generated-artifact directory. Provide one documented command to generate it.

## Acceptance criteria

- [ ] The evaluation harness invokes `RenderEngine`/the normal preview-export rendering seam rather than a CSS approximation.
- [ ] It emits unchanged, proposed, diff, and mask-overlay images with matching orientation, crop geometry, color-space handling, and dimensions.
- [ ] It can evaluate a document containing existing Looks/LUTs, curves, grading, and manual masks while also supporting the Auto analysis view that temporarily excludes LUTs, grading, grain, and decorative vignette.
- [ ] The report identifies renderer failures and never presents a missing render as a successful candidate.
- [ ] A deterministic generated fixture test verifies pixel dimensions, orientation, and that a known edit changes the actual diff image.
- [ ] Preview and export render paths have a parity assertion for at least one representative fixture.
- [ ] The generated output location and command are documented in the completion comment; generated files are ignored.

## Non-goals

- Do not change Auto policy or candidate selection in this ticket.
- Do not optimize rendering or add a new renderer.
- Do not make the report a CI gate; later quality tickets consume it.

## Likely files

- `Sources/KromoraKit/Models/RenderEngine.swift`
- `Sources/KromoraKit/Models/RenderRequest.swift`
- `Sources/KromoraKit/Models/RenderStageFacade.swift`
- `Sources/KromoraKit/Models/LocalMaskRenderer.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/`
- `Tests/KromoraKitTests/Fixtures.swift`
- `Tests/KromoraKitTests/`
- `scripts/`

## Verification

Run the focused evaluation/report tests, `swift build`, `dg validate`, and `git diff --check`. Do not rely on a browser screenshot or CSS-only report as verification.


### Comment — pi @ 2026-09-10T15:17:53.123Z

Implementation complete on branch krma-342-auto-evaluation (3 files, +771). AutoCandidateEvaluation seam renders unchanged/proposed/complete documents through the real RenderEngine makeCGImage/buildImage path at 768px long edge with matching orientation/crop/color-space; emits real before/after/diff PNGs plus actual mask overlays; Codable report carries fixture identity, edit hashes, changed controls, diff measurements, and render failures (missing renders recorded, never presented as success). Analysis-view transform strips LUT/grading/grain/decorative vignette while retaining geometry. Verification: 9/9 AutoCandidateEvaluationTests pass (stub-driven geometry/diff/failure/artifact + real-engine diff and preview/export parity on gradient fixture); neighboring suites (AutoAdjustment, AutoLightEngine, RenderRequest, PackageSettings, 27 tests) pass; swift build clean; dg validate OK; git diff --check clean. Generate: scripts/auto-evaluation-report.sh [output-dir], default artifacts/auto-evaluation/ (gitignored; verified real-gradient: 96x64 sRGB, +1EV mean diff 0.14154, changed 100%). No policy/selection changes per non-goals.


### Comment — codex @ 2026-09-10T16:24:19.876Z

Recovered and integrated onto main at commit 66e5d33 (KRMA-342: add RenderEngine-backed Auto candidate evaluation foundation). Verified on main: swift test --filter AutoCandidateEvaluationTests — 9 passed, 0 failures, including real RenderEngine diff/parity, rotation geometry, artifact writing, and render-failure reporting. dg validate and git diff --check pass; only pre-existing DG warnings remain. Existing unrelated worktree changes were preserved.

## Agent log

- 2026-09-10T16:32:20.995Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- medium/correctness: evaluate() computed the base/proposed target box from the baseline document's rotation only and reused it for both renders; when a proposal changed rotation, the real RenderEngine could produce a genuinely different pixel extent, but compare() silently returned a zero-diff measurement instead of flagging the mismatch, violating the 'never present an invalid render as a successful candidate' acceptance criterion. Fixed in commit 066b0eb.
Fixes:
- Record a base/proposed dimension mismatch as a 'geometry-mismatch' render failure (nil measurements/diff) instead of silently comparing mismatched-extent renders as zero-diff; added a real-RenderEngine regression test. Files: Sources/KromoraKit/Models/AutoCandidateEvaluation.swift, Tests/KromoraKitTests/AutoCandidateEvaluationTests.swift. Commit: 066b0eb.
Verification commits:
- 066b0eb
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVQSPADO58UKBZ7
Summary: Verification pass: real RenderEngine-backed evaluation seam confirmed (real pixels, diff, mask overlays, render-failure reporting, preview/export parity). Found and fixed one correctness gap: base/proposed geometry mismatch (e.g. a rotation-changing proposal) was silently reported as zero-diff instead of a failure; added 'geometry-mismatch' failure reporting plus a real-RenderEngine regression test. 10/10 focused tests + 27 neighboring tests pass, swift build/dg validate/git diff --check clean.
