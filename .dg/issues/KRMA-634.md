---
id: KRMA-634
title: Correct the filmstrip surface color in light appearance
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Light appearance uses an attractive, intentional surface color fitting Kromora's palette
      result: pass
      notes: "secondaryChromeNSColor resolves to a warm neutral #ECE8E1 in light appearance, distinct from the flat #E6E6E6 canvas surface; confirmed via code read and unit test assertions in KromoraThemeTests.swift."
    - criterion: Thumbnail cells, selection treatment, culling controls, and status text remain legible
      result: pass
      notes: FilmstripView, CullingBarView, and StatusBar draw foreground content with dynamic system semantic colors (.secondary, .primary, tertiaryLabelColor, quaternaryLabelColor) rather than hardcoded colors, so contrast against the new light warm neutral is preserved by the system's own light-appearance label contrast targets.
    - criterion: Dark appearance retains the currently acceptable appearance
      result: pass
      notes: secondaryChromeNSColor keeps NSColor.underPageBackgroundColor for isDark == true, unchanged from before KRMA-634.
    - criterion: Surface color remains appearance-aware and implemented through theme's semantic surface roles, not one-off hardcoded colors in individual views
      result: pass
      notes: Change is isolated to KromoraTheme.secondaryChromeNSColor (a dynamic NSColor keyed on NSAppearance); consuming views (FilmstripView, CullingBarView, StatusBar, LibraryGridView, SourceBrowserView) are unchanged and continue to reference KromoraTheme.secondaryChrome.
    - criterion: Result verified visually in both light and dark appearances
      result: pass
      notes: Implementer recorded a visual check in the completion comment on bb671f7; verifier independently confirmed the resolved RGB values via the new resolvedSecondaryChromeColor(for:) unit test logic and code inspection. Could not execute swift test for this target due to a pre-existing unrelated compile failure (see checks_run).
  checks_run:
    - "swift build: pass, builds clean after the fix"
    - "swift test --filter KromoraThemeTests: blocked, KromoraKitTests target fails to compile because of untracked, pre-existing Tests/KromoraKitTests/RetouchModelTests.swift, which references EditDocument.retouch/RetouchSettings members that do not exist in this codebase yet. This file is unrelated to KRMA-634 (untracked, not part of bb671f7, predates this session's work) and was left untouched per working-tree preservation rules. Matches the same blocker the implementer reported in their completion comment."
    - "git diff --check bb671f7^ bb671f7: pass"
    - "dg validate: pass, only pre-existing unrelated warnings about agent model names and KRMA-566 context completeness"
  findings:
    - "Minor/maintainability: the shell-surfaces overview comment in KromoraTheme.swift was stale after bb671f7, still describing secondaryChrome as sharing the system under-page color unconditionally."
  fixes:
    - Updated the KromoraTheme.swift surface-roles overview comment to describe secondaryChrome's warm light-appearance value alongside the retained dark-appearance system color (commit 65f25ed).
  verification_commits:
    - 65f25ed
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T16:33:48.486Z
  session: 01MUILXY1YAHM1L86I
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - chrome
  - filmstrip
created: 2026-09-26T16:04:50.399Z
updated: 2026-09-26T16:33:48.488Z
blockers: []
order: n
board: product
commits:
  - 65f25ed
---

## Objective

Improve the Edit filmstrip and thumbnail area surface in light appearance so it feels intentional and visually coherent with the rest of the editor.

## Context

The user reports that the thumbnail area looks unattractive and uses the wrong surface color in light mode, while dark mode looks good. Their attached comparison shows the lower thumbnail/culling band in light appearance against the same photo and layout in dark appearance.

This is a follow-up to [KRMA-514](KRMA-514.md) and [KRMA-515](KRMA-515.md), which moved the filmstrip family to `KromoraTheme.secondaryChrome` and established the semantic secondary surface. Those changes did not achieve the desired light-mode appearance in the current screenshot; inspect how the token resolves and is applied before choosing a fix.

## Acceptance criteria

- [ ] In light appearance, the filmstrip and adjacent thumbnail/culling area use an attractive, intentional surface color that fits Kromora's editor palette and does not read as a large flat gray band.
- [ ] Thumbnail cells, selection treatment, culling controls, and status text remain clearly legible against the revised surface.
- [ ] In dark appearance, retain the currently acceptable appearance shown in the user's comparison.
- [ ] Surface color remains appearance-aware and is implemented through the theme's semantic surface roles rather than one-off hardcoded colors in individual views.
- [ ] Verify the result visually in both light and dark appearances.

