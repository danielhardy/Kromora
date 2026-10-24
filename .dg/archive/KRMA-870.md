---
id: KRMA-870
title: "Effects inspector: icon toggle for Advanced and a full-width band that slices open"
type: task
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Advanced controls use icon toggles in the Effects inspector, with the flattened-list design described in the handoff.
      result: pass
      notes: Source review confirms icon toggles for Sharpening, Vignette, Grain, and Noise Reduction; the original blue text link is absent.
    - criterion: Opening an advanced control reveals a full-width darker band below its primary control and pushes following content down; closing reverses the reveal.
      result: pass
      notes: Source review confirms the full-width band, hairlines, and animatable RevealHeightLayout transition. The issue context records a confirming offscreen layout capture. I could not observe the live animation because the default library package is locked by another Mac (pid 49242).
    - criterion: Advanced controls open automatically when advanced values are non-neutral, and a closed modified group shows a dot.
      result: pass
      notes: The view observes Effects changes to expand modified groups, and the toggle conditionally displays the accent dot while closed.
    - criterion: VoiceOver announces Advanced <section> controls and exposes Expanded or Collapsed state.
      result: pass
      notes: The toggle sets the requested accessibility label, value, hint, and toggle trait.
    - criterion: Effects inspector tests pass.
      result: pass
      notes: swift test --filter EffectsInspectorTests passed all 11 tests.
  checks_run:
    - swift test --filter EffectsInspectorTests — passed (11 tests, 0 failures).
    - swift run — build succeeded; runtime UI showed a package-lock alert for the existing default library, so animation was not visually observed.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:10:57.207Z
  session: 01MV38VOGLSYN2RLKQ
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T22:09:31.509Z
updated: 2026-10-11T03:10:57.210Z
blockers: []
order: zv
board: product
commits:
  - 2c722ffccae7fefdb17f927c6159098a3d309a88
  - d9efec43fd4ca1a0413c33db3d33fcf105e34770
  - e2e3cedbfe82c4cfb525cfea8fd17984b0754195
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


### Comment — claude @ 2026-10-11T00:40:11.974Z

Follow-up d9efec43fd4ca1a0413c33db3d33fcf105e34770: the open Advanced icon and its dot use KromoraTheme.primaryAccent instead of the system accent (it rendered blue); reset and Advanced icons now share InspectorIconButtonStyle with hover (brighter glyph, soft circle), pressed dimming, and disabled dimming. Hover and press states were not observed in the app.


### Comment — claude @ 2026-10-11T00:50:23.274Z

Design change by the reporter, implemented in e2e3cedbfe82c4cfb525cfea8fd17984b0754195: the Effects inspector is now one flat list with no accordions. Rows: Texture, Clarity, Dehaze, Sharpening (+icon), Vignette (+icon), Grain (+icon), then Noise Reduction (heading with icon and a group reset; main rows Luminance and Color; Detail and Contrast for both live under Advanced). The Advanced icon sits right after the label; the band opens inline under its row with its own reset-advanced icon (new single-undo resetSharpeningAdvanced/resetNoiseAdvanced/resetVignetteAdvanced/resetGrainAdvanced). Per-section reset icons are gone: double-click a label to reset that control, header icon resets all Effects. A band opens automatically when an advanced value is off neutral. Verified with a capture of the real view hosted offscreen; the open/close animation and hover states have not been seen in the running app.


### Comment — claude @ 2026-10-11T01:13:17.000Z

Handoff to verification (implementer: claude; reporter has reviewed and directed the final design). Commits 2c722ffc, d9efec43, e2e3cedb. Effects inspector rebuilt as one flat list: Texture, Clarity, Dehaze, then Sharpening, Vignette and Grain as single rows whose label carries an icon-only Advanced toggle, then Noise Reduction with a heading, the toggle and a group reset. Advanced controls open as a full-width darker band under the row (bleeds past the content inset, hairlines, slice-open reveal via a height-fraction Layout) with its own reset icon; a band opens automatically when an advanced value is off neutral. The toggle and its dot use KromoraTheme.primaryAccent (the system accent rendered blue). Reset and Advanced icons share InspectorIconButtonStyle: hover brightens the glyph and adds a soft circle, pressed and disabled states dim. New single-undo resetSharpeningAdvanced, resetNoiseAdvanced, resetVignetteAdvanced, resetGrainAdvanced with a test that only the advanced values reset. Section-level reset icons are gone by design (header resets all; double-click a label resets one control). Verified with an offscreen capture of the real view; the open/close animation and hover were not seen in the running app by me. Tests: EffectsInspectorTests green; the only inspector failure is KRMA-853.


### Comment — claude @ 2026-10-11T01:13:26.209Z

Commits for KRMA-870 (oldest first; review with git show <sha>):
- 2c722ffccae7fefdb17f927c6159098a3d309a88 KRMA-870: icon toggle for Effects Advanced and a full-width band that slices open
- d9efec43fd4ca1a0413c33db3d33fcf105e34770 KRMA-870: copper active state and hover states for inspector icon buttons
- e2e3cedbfe82c4cfb525cfea8fd17984b0754195 KRMA-870: flatten the Effects inspector into one list with an Advanced icon beside each label

## Agent log

- 2026-10-11T03:10:57.207Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Advanced controls use icon toggles in the Effects inspector, with the flattened-list design described in the handoff. (pass) — Source review confirms icon toggles for Sharpening, Vignette, Grain, and Noise Reduction; the original blue text link is absent.
- [x] Opening an advanced control reveals a full-width darker band below its primary control and pushes following content down; closing reverses the reveal. (pass) — Source review confirms the full-width band, hairlines, and animatable RevealHeightLayout transition. The issue context records a confirming offscreen layout capture. I could not observe the live animation because the default library package is locked by another Mac (pid 49242).
- [x] Advanced controls open automatically when advanced values are non-neutral, and a closed modified group shows a dot. (pass) — The view observes Effects changes to expand modified groups, and the toggle conditionally displays the accent dot while closed.
- [x] VoiceOver announces Advanced <section> controls and exposes Expanded or Collapsed state. (pass) — The toggle sets the requested accessibility label, value, hint, and toggle trait.
- [x] Effects inspector tests pass. (pass) — swift test --filter EffectsInspectorTests passed all 11 tests.
Checks run:
- swift test --filter EffectsInspectorTests — passed (11 tests, 0 failures).
- swift run — build succeeded; runtime UI showed a package-lock alert for the existing default library, so animation was not visually observed.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38VOGLSYN2RLKQ
Summary: Independent verification passed; 11 Effects inspector tests passed. No code findings or verification fixes. Live animation could not be observed because the default library is locked by another Mac.
