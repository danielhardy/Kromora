---
id: KRMA-822
title: Effects inspector simple vs advanced for Vignette, Grain, and Sharpening
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Vignette: Amount primary, other four under collapsed-by-default Advanced"
      result: pass
    - criterion: "Grain: Amount primary, Size/Roughness under Advanced"
      result: pass
    - criterion: "Sharpening: Amount primary, Radius/Detail/Masking + caption under Advanced; section collapsed by default"
      result: pass
    - criterion: Auto-expand Advanced on non-neutral values (load and section open)
      result: pass
      notes: onChange initial:true plus section-expand hook; expand-only, never auto-collapses
    - criterion: Resets unchanged
      result: pass
    - criterion: Bindings unchanged
      result: pass
      notes: Same vignetteBinding/grainBinding/detailBinding via shared row helpers
    - criterion: Accessibility labels and reset reachability
      result: pass
      notes: Rows reuse existing valueRow; not exercised with VoiceOver
    - criterion: swift build and EffectsInspectorTests pass
      result: pass
      notes: 10 tests, 0 failures; no RenderPipeline/model/schema diffs
  checks_run:
    - swift build (pass)
    - swift test --filter EffectsInspectorTests (10 tests, 0 failures)
    - Code review of commit 4e45e125
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T14:41:33.224Z
  session: 01MUVCXW6J2IDM3AJJ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - editor
  - inspector
  - effects
  - ui
created: 2026-10-05T13:10:27.529Z
updated: 2026-10-05T14:41:33.228Z
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Views/EffectsInspectorView.swift
    - Sources/KromoraKit/Views/InspectorDisclosure.swift
    - Sources/KromoraKit/Views/LightInspectorView.swift
    - Sources/KromoraKit/Models/EffectsAdjustments.swift
    - Sources/KromoraKit/Models/EffectsControl.swift
    - Sources/KromoraKit/ViewModels/AppViewModel+Effects.swift
    - Tests/KromoraKitTests/EffectsInspectorTests.swift
  docs:
    - CLAUDE.md
  issues:
    - KRMA-820
  commands:
    - swift build
    - swift test --filter EffectsInspectorTests
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T14:40:57.718Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Restructure the Effects inspector so **Vignette**, **Grain**, and **Sharpening** expose a single primary **Amount** slider when their section is open, with secondary parameters tucked into a nested **Advanced** disclosure. This is a **presentation-only** change: the same bindings, defaults, reset semantics, render pipeline, and persisted edit document must behave exactly as today.

## User report

Vignette and Grain feel heavy when every sub-parameter is visible at once. Sharpening dominates the panel because its section starts expanded with four sliders. The desired pattern matches Light’s **Advanced Curve** nested disclosure: one obvious control up front, expert shape parameters one click away. Moving Amount alone should continue to use the existing neutral subordinate defaults (midpoint/feather/roundness/highlights for vignette; size/roughness for grain; radius/detail/masking for sharpening) without inventing new presets or non-zero starting amounts.

## Context

Today `EffectsInspectorView` lists all `VignetteControl` and `GrainControl` cases inside each top-level disclosure, and Sharpening shows Amount, Radius, Detail, and Masking together with Sharpening expanded by default. The adjustment models already document that only Amount enables vignette/grain and that subordinates stay persisted at their neutrals (`EffectsAdjustments.swift`). No kernel, `RenderPipeline`, or schema work is in scope.

**Out of scope (explicit):**

- Noise Reduction layout (six sliders) — follow-up if this lands well.
- Export **output** sharpening (medium/strength in the export sheet).
- New parameters, changed ranges, changed defaults, or “simple mode” that rewrites stored values.
- Texture / Clarity / Dehaze section changes.

## Acceptance criteria

