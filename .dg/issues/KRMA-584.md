---
id: KRMA-584
title: Expose automatic Sky mask in masking workflow
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - masking
  - semantic-mask
  - ui
created: 2026-09-25T03:19:13.712Z
updated: 2026-09-25T03:19:33.864Z
depends_on:
  - KRMA-583
blockers: []
order: zzzx
board: product
---

## Objective

Expose the production Sky semantic matte in Kromora's existing masking workflow. Users can create a Sky mask from Add Mask and edit it like the existing Subject, Person, and Foreground masks.

This issue depends on KRMA-583, which implements the scene-semantic Sky provider. Use its analysis-space matte, cache, and availability behavior; do not add UI workarounds for provider alignment or segmentation issues.

## Expected behavior

```text
Add Mask → Sky
```

- Selecting Sky requests the semantic matte and, when applicable, creates one ordinary editable local mask.
- The mask uses the existing overlay rendering and local adjustment workflow.
- It can be selected, renamed, inverted, reset, or deleted wherever those actions are supported for other local masks.
- Adjustments and mask state remain independent from other masks.
- Switching photos uses the correct photo's cached analysis and never carries a prior photo's matte into the new image.
- If no usable Sky is detected, do not create an empty or otherwise meaningless mask. Use the existing unavailable/not-applicable feedback; if none fits this flow, add the smallest consistent message or state.

## UI integration

- Add Sky alongside existing automatic semantic-mask choices in Add Mask.
- Do not add a separate AI section or redesign Add Mask.
- Expose only Sky; keep the existing structure compatible with future scene classes without adding Vegetation, Water, Buildings, or Ground now.
- Reuse existing semantic-mask loading/progress behavior. Keep the UI responsive while analysis runs and reuse scene inference already computed for the image.
- Render the provider matte through the normal mask overlay. If alignment is offset, stretched, or cropped, fix provider coordinate mapping in KRMA-583 rather than introducing rendering compensation here.

## Tests

Add or update deterministic workflow/UI tests covering:

- Sky appears in Add Mask.
- Selecting Sky creates exactly one editable Sky mask when applicable.
- No-sky/unavailable results do not create a bogus mask and communicate unavailability consistently.
- Sky selection, rename, inversion, reset/deletion behavior follows existing mask semantics.
- Sky adjustments do not mutate another mask's matte or adjustments.
- Switching photos requests/displays the correct cached Sky analysis without leaking the previous image's result.
- Existing semantic-mask and masking workflow behavior remains unchanged.

Prefer provider/cache test seams or synthetic results over tests that depend on nondeterministic model inference. Keep actual model inference off the main actor/thread.

## Acceptance criteria

- Sky is available from Add Mask next to existing automatic semantic options.
- A usable result creates a normal independently editable local mask with the existing overlay and adjustment behavior.
- An unavailable result creates no mask and gives consistent feedback.
- Mask selection and supported rename/invert/reset/delete actions behave as they do for other semantic masks.
- Per-mask adjustments and per-photo cached results stay isolated.
- Existing loading and inference reuse behavior is preserved; the UI remains responsive.
- No renderer alignment hacks or additional scene categories are introduced.

## Dependency and context

- Depends on KRMA-583: production on-device Sky semantic mask provider.
- Follow the semantic mask creation path, Add Mask options, loading state, and local-mask tests already used by Subject, Person, and Foreground.
- Kromora targets macOS 14+ and has no third-party runtime dependencies.

## Checks

- `swift build`
- Run relevant `MaskingWorkflow`, `LocalMask`, and semantic-mask tests.
- `git diff --check`

## Out of scope

- Sky replacement or generative editing.
- New mask-combination UX or general Add Mask redesign.
- Vegetation, Water, Buildings, Ground, or other scene classes.
- UI-side correction of matte alignment or segmentation quality.

## Handoff

Document where Sky was added to Add Mask, how provider availability/loading is surfaced, how mask creation uses the existing local-mask workflow, and which tests/checks were run.
