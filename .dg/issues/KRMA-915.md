---
id: KRMA-915
title: Refine dark app chrome with a macOS-aligned frosted-glass palette
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The dark palette has a deliberate hierarchy across window/toolbar, navigation and library surfaces, inspector, canvas surround, filmstrip, and bottom chrome; adjacent planes are distinguishable without flat black or uniform gray.
      result: pass
      notes: "The dynamic graphite ladder is canvas #141414, secondary #222222, inspector #2A2A2A, and toolbar #323232; theme tests assert the ordering."
    - criterion: A selective dark frosted-glass treatment is evaluated for appropriate chrome using native material APIs while preserving contrast and photo/analysis clarity.
      result: pass
      notes: Large panes remain opaque for stable contrast; native regular material remains on the floating grid badge. The recorded 1200x800 review found the photo, histogram, and tone curve clear.
    - criterion: Library and Edit share surface roles and clear interactive states; the copper accent, analysis colors, and mask semantics remain readable and unchanged in meaning.
      result: pass
      notes: Theme roles are shared across Library/Edit; focused tests cover the ladder, copper contrast, and light labels. No render, analysis-series, or mask-overlay semantics changed.
    - criterion: System mode tracks macOS appearance, Always Dark applies consistently to main and Settings windows, and light appearance remains usable.
      result: pass
      notes: Appearance-controller tests pass; the recorded review checked system Light/Dark and Always Dark in the main and Settings windows, with light appearance and copper accent readable.
    - criterion: Text and controls remain readable at common sizes and accessibility settings using non-personal fixtures.
      result: pass
      notes: The issue records Library/Edit review at 1200x800 with bundled SamplePhotos, Reduce Transparency, and Increase Contrast. Human review explicitly waived exact 800x500 because this palette-only change does not alter layout.
    - criterion: Manual visual review records screens, appearances, material choice, and remaining limits without personal imagery.
      result: pass
      notes: The issue comments record the screens and appearances checked, the opaque-pane/floating-material choice, the 800x500 waiver, and that no screenshots or user photos were attached.
    - criterion: Focused theme/appearance tests, strict build, fast and serial lanes, dg validate, and git diff --check pass.
      result: pass
      notes: Strict build, focused tests (15), and serial lane (517) pass. The fast lane exits 1 only on the unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory baseline failure already documented in completed KRMA-894. dg validate passes with pre-existing model-name warnings; git diff --check passes.
  checks_run:
    - "swift build -Xswiftc -warnings-as-errors: pass"
    - "Focused theme, appearance-controller, and library-layout tests: pass (15 tests)"
    - "scripts/ci-tests.sh fast: exit 1; only CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failed, matching the unrelated baseline documented in KRMA-894"
    - "scripts/ci-tests.sh serial: pass (517 tests)"
    - "git diff --check: pass"
    - "dg validate: pass with existing model-name warnings"
  findings:
    - No issue-specific correctness, maintainability, security, or performance defect found.
    - The fast lane retains the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure already recorded in completed KRMA-894; no duplicate child ticket was created.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T00:39:55.519Z
  session: 01MV5Y58OFRFPCGFBM
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - ui
  - design
  - appearance
  - dark-mode
  - macos
created: 2026-10-12T22:04:51.809Z
updated: 2026-10-13T00:39:55.523Z
blockers:
  - id: evt_mv5vzqwo_v90thn
    type: human
    reason: The required manual visual review remains unverified. The production app entry point opens the normal user library, and this verification environment has no isolated package/profile configured; launching it could expose personal photos. The required review cannot be completed safely in this session.
    action: Run the manual visual review in an isolated disposable app profile/library using only generated or repository-provided non-personal imagery. Check Library and Edit at 800x500 and 1200x800 in system Light, system Dark, and Always Dark; check reduced-transparency and increased-contrast settings where available. Record the screens and appearances checked, surface/material choice, and remaining limits in the issue.
    created_at: 2026-10-12T23:32:09.336Z
    resolved_at: 2026-10-12T23:48:15.094Z
    resolved_by: web
  - id: evt_mv5x1zxa_vhtmo0
    type: human
    reason: Exact 800x500 Library and Edit visual review remains incomplete; the available native desktop controls could not resize the review window to that size.
    action: Using a disposable app profile and only bundled repository SamplePhotos, set the app window to exactly 800x500 and inspect Library and Edit in system Light, system Dark, and Always Dark. Check text, controls, copper accent, histogram/curve, and reduced-transparency or increased-contrast settings where available; record the screens, appearances, observations, and any limits in this issue. Do not open or attach user photos.
    created_at: 2026-10-13T00:01:53.950Z
    resolved_at: 2026-10-13T00:32:17.794Z
    resolved_by: cli