- [ ] **Vignette:** With the Vignette section expanded, **Amount** is always visible. Midpoint, Roundness, Feather, and Highlights live under a nested disclosure labeled **Advanced** (or equivalent clear copy), default **collapsed** when all subordinates are at their `VignetteControl.neutral` values.
- [ ] **Grain:** With the Grain section expanded, **Amount** is always visible. Size and Roughness are under nested **Advanced**, default collapsed when size/roughness are neutral.
- [ ] **Sharpening:** With the Sharpening section expanded, **Amount** is always visible. Radius, Detail, and Masking (and the existing masking caption) are under nested **Advanced**, default collapsed when those three match `DetailControl` neutrals. Sharpening should not default to showing four sliders on first open (align default expansion with Vignette/Grain: section may stay collapsed; advanced stays collapsed until needed).
- [ ] **Auto-expand Advanced:** When a document has non-neutral subordinate values for that tool, opening the section (or loading the image) expands **Advanced** automatically so existing edits remain discoverable without hunting.
- [ ] **Resets unchanged:** Section-level “Reset Vignette” / “Reset Grain” and per-control resets still call the same `AppViewModel` methods; identity and `hasVignetteAdjustments` / `hasGrainAdjustments` / detail sharpening semantics are unchanged.
- [ ] **Bindings unchanged:** All sliders still use existing `vignetteBinding`, `grainBinding`, and `detailBinding` with the same interactive preview begin/end hooks as today.
- [ ] **Accessibility:** Amount and Advanced rows remain labeled; VoiceOver can reach advanced controls and per-row reset actions.
- [ ] **Tests:** `swift build` and `swift test --filter EffectsInspectorTests` pass; update or add view-structure tests only if the test target already asserts inspector hierarchy (otherwise manual smoke: drag Amount on each tool, expand Advanced, reset).

## Implementation notes

- Primary file: `EffectsInspectorView.swift`. Reuse `InspectorDisclosure` the same way `LightInspectorView` nests **Advanced Curve** under Tone Curve.
- Prefer `@State` for each section’s `advancedExpanded`, initialized from whether subordinates differ from neutral (and optionally `.onChange` of document effects to expand when a preset/Look loads non-default shape).
- Keep `InspectorSectionResetButton` placement consistent with today (still resets full vignette/grain, not “advanced only”).
- Do not add ViewModel API unless a tiny helper (e.g. `vignetteHasAdvancedAdjustments`) keeps the view readable; reading `document.effects` in the view is acceptable for expansion state if that matches nearby inspectors.
- Visual density: nested Advanced can use slightly tighter spacing; match `InspectorStyle` patterns elsewhere.

## Non-goals / verification guardrails

- Golden images, Metal kernel parity, and render tests should **not** change.
- If a verifier sees diffs in `RenderPipeline.swift`, `EffectsAdjustments.swift` clamping, or edit JSON schema, treat as scope creep and return to review.

### Comment — codex @ 2026-10-05T14:40:55.044Z

Restructured Vignette, Grain, and Sharpening so Amount stays primary and subordinate controls sit under Advanced. Non-neutral shape values auto-expand Advanced; bindings, reset callbacks, and preview hooks are preserved. Verification: swift build; swift test --filter EffectsInspectorTests (10 passed); git diff --check. Manual UI smoke was unavailable because the development app reported the library package was locked by another process. Commit: 4e45e125.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-05T14:41:33.224Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Vignette: Amount primary, other four under collapsed-by-default Advanced (pass)
- [x] Grain: Amount primary, Size/Roughness under Advanced (pass)
- [x] Sharpening: Amount primary, Radius/Detail/Masking + caption under Advanced; section collapsed by default (pass)
- [x] Auto-expand Advanced on non-neutral values (load and section open) (pass) — onChange initial:true plus section-expand hook; expand-only, never auto-collapses
- [x] Resets unchanged (pass)
- [x] Bindings unchanged (pass) — Same vignetteBinding/grainBinding/detailBinding via shared row helpers
- [x] Accessibility labels and reset reachability (pass) — Rows reuse existing valueRow; not exercised with VoiceOver
- [x] swift build and EffectsInspectorTests pass (pass) — 10 tests, 0 failures; no RenderPipeline/model/schema diffs
Checks run:
- swift build (pass)
- swift test --filter EffectsInspectorTests (10 tests, 0 failures)
- Code review of commit 4e45e125
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUVCXW6J2IDM3AJJ
Summary: Verified: build and EffectsInspectorTests pass; code review found no blocking issues. Manual UI smoke not performed.