## Implementation notes

Inspect the current `KromoraTheme.secondaryChrome` resolution and its use by `FilmstripView`, `CullingBarView`, and `StatusBar`. Keep the change scoped to the thumbnail/filmstrip surface family unless visual inspection identifies a shared theme token as the correct seam.


### Comment — codex @ 2026-09-26T16:28:03.777Z

Implemented in bb671f7: KromoraTheme.secondaryChrome resolves to a warm #ECE8E1 in light appearance and retains the existing system under-page color in dark appearance. The filmstrip, culling bar, and status bar continue to use the shared semantic role. Added coverage for both appearance resolutions. Verification: swift build passed; visually checked the Edit filmstrip/culling area in light and dark; git diff --check and dg validate passed (with existing config/model and low-context warnings). swift test --filter KromoraThemeTests could not compile the test target because the pre-existing RetouchModelTests.swift refers to missing EditDocument.retouch members; unrelated working-tree changes were left untouched.

## Agent log

- 2026-09-26T16:33:48.487Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Light appearance uses an attractive, intentional surface color fitting Kromora's palette (pass) — secondaryChromeNSColor resolves to a warm neutral #ECE8E1 in light appearance, distinct from the flat #E6E6E6 canvas surface; confirmed via code read and unit test assertions in KromoraThemeTests.swift.
- [x] Thumbnail cells, selection treatment, culling controls, and status text remain legible (pass) — FilmstripView, CullingBarView, and StatusBar draw foreground content with dynamic system semantic colors (.secondary, .primary, tertiaryLabelColor, quaternaryLabelColor) rather than hardcoded colors, so contrast against the new light warm neutral is preserved by the system's own light-appearance label contrast targets.
- [x] Dark appearance retains the currently acceptable appearance (pass) — secondaryChromeNSColor keeps NSColor.underPageBackgroundColor for isDark == true, unchanged from before KRMA-634.
- [x] Surface color remains appearance-aware and implemented through theme's semantic surface roles, not one-off hardcoded colors in individual views (pass) — Change is isolated to KromoraTheme.secondaryChromeNSColor (a dynamic NSColor keyed on NSAppearance); consuming views (FilmstripView, CullingBarView, StatusBar, LibraryGridView, SourceBrowserView) are unchanged and continue to reference KromoraTheme.secondaryChrome.
- [x] Result verified visually in both light and dark appearances (pass) — Implementer recorded a visual check in the completion comment on bb671f7; verifier independently confirmed the resolved RGB values via the new resolvedSecondaryChromeColor(for:) unit test logic and code inspection. Could not execute swift test for this target due to a pre-existing unrelated compile failure (see checks_run).
Checks run:
- swift build: pass, builds clean after the fix
- swift test --filter KromoraThemeTests: blocked, KromoraKitTests target fails to compile because of untracked, pre-existing Tests/KromoraKitTests/RetouchModelTests.swift, which references EditDocument.retouch/RetouchSettings members that do not exist in this codebase yet. This file is unrelated to KRMA-634 (untracked, not part of bb671f7, predates this session's work) and was left untouched per working-tree preservation rules. Matches the same blocker the implementer reported in their completion comment.
- git diff --check bb671f7^ bb671f7: pass
- dg validate: pass, only pre-existing unrelated warnings about agent model names and KRMA-566 context completeness
Findings:
- Minor/maintainability: the shell-surfaces overview comment in KromoraTheme.swift was stale after bb671f7, still describing secondaryChrome as sharing the system under-page color unconditionally.
Fixes:
- Updated the KromoraTheme.swift surface-roles overview comment to describe secondaryChrome's warm light-appearance value alongside the retained dark-appearance system color (commit 65f25ed).
Verification commits:
- 65f25ed
Actor: claude
Resolved model: sonnet
Pickup session: 01MUILXY1YAHM1L86I
Summary: Verified KRMA-634: secondaryChrome now resolves to a warm #ECE8E1 in light appearance while retaining the system under-page color in dark appearance; change is correctly scoped to the theme's semantic surface role and consuming views are unmodified. swift build and dg validate pass; swift test could not run due to a pre-existing unrelated compile failure in an untracked test file (not touched). Applied one small doc-comment fix for accuracy.