order: a0
board: product
blocked_reason: Exact 800x500 Library and Edit visual review remains incomplete; the available native desktop controls could not resize the review window to that size.
blocked_action: Using a disposable app profile and only bundled repository SamplePhotos, set the app window to exactly 800x500 and inspect Library and Edit in system Light, system Dark, and Always Dark. Check text, controls, copper accent, histogram/curve, and reduced-transparency or increased-contrast settings where available; record the screens, appearances, observations, and any limits in this issue. Do not open or attach user photos.
blocked_from_status: verification
context:
  files:
    - Sources/KromoraKit/Views/KromoraTheme.swift
    - Sources/KromoraKit/Models/KromoraWindowAppearanceController.swift
    - Sources/KromoraKit/Models/KromoraSettings.swift
    - Sources/KromoraKit/Views/ContentView.swift
    - Sources/KromoraKit/Views/SourceBrowserView.swift
    - Sources/KromoraKit/Views/LibraryFacetSidebar.swift
    - Sources/KromoraKit/Views/LibraryGridView.swift
    - Sources/KromoraKit/Views/InfoInspectorView.swift
    - Sources/KromoraKit/Views/FilmstripView.swift
    - Sources/KromoraKit/Views/StatusBar.swift
    - Sources/KromoraKit/Views/KromoraSettingsView.swift
    - Tests/KromoraKitTests/KromoraThemeTests.swift
    - Tests/KromoraKitTests/KromoraWindowAppearanceControllerTests.swift
    - Tests/KromoraKitTests/LibraryChromeLayoutTests.swift
  docs:
    - CLAUDE.md
    - .dg/AGENTS.md
    - docs/PRODUCT_SCOPE.md
    - docs/APP_ARCHITECTURE.md
  issues: []
  commands:
    - swift build -Xswiftc -warnings-as-errors
    - swift test --filter 'KromoraThemeTests|KromoraWindowAppearanceControllerTests|LibraryChromeLayoutTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - git diff --check
    - dg validate
---

## Objective

Refine Kromora's app-shell palette so its dark appearance feels grounded in macOS's layered graphite surfaces. Explore dark frosted glass as a unifying visual direction: deeper neutral planes, selective native translucency, restrained highlights, and clear control states. Keep the existing system-following appearance and Always Dark Mode behavior.

## Context

Kromora already has a dark appearance, a system/Always Dark Mode preference, and Tahoe Liquid Glass controls in its unified toolbar. The remaining visual impression is driven by the broader shell palette: large areas of chrome read as medium charcoal, and some adjacent roles share the same tone. The dark surfaces should frame the photograph more quietly and feel cohesive with current macOS dark UI, while preserving the clear hierarchy and legibility a photo editor needs.

At ticket creation, `KromoraTheme` resolves named dynamic colors for the window, toolbar, secondary chrome, inspector, canvas, and primary accent. Its dark values include approximately `#4A4A4A` for toolbar chrome, `#343434` for both secondary and inspector chrome, and `#262626` for the canvas; `ContentView` also applies `.regularMaterial` to the unified toolbar. Treat these values as a starting point for review, not a prescribed replacement palette. Inspect the actual running app and the full usage of these roles before changing them.

The requested design reference is macOS Dark Appearance's graphite surfaces and layered cards. The user also suggested dark frosted glass as a possible theme. Apply native material/translucency selectively to app chrome where it adds depth. Keep the effect subtle enough that controls, labels, and analysis remain easy to read. The photo remains the visual subject; shell materials must not obscure or alter the rendered photograph.

This is a product polish task for the Library and Edit shell: window/toolbar chrome, source/navigation areas, library surfaces, inspector, filmstrip, culling/status chrome, and custom popovers or sheets where they share the app theme. Keep surface roles coherent while allowing a recessed editor canvas and appropriately distinct selected, hover, and disabled states. Review how Kromora's copper primary accent and other existing state colors sit against the revised dark neutrals. Preserve the meaning and legibility of histogram/curve series and mask overlays.

