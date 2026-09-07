---
id: LUMO-276
title: Linear-gradient endpoints redraw instead of adjusting gradient length
type: bug
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - gradients
  - ux
created: 2026-09-07T04:05:10.715Z
updated: 2026-09-07T04:16:55.543Z
order: xq
board: product
---

## Objective

Allow either endpoint of an existing linear-gradient mask to adjust the gradient length while
keeping the opposite endpoint, direction, and gradient placement stable.

## Context

When editing a linear gradient, dragging the zero-strength side or full-strength side should
extend or contract the transition from that side. Instead, the current interaction behaves like a
new gradient draw: the gradient is redrawn/repositioned rather than simply changing its length.
This makes precise mask refinement difficult and can unexpectedly move the gradient's fixed side.

The relevant interaction state and endpoint handles are in
`Sources/LumoKit/Models/MaskInteractionState.swift`,
`Sources/LumoKit/ViewModels/AppViewModel+Masking.swift`, and
`Sources/LumoKit/Views/MaskingWorkspace.swift`. The durable definition is
`LinearGradientDefinition` in `Sources/LumoKit/Models/LocalMaskModels.swift`; its existing
`changingFalloff(to:keeping:)` API expresses the intended opposite-edge-fixed behavior.

## Acceptance criteria

- [ ] Dragging the zero-strength endpoint changes only the gradient length while keeping the
      full-strength endpoint fixed.
- [ ] Dragging the full-strength endpoint changes only the gradient length while keeping the
      zero-strength endpoint fixed.
- [ ] Endpoint drags preserve the gradient direction/angle and do not enter creation or center
      translation behavior; crossing/near-zero lengths remain clamped safely.
- [ ] The center and rotation handles retain their existing translation and rotation semantics.
- [ ] Add regression tests proving each endpoint updates `falloff` with the opposite point
      unchanged, and that the interaction does not silently replace the gradient definition.
- [ ] Existing masking, rendering, persistence, and undo/redo tests continue to pass.

## Implementation notes

- Keep endpoint editing in normalized source coordinates and reuse the model-level
  `changingFalloff(to:keeping:)` semantics so the opposite edge remains anchored.
- Distinguish endpoint editing from creation gestures when resolving the active linear handle;
  pointer movement should be interpreted relative to the gesture-start definition.
- Preserve accessibility labels for the zero-strength and full-strength endpoint handles.

### Comment — codex @ 2026-09-07T04:05:42.127Z

Captured the expected endpoint-editing semantics: dragging either linear-gradient side should reuse the existing definition and adjust falloff with the opposite edge anchored, rather than entering creation/redraw behavior. Relevant code paths are listed in the ticket.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
