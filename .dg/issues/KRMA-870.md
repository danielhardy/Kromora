---
id: KRMA-870
title: "Effects inspector: icon toggle for Advanced and a full-width band that slices open"
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T22:09:31.509Z
updated: 2026-10-10T22:09:31.882Z
blockers: []
order: zzzzz
board: product
---

## Objective

The Effects inspector's advanced controls (Sharpening, Vignette, Grain) used a blue "Advanced" text link in the section header and opened a rounded card with an accent outline inside the section. Replace the link with an icon beside the reset icon, and make the advanced controls feel like part of the panel: a full-width, darker band that slices open under the section's main control and pushes the content below it down.

## Work done (Sources/KromoraKit/Views/EffectsInspectorView.swift)

- `advancedToggle`: an icon-only button (`slider.horizontal.3`, 24 pt, same footprint as `ResetIconButton`) in the header accessory slot, so it sits next to the reset icon. Secondary colour when closed; accent colour on a faint circle when open; a small dot when closed but an advanced value is off neutral. Opening it also opens its section so the band never hides behind a collapsed header. Accessibility label, value, hint and toggle trait kept.
- `InspectorAdvancedBand` replaces `InspectorAdvancedGroup`: shown after the section's main row (outside the disclosure's content), bleeds past the content inset to the panel edges with `.padding(.horizontal, -InspectorStyle.contentInset)`, darker background (black at 22%), hairlines top and bottom, content inset back to the normal margin, and the existing "<Section> · Advanced" caption.
- Insert/remove transition: `RevealHeightLayout` reports a fraction of the band's height and the container masks vertically only, so the band grows from a slit and the rows below ride down with it instead of being overlapped; opacity fades in with it. The toggle animates with a 0.25 s ease.
- Applied to Sharpening, Vignette and Grain; other sections unchanged.
- An offscreen render (ImageRenderer at 280 pt, dark) confirmed the layout: icon beside reset, band flush to both panel edges with hairlines, following rows pushed down. The transition itself was not observed.

## Acceptance criteria

- No blue "Advanced" text link; the advanced toggle is an icon next to reset in each of the three headers.
- Opening it reveals a full-width darker band under the main control with the rest of the panel pushed down; closing reverses it.
- The advanced values still open automatically when any is off neutral; a closed band shows the modified dot.
- VoiceOver announces "Advanced <section> controls" with Expanded/Collapsed.
- Effects inspector tests pass (they do; the only failure in the inspector suites is KRMA-853).
- Not yet seen in the running app, in particular the open/close animation.