Preserve macOS 26+ and Apple Silicon as the target, Swift 6, zero third-party dependencies, and the current `.system` / Always Dark Mode behavior. System mode must continue to follow macOS appearance changes; the app override must remain consistently dark across the main and Settings windows. Keep the current light appearance usable and visually intentional.

**Privacy for visual review:** The motivating user screenshots contain personal photo content. They are visual context only and must not be attached to this issue, copied into the repository, or reproduced in issue text. Do not record their paths, filenames, image pixels, metadata, or photo details. Use generated or repository-provided non-personal fixtures for any implementation screenshots or manual visual review.

## Acceptance criteria

- [ ] The dark palette has a deliberate hierarchy across window/toolbar, navigation and library surfaces, inspector, canvas surround, filmstrip, and bottom chrome. Adjacent large surfaces are distinguishable without turning the entire shell into flat black or uniformly gray fills.
- [ ] A selective dark frosted-glass treatment is evaluated for appropriate chrome surfaces using macOS-native material APIs. Translucency and blur feel restrained, preserve control/label contrast, and do not wash out the photo, histogram, curve, or other analysis content.
- [ ] Library and Edit use the same surface-role language, with clear interactive states and intentional treatment of Kromora's primary accent. Analysis series colors and mask-overlay semantics remain readable and unchanged in meaning.
- [ ] `.system` continues to track macOS Light and Dark appearances, and Always Dark Mode continues to apply consistently to the main and Settings windows. The existing light palette remains legible and intentional.
- [ ] Text and controls remain readable at common window sizes, including 800×500 and 1200×800, with the app in Library and Edit. Review dark appearance with representative generated/repository fixtures and check reduced-transparency or increased-contrast settings where available.
- [ ] Manual visual review records the screens and appearances checked, the chosen surface/material treatment, and any remaining limits. Review uses only generated or repository-provided non-personal imagery; no user-provided screenshot or photo is attached or reproduced.
- [ ] Focused theme/appearance tests, `swift build -Xswiftc -warnings-as-errors`, and the applicable fast and serial UI test lanes pass. `dg validate` and `git diff --check` pass.

## Implementation notes

Start with `KromoraTheme.swift` and follow each role through its consumers before adjusting colors. Consolidate repeated shell colors as semantic, appearance-aware roles instead of adding unrelated per-view literals. Check which surfaces should use opaque dynamic colors and which benefit from native dark material; apply glass where it improves depth and keeps interaction readable. Inspect the Tahoe toolbar and its existing glass grouping before revising it.

Keep `KromoraWindowAppearanceController` and the system/Always Dark Mode contract intact. Add or update focused color-resolution and appearance-propagation coverage in the existing theme/controller tests. Review the actual app in Library and Edit at the stated sizes, using non-personal fixtures. Do not change photo pixels, render output, analysis values, or the meaning of diagnostic colors as part of a chrome palette adjustment.

This issue captures a visual direction and implementation scope. It remains in backlog for product sequencing and is not authorization to start implementation or move the issue to Ready.

### Comment — claude @ 2026-10-12T22:27:33.086Z

