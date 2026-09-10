---
id: KRMA-346
title: Add Core Image automatic-enhancement reference proposal fitting
type: feature
status: ready
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - apple-frameworks
  - rendering
created: 2026-09-10T14:40:05.868Z
updated: 2026-09-10T14:53:41.012Z
depends_on:
  - KRMA-342
  - KRMA-343
  - KRMA-345
order: zq
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Add an Apple-frameworks-first proposal source using Core Image's automatic enhancement suggestions, then fit that reference through Kromora's editable controls instead of persisting an opaque filter stack.

## Scope

- Add an internal adapter around Core Image automatic enhancement analysis/rendering that is isolated from the policy and coordinator.
- Treat the Apple output as a reference proposal, not authoritative truth and not a persisted filter chain.
- Compare the reference render or filter intent to Kromora-supported controls and return a bounded value-only proposal with provenance and confidence.
- Respect the analysis view exclusions and restore the complete edit for final evaluation.
- Keep the adapter available only on supported Apple OS/runtime combinations and return an explicit unavailable result otherwise.

## Acceptance criteria

- [ ] Core Image automatic enhancement is invoked through a testable internal adapter with no network or third-party dependency.
- [ ] The adapter returns a value-only reference/provenance result and never stores CI filters as the user's edit.
- [ ] Reference intent is fitted through Kromora's existing exposure/tone/color/white-balance mappings with bounded residual error; unsupported effects are omitted and reported.
- [ ] RAW and standard-image inputs use the correct source/render color space and white-balance direction.
- [ ] Existing Looks/LUTs, grading, curves, masks, crop, and decorative effects are not lost while producing the reference proposal.
- [ ] Unsupported OS/API, malformed image, and Core Image failure paths return a graceful unavailable result and do not block native proposals.
- [ ] Focused tests cover deterministic fixtures, unavailable/failure paths, provenance, and no opaque-filter persistence.

## Non-goals

- Do not ship a Core ML model in this ticket.
- Do not select the final candidate here.
- Do not claim the Apple reference is perceptually superior for every image.

## Likely files

- `Sources/KromoraKit/Models/RenderEngine.swift`
- `Sources/KromoraKit/Models/RenderEngineResources.swift`
- `Sources/KromoraKit/Models/RenderRequest.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/`
- `Sources/KromoraKit/Models/AutoAdjustment.swift`
- `Tests/KromoraKitTests/`

## Verification

Run focused Core Image/reference tests on the supported macOS SDK and confirm the standard test lane still builds on the minimum deployment target.
