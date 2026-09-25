---
id: KRMA-577
title: "Theme: centralize the primary interactive accent in a bronze/copper tone"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: KromoraTheme exposes one semantic primary-accent token that all migrated usages consume
      result: pass
      notes: KromoraTheme.primaryAccent (SwiftUI Color) and primaryAccentNSColor share one backing dynamic NSColor 'KromoraPrimaryAccent' defined once in KromoraTheme.swift.
    - criterion: Default is muted bronze/copper, recorded in handoff
      result: pass
      notes: "Dark #CE865C (206,134,92), light #9D5738 (157,87,56); documented in the issue comment and covered by KromoraThemeTests.testPrimaryAccentResolvesToCentralizedCopperVariants."
    - criterion: Slider thumbs and reviewed selected/focused controls use the token
      result: pass
      notes: "NeutralOriginSlider stroke/fill migrated. Verification found and fixed one missed spot: LightInspectorView's tone curve line still used .accentColor while its own point handle used the token, producing a mismatched control; fixed to use KromoraTheme.primaryAccent (commit 3e7ed17)."
    - criterion: Hover, pressed, disabled states remain distinguishable/accessible
      result: pass
      notes: Disabled paths keep system tertiary/disabled colors (unchanged code paths); hover/pressed rely on native SwiftUI tint-aware button styles, unaffected by the token swap.
    - criterion: Mask overlay and primary UI accent feel related but remain independently represented; mask rendering/settings unchanged
      result: pass
      notes: MaskOverlayColor/MaskInteractionState untouched by the diff; only view-layer selection/handle colors in MaskingWorkspace.swift changed.
    - criterion: Source search and manual review of remaining blue/system-accent usages, with rationale for retained ones
      result: pass
      notes: "Verified no remaining Color.accentColor/NSColor.controlAccentColor in Sources/KromoraKit after the fix. Retained: NeutralOriginSlider's .systemBlue (one stop in a hue spectrum gradient) and RecipeReportView's .blue (blue tone-curve channel line and a data-series stat badge tint) — both are content/data colors, not primary-accent semantics."
    - criterion: Dark-surface contrast checked for slider thumbs/selected/focused elements; appearance variants verified
      result: pass
      notes: KromoraThemeTests.testDarkPrimaryAccentHasAccessibleContrastAgainstCanvas asserts >4.5:1 contrast against the dark canvas background; both light/dark NSColor variants are exercised.
    - criterion: Adjustment gradient tracks, slider layout, thumb geometry, interaction behavior unchanged
      result: pass
      notes: Only stroke/fill color lines changed in NeutralOriginSlider.swift; geometry, gradients, and behavior code paths untouched. NeutralOriginSliderTests (18 cases) pass.
  checks_run:
    - swift build (clean, before and after fix)
    - swift test --filter 'KromoraThemeTests|NeutralOriginSliderTests' (20 passed)
    - git diff --check (no whitespace errors)
    - grep audit for remaining Color.accentColor / NSColor.controlAccentColor across Sources/KromoraKit (none remain after fix)
  findings:
    - LightInspectorView.swift:216 - tone curve line used .accentColor while its own point handle already used KromoraTheme.primaryAccent, leaving one interactive control visually split between old and new accent colors. Fixed.
  fixes:
    - "Sources/KromoraKit/Views/LightInspectorView.swift: changed the tone curve stroke color from .accentColor to KromoraTheme.primaryAccent so the curve line matches its already-migrated point handles."
  verification_commits:
    - 3e7ed17
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T06:10:14.476Z
  session: 01MUGK80ICVUL9DRYB
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - ux
  - theme
  - color
  - masking
created: 2026-09-25T02:38:56.550Z
updated: 2026-09-25T06:10:14.478Z
blockers: []
order: a0
board: product
commits:
  - 3e7ed17
---

## Objective

Replace Kromora-owned blue primary-accent styling with one centralized semantic app token whose default is a muted bronze/copper suited to the dark editing UI. Changing the token later should update the app’s primary interactive accents from one source.

## Investigation findings