Implemented dark graphite ladder in KromoraTheme (canvas #141414, secondary #222222, inspector #2A2A2A, toolbar #323232; light unchanged), plus ladder-order test. Material decision: large panes stay opaque for stable label/plot contrast; native materials remain on floating overlays only (toolbar has no scrolling content beneath, so blur would add nothing). Verified: swift build -warnings-as-errors, focused theme/appearance tests, serial lane (517 pass), git diff --check, dg validate (warnings only, pre-existing). NOT done: manual visual review at 800x500/1200x800, reduced-transparency/increased-contrast check (non-interactive session, no display). Fast lane has 1 failure, CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory (dust/undo, unrelated to theme; working tree also holds other uncommitted PreviewAdmission changes).

### Comment - human 

Dark colors look good 

### Comment — codex @ 2026-10-13T00:01:09.695Z

Counterpoint verification - 2026-10-12:

Visual review used an isolated disposable app profile and only the bundled repository SamplePhotos. At 1200x800, I checked Library and Edit in system Light, system Dark, and Always Dark; the Always Dark override was visible in both the main and Settings windows. I also checked Edit with Reduce Transparency enabled, then with Increase Contrast enabled, each independently while system Dark was active; both settings were restored to off. Text, controls, the copper accent, histogram, and tone curve remained readable at 1200x800, and the photo stayed visually clear.

Surface/material choice: the graphite surface ladder is opaque on large panes; existing regular material remains on the floating grid badge. No palette defect was found at 1200x800.

Checks: strict swift build -Xswiftc -warnings-as-errors passed; focused theme/appearance/layout tests passed (13); serial lane passed (517). The fast lane exited 1 on the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure, also documented in KRMA-894. The additional parallel-only StoredEditAdoption shutdown assertion passed when rerun serially. git diff --check passed; dg validate passed with the existing model-name warnings. No product source changes or verification commits were made.

Limit: I could not resize the app window to exactly 800x500 through the available native desktop controls, so Library and Edit at that size remain unreviewed. No screenshots were saved or attached, and no user photos were opened.

### Comment — human @ 2026-10-13T00:32:17.316Z

Human review: I opened the app and reviewed the dark palette in person; it looks great. The exact 800x500 check is waived. This change only alters colors, not layout, so a small-window size check adds no information. Remaining acceptance criteria are satisfied by the 1200x800 review recorded above.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-13T00:39:55.519Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The dark palette has a deliberate hierarchy across window/toolbar, navigation and library surfaces, inspector, canvas surround, filmstrip, and bottom chrome; adjacent planes are distinguishable without flat black or uniform gray. (pass) — The dynamic graphite ladder is canvas #141414, secondary #222222, inspector #2A2A2A, and toolbar #323232; theme tests assert the ordering.
- [x] A selective dark frosted-glass treatment is evaluated for appropriate chrome using native material APIs while preserving contrast and photo/analysis clarity. (pass) — Large panes remain opaque for stable contrast; native regular material remains on the floating grid badge. The recorded 1200x800 review found the photo, histogram, and tone curve clear.
- [x] Library and Edit share surface roles and clear interactive states; the copper accent, analysis colors, and mask semantics remain readable and unchanged in meaning. (pass) — Theme roles are shared across Library/Edit; focused tests cover the ladder, copper contrast, and light labels. No render, analysis-series, or mask-overlay semantics changed.
- [x] System mode tracks macOS appearance, Always Dark applies consistently to main and Settings windows, and light appearance remains usable. (pass) — Appearance-controller tests pass; the recorded review checked system Light/Dark and Always Dark in the main and Settings windows, with light appearance and copper accent readable.
- [x] Text and controls remain readable at common sizes and accessibility settings using non-personal fixtures. (pass) — The issue records Library/Edit review at 1200x800 with bundled SamplePhotos, Reduce Transparency, and Increase Contrast. Human review explicitly waived exact 800x500 because this palette-only change does not alter layout.
- [x] Manual visual review records screens, appearances, material choice, and remaining limits without personal imagery. (pass) — The issue comments record the screens and appearances checked, the opaque-pane/floating-material choice, the 800x500 waiver, and that no screenshots or user photos were attached.
- [x] Focused theme/appearance tests, strict build, fast and serial lanes, dg validate, and git diff --check pass. (pass) — Strict build, focused tests (15), and serial lane (517) pass. The fast lane exits 1 only on the unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory baseline failure already documented in completed KRMA-894. dg validate passes with pre-existing model-name warnings; git diff --check passes.
Checks run:
- swift build -Xswiftc -warnings-as-errors: pass
- Focused theme, appearance-controller, and library-layout tests: pass (15 tests)
- scripts/ci-tests.sh fast: exit 1; only CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failed, matching the unrelated baseline documented in KRMA-894
- scripts/ci-tests.sh serial: pass (517 tests)
- git diff --check: pass
- dg validate: pass with existing model-name warnings
Findings:
- No issue-specific correctness, maintainability, security, or performance defect found.
- The fast lane retains the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure already recorded in completed KRMA-894; no duplicate child ticket was created.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5Y58OFRFPCGFBM
Summary: Verified KRMA-915; focused and serial checks passed, with only the known unrelated fast-lane baseline failure.
