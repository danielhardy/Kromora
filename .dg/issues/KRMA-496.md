---
id: KRMA-496
title: "Crop orientation controls: square buttons with always-visible icons"
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Two square landscape/portrait controls appear for ratios supporting orientation; icons visible
      result: pass
      notes: Fixed 32x32 bordered buttons with explicit Image(systemName:) and rectangle fallback, matching the rotate/flip pattern. Verified by code review; no interactive UI run.
    - criterion: Tapping each still flips orientation and reshapes crop frame
      result: pass
      notes: Buttons call the unchanged onAspectRatioChange(aspectRatio, orientation) path.
    - criterion: Freeform does not show the orientation pair
      result: pass
      notes: Still gated by supportsOrientationSelection.
    - criterion: Note confirming icons visible in light and dark chrome
      result: pass
      notes: Implementer note only; no screenshot captured. Native bordered buttons with explicit glyphs adapt to appearance.
    - criterion: scripts/ci-tests.sh fast and serial pass
      result: pass
      notes: fast 1103 tests, serial 398 tests with 1 expected skip, 0 failures.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
  findings:
    - Container-level accessibilityLabel/Value/Hint on the orientation HStack, without an explicit container element, can propagate to the child buttons and override their Landscape/Portrait labels and selected values.
    - The implementation commit also contains unrelated swift-format reflow in CropInspectorView.swift (non-blocking, cosmetic).
  fixes:
    - "Added .accessibilityElement(children: .contain) to the orientation HStack and dropped the redundant container value so per-button labels and selected state survive."
  verification_commits:
    - 779962d
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T00:08:10.454Z
  session: 01MUAHINW22MRXSP85
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - crop
  - ui
  - ux
created: 2026-09-20T23:48:03.716Z
updated: 2026-09-21T00:08:10.455Z
order: a0
board: product
commits:
  - 779962d
---

## Objective

When a non-freeform crop aspect is selected, the landscape / portrait orientation controls are **square buttons** whose icons are **always visible** (and clearly readable in both selected and unselected states).

## Context

User report (2026-09-20): in crop mode, choosing anything besides Freeform shows handy landscape / portrait controls. Those controls should be square, and currently the icon on them is not always visible.

Today (`CropInspectorView.aspectSection` in `Sources/KromoraKit/Views/CropInspectorView.swift`): when `aspectRatio.supportsOrientationSelection`, a SwiftUI `Picker` with `.pickerStyle(.segmented)`, `.controlSize(.small)`, and `.labelStyle(.iconOnly)` offers:

- Landscape — `rectangle.landscape`
- Portrait — `rectangle.portrait`

A full-width segmented control tends to stretch into wide pills rather than square tiles, and AppKit/SwiftUI segmented pickers are unreliable about rendering SF Symbol–only labels (especially at `.small`), which matches “icon isn’t always visible.”

Introduced with the aspect dropdown work (KRMA-476). Behaviour of `onAspectRatioChange` / frame reshaping is unchanged by this ticket — chrome only (unless a custom control is required to get reliable icons).

## Requirements

- Replace or restyle the orientation control so each option is a **square** hit target (equal width and height), side by side under the Aspect menu when orientation applies.
- Landscape and portrait **icons always show** in both selected and unselected states (not blank segments, not text-only fallbacks that appear only sometimes). Prefer explicit `Image(systemName:)` / bordered buttons over relying on segmented `Label` + `.iconOnly` if that remains flaky.
- Selected state remains obvious (tint, fill, or ring) without hiding the glyph.
- Accessibility: still “Landscape” / “Portrait”; VoiceOver can distinguish selection.
- Freeform, Original, and Square (no orientation control) unchanged — control only appears when `supportsOrientationSelection` is true.
- No change to aspect math or KRMA-486 (dropdown apply) beyond presentation.

## Acceptance criteria

- [ ] With a ratio that supports orientation (e.g. 16:9, 4:5), two square landscape/portrait controls appear; icons are visible every time the control is shown.
- [ ] Tapping each still flips orientation and reshapes the crop frame as today.
- [ ] Freeform does not show the orientation pair.
- [ ] Screenshot or short note in the ticket confirming icons visible in light and dark chrome if both are supported.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass (no new behaviour tests required unless the control type changes enough to warrant a small accessibility/tag test).

## Implementation notes

- Primary file: `Sources/KromoraKit/Views/CropInspectorView.swift` (~orientation `Picker`).
- Likely fix: two square `.bordered` / toggle-style buttons in an `HStack` (same pattern as rotate/flip in `rotationAndFlipSection`), not a stretched segmented picker.
- Confirm SF Symbol names exist on the macOS 14 deployment target; if `rectangle.landscape` / `rectangle.portrait` are missing on older SDKs, use available rectangle symbols with explicit rotation or asset fallbacks so icons never blank out.
- Related: KRMA-476 (dropdown + orientation control), KRMA-486 (aspect apply behaviour).

### Comment — codex @ 2026-09-21T00:05:52.574Z

Implemented in commit 8860922. Replaced the segmented orientation Picker with two explicit bordered buttons in CropInspectorView: each is a fixed 32x32 square, uses a visible Image(systemName:) glyph, and has a rectangle/rotation fallback so older symbol sets cannot render blank. Selected/unselected tint and accessibility values/traits distinguish state; callbacks still use the existing onAspectRatioChange path, and the pair remains conditional on supportsOrientationSelection. Light/dark chrome note: explicit glyphs are rendered in both states against native bordered controls, with accent/secondary tint preserving selected-state contrast. Verification: scripts/ci-tests.sh fast (1103 passed), scripts/ci-tests.sh serial (398 passed, 1 expected RAW-fixture skip), swift build, Swift format, git diff --check, and dg validate (OK; existing model-name warnings only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T00:08:10.454Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Two square landscape/portrait controls appear for ratios supporting orientation; icons visible (pass) — Fixed 32x32 bordered buttons with explicit Image(systemName:) and rectangle fallback, matching the rotate/flip pattern. Verified by code review; no interactive UI run.
- [x] Tapping each still flips orientation and reshapes crop frame (pass) — Buttons call the unchanged onAspectRatioChange(aspectRatio, orientation) path.
- [x] Freeform does not show the orientation pair (pass) — Still gated by supportsOrientationSelection.
- [x] Note confirming icons visible in light and dark chrome (pass) — Implementer note only; no screenshot captured. Native bordered buttons with explicit glyphs adapt to appearance.
- [x] scripts/ci-tests.sh fast and serial pass (pass) — fast 1103 tests, serial 398 tests with 1 expected skip, 0 failures.
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
Findings:
- Container-level accessibilityLabel/Value/Hint on the orientation HStack, without an explicit container element, can propagate to the child buttons and override their Landscape/Portrait labels and selected values.
- The implementation commit also contains unrelated swift-format reflow in CropInspectorView.swift (non-blocking, cosmetic).
Fixes:
- Added .accessibilityElement(children: .contain) to the orientation HStack and dropped the redundant container value so per-button labels and selected state survive.
Verification commits:
- 779962d
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAHINW22MRXSP85
Summary: Verified: square 32x32 orientation buttons with explicit glyphs; fixed container accessibility override; fast/serial suites pass.