- `Sources/KromoraKit/Views/KromoraTheme.swift` already centralizes appearance-aware surface roles (`windowBackground`, `secondaryChrome`, `canvasBackground`, and related surfaces), but it has no primary-accent role. Extend this existing theme layer rather than creating a parallel theme system.
- `Sources/KromoraKit/Views/NeutralOriginSlider.swift` draws the slider thumb ring with `NSColor.controlAccentColor`, which follows the macOS accent color rather than a Kromora token.
- SwiftUI app views use `Color.accentColor` for selected, focused, or active elements. Examples include `MaskingWorkspace.swift`, `CropOverlayView.swift`, `LightInspectorView.swift`, `FilmstripView.swift`, `LibraryGridView.swift`, `LookInspectorView.swift`, and `CropInspectorView.swift`. Audit each use to determine whether it is a Kromora primary accent or native/system state before migrating it.
- The default mask overlay color is separately configurable. `MaskOverlayAppearance.standard` currently uses `MaskOverlayColor.orange` (red 1, green 0.5, blue 0, alpha 1); this is a visual reference, not a reason to couple UI accent changes to mask rendering or persisted overlay settings.

## Desired visual direction

Use a dark-interface-friendly, muted bronze/copper accent: warm and visible, with a premium photographic-tool feel. Avoid bright orange, yellow/gold, and highly saturated neon copper. The accent must remain easy to see on the existing dark surfaces.

The UI primary accent should harmonize with the default mask overlay color. They may start from the same or a closely related base, but keep `primaryAccent` and mask-overlay semantics independently changeable. The mask overlay remains user-configurable and its existing default/persisted behavior is not changed by this ticket.

## Requirements

- Add one semantic `KromoraTheme.primaryAccent` role (or the project’s equivalent) in the existing centralized theme source. Do not scatter calibrated or hex values across views.
- If appearance variants are needed, resolve them from a single centralized definition or asset so there remains one obvious source of truth.
- Migrate app-owned primary accent usage where blue currently indicates Kromora selection, focus, active state, or primary interaction. This includes the NeutralOriginSlider thumb ring and appropriate selected/focused controls.
- Inspect every candidate use instead of replacing every blue. Keep semantic colors such as culling pick/reject colors, hue/color-spectrum ramps, recipe status indicators, image/content colors, and native macOS behaviors that are not Kromora’s primary accent.
- Derive hover, pressed, selected, and disabled states from the central accent or the existing state pattern. Keep each state legible against dark surfaces.
- Preserve slider geometry, sizing, hover/drag behavior, values, and adjustment gradients. Do not change mask pixel rendering, overlay color settings, or content colors as a side effect.
- Do not introduce a user-selectable theme system or a broad design-system refactor.

## Acceptance criteria

- `KromoraTheme` exposes one semantic primary-accent token, and changing its source value updates all migrated Kromora primary-accent usages.
- The token’s default is a muted bronze/copper; record the exact chosen value and its source in the handoff.
- Slider thumbs and reviewed selected/focused controls use the token. Hover, pressed, and disabled states remain distinguishable and accessible.
- The default mask overlay and primary UI accent feel visually related while remaining separately represented and independently adjustable. Mask overlay rendering and saved user settings are unchanged.
- A source search and manual review of remaining blue/system-accent usages identify which are semantic, native macOS behavior, image/content colors, or intentionally retained.
- Dark-surface contrast is checked for slider thumbs, selected controls, and focused elements. Verify appearance variants if the chosen token supports both light and dark appearances.
- Adjustment gradient tracks, slider layout, thumb geometry, and interaction behavior are unchanged.

## Implementation notes

- Existing theme source: `Sources/KromoraKit/Views/KromoraTheme.swift`.
- Slider thumb source: `Sources/KromoraKit/Views/NeutralOriginSlider.swift` (`NSColor.controlAccentColor`).
- Representative SwiftUI accent call sites: `Sources/KromoraKit/Views/MaskingWorkspace.swift`, `CropOverlayView.swift`, `LightInspectorView.swift`, `FilmstripView.swift`, `LibraryGridView.swift`, `LookInspectorView.swift`, and `CropInspectorView.swift`.
- Mask overlay model and default: `Sources/KromoraKit/Models/MaskInteractionState.swift` and `Sources/KromoraKit/Presentation/MaskInteractionPresentationBridge.swift`.
- Be careful with `.accentColor` uses in canvas and mask-overlay drawing code: classify them before migration so this UI-token change does not alter mask/image rendering.

## Tests and verification

- Add or update focused theme/UI tests to verify the centralized token resolves to the intended bronze/copper value and remains visible against dark surfaces; cover appearance variants if present.
- Confirm the slider thumb and representative selected/active controls consume the token.
- Search remaining app-owned hard-coded/system-blue accent usages and record why retained uses stay unchanged.
- Confirm mask rendering/settings and adjustment gradient tracks are unchanged.
- `swift build`
- Run relevant UI/unit tests.
- `git diff --check`

## Handoff

Record where the token lives, its exact default value, the major UI components migrated, blue usages intentionally left unchanged and why, how to change the global accent later, and evidence that hover/pressed/disabled states remain legible.

## Out of scope

- Slider redesign or adjustment-gradient color changes.
- Masking UI redesign or mask-rendering color changes.
- Image/content color changes.
- A full user-selectable theme system.


### Comment — codex @ 2026-09-25T06:08:19.265Z

Implemented and verified. KromoraTheme.primaryAccent is the one app token: dark #CE865C (sRGB 206,134,92), light #9D5738 (sRGB 157,87,56). Change the centralized primaryAccentColor variants in KromoraTheme.swift to retune it. Applied at the ContentView tint and to slider thumb/non-gradient fill, crop controls/handles, source browser, filmstrip, library selection, look selection, masking UI selections/handles, tone curve, and removable-media selection. Disabled controls retain system tertiary/disabled styling; hover and pressed feedback continue through SwiftUI's tint-aware native button styles. Dark token contrast against the editor canvas is >4.5:1 (unit checked). Slider gradient tracks, dimensions, geometry, and behavior are unchanged. Mask overlay color/settings/rendering are unchanged. Remaining blue uses: NeutralOriginSlider's systemBlue is one stop in the hue spectrum; RecipeReportView blue draws the blue RGB output channel and marks recipe sample/status data. Tests: swift build; swift test --filter 'KromoraThemeTests|NeutralOriginSliderTests' (20 passed); git diff --check. Committed as 436fa46.

## Agent log

- 2026-09-25T06:10:14.476Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] KromoraTheme exposes one semantic primary-accent token that all migrated usages consume (pass) — KromoraTheme.primaryAccent (SwiftUI Color) and primaryAccentNSColor share one backing dynamic NSColor 'KromoraPrimaryAccent' defined once in KromoraTheme.swift.
- [x] Default is muted bronze/copper, recorded in handoff (pass) — Dark #CE865C (206,134,92), light #9D5738 (157,87,56); documented in the issue comment and covered by KromoraThemeTests.testPrimaryAccentResolvesToCentralizedCopperVariants.
- [x] Slider thumbs and reviewed selected/focused controls use the token (pass) — NeutralOriginSlider stroke/fill migrated. Verification found and fixed one missed spot: LightInspectorView's tone curve line still used .accentColor while its own point handle used the token, producing a mismatched control; fixed to use KromoraTheme.primaryAccent (commit 3e7ed17).
- [x] Hover, pressed, disabled states remain distinguishable/accessible (pass) — Disabled paths keep system tertiary/disabled colors (unchanged code paths); hover/pressed rely on native SwiftUI tint-aware button styles, unaffected by the token swap.
- [x] Mask overlay and primary UI accent feel related but remain independently represented; mask rendering/settings unchanged (pass) — MaskOverlayColor/MaskInteractionState untouched by the diff; only view-layer selection/handle colors in MaskingWorkspace.swift changed.
- [x] Source search and manual review of remaining blue/system-accent usages, with rationale for retained ones (pass) — Verified no remaining Color.accentColor/NSColor.controlAccentColor in Sources/KromoraKit after the fix. Retained: NeutralOriginSlider's .systemBlue (one stop in a hue spectrum gradient) and RecipeReportView's .blue (blue tone-curve channel line and a data-series stat badge tint) — both are content/data colors, not primary-accent semantics.
- [x] Dark-surface contrast checked for slider thumbs/selected/focused elements; appearance variants verified (pass) — KromoraThemeTests.testDarkPrimaryAccentHasAccessibleContrastAgainstCanvas asserts >4.5:1 contrast against the dark canvas background; both light/dark NSColor variants are exercised.
- [x] Adjustment gradient tracks, slider layout, thumb geometry, interaction behavior unchanged (pass) — Only stroke/fill color lines changed in NeutralOriginSlider.swift; geometry, gradients, and behavior code paths untouched. NeutralOriginSliderTests (18 cases) pass.
Checks run:
- swift build (clean, before and after fix)
- swift test --filter 'KromoraThemeTests|NeutralOriginSliderTests' (20 passed)
- git diff --check (no whitespace errors)
- grep audit for remaining Color.accentColor / NSColor.controlAccentColor across Sources/KromoraKit (none remain after fix)
Findings:
- LightInspectorView.swift:216 - tone curve line used .accentColor while its own point handle already used KromoraTheme.primaryAccent, leaving one interactive control visually split between old and new accent colors. Fixed.
Fixes:
- Sources/KromoraKit/Views/LightInspectorView.swift: changed the tone curve stroke color from .accentColor to KromoraTheme.primaryAccent so the curve line matches its already-migrated point handles.
Verification commits:
- 3e7ed17
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGK80ICVUL9DRYB
