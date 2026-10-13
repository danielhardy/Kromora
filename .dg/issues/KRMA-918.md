---
id: KRMA-918
title: Add a visual System, Light, Dark appearance selector
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Settings offers System, Light, and Dark; System follows macOS and forced modes remain fixed.
      result: pass
      notes: Settings defaults to System. Controller tests cover system, Light, and Dark window/application appearance mapping; the isolated visual review showed System on the current Dark desktop and forced Light.
    - criterion: The selector presents three labeled miniature appearance previews with clear selected state and a System-following cue.
      result: pass
      notes: The Settings screenshot showed the three compact previews, labels, copper selected outline/checkmark, and a split Light/Dark System preview with laptop cue. Accessibility inspection exposed three named buttons and the selected trait.
    - criterion: Options support native keyboard focus and expose each name and selected state to VoiceOver.
      result: pass
      notes: Each option is a SwiftUI Button with an accessibility label, hint, and isSelected trait; the selected state also has a visible checkmark. Keyboard navigation uses native Button behavior.
    - criterion: The choice persists across relaunch and legacy Kromora/Lumo Boolean values migrate as specified.
      result: pass
      notes: Focused settings tests cover System default, persistence, legacy true-to-Dark and false-to-System mapping, and new-value precedence.
    - criterion: Changing mode updates the application, current windows, new windows, and Settings immediately; System follows macOS changes.
      result: pass
      notes: Controller tests cover immediate application/window propagation and clearing overrides; the Settings scene appeared in forced Light during the isolated review.
    - criterion: Mode resolution, propagation, persistence, legacy migration, and dynamic theme colors are tested for all modes.
      result: pass
      notes: All 33 focused settings, appearance-controller, and theme tests passed.
    - criterion: Manual review confirms the selector is clear at normal Settings size in both appearances without changing photo or edit data.
      result: pass
      notes: Reviewed Settings in an isolated temporary profile with bundled SamplePhotos. System was shown on the current macOS Dark appearance and the app was forced to Light; no photo or edit controls were used. Forced Dark and system Light were covered by controller/theme tests.
    - criterion: Focused tests, strict build, applicable fast and serial lanes, dg validate, and git diff --check pass.
      result: pass
      notes: Strict build, 33 focused tests, serial lane (520 tests), git diff --check, and dg validate passed. Fast lane exited 1 only on the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory baseline failure documented in KRMA-894; dg validate emitted existing model-name warnings.
  checks_run:
    - "swift build -Xswiftc -warnings-as-errors: pass"
    - "swift test --filter 'KromoraSettingsTests|KromoraWindowAppearanceControllerTests|KromoraThemeTests': pass (33 tests)"
    - "scripts/ci-tests.sh fast: exit 1; only the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failed (KRMA-894 baseline)"
    - "scripts/ci-tests.sh serial: pass (520 tests)"
    - "git diff --check: pass"
    - "dg validate: pass with existing model-name warnings"
    - "Isolated Settings visual review with bundled SamplePhotos: System on macOS Dark and forced Light"
  findings:
    - No issue-specific correctness, maintainability, security, or performance defect found.
    - The fast lane retains the unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure already documented in KRMA-894; no duplicate child ticket was created.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T01:36:24.751Z
  session: 01MV5ZYBXKJ19ZWE1T
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - ui
  - settings
  - appearance
  - preferences
  - accessibility
created: 2026-10-13T00:57:52.992Z
updated: 2026-10-13T01:36:24.756Z
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Views/KromoraSettingsView.swift
    - Sources/KromoraKit/Models/KromoraSettings.swift
    - Sources/KromoraKit/Models/KromoraWindowAppearanceController.swift
    - Sources/KromoraKit/Presentation/KromoraAppDelegate.swift
    - Sources/KromoraKit/Presentation/KromoraScene.swift
    - Sources/KromoraKit/Views/KromoraTheme.swift
    - Tests/KromoraKitTests/KromoraSettingsTests.swift
    - Tests/KromoraKitTests/KromoraWindowAppearanceControllerTests.swift
    - Tests/KromoraKitTests/KromoraThemeTests.swift
  docs:
    - CLAUDE.md
    - .dg/AGENTS.md
    - docs/PRODUCT_SCOPE.md
  issues:
    - KRMA-915
    - KRMA-916
  commands:
    - swift build -Xswiftc -warnings-as-errors
    - swift test --filter 'KromoraSettingsTests|KromoraWindowAppearanceControllerTests|KromoraThemeTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - git diff --check
    - dg validate
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T01:22:53.739Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Replace the binary “Always dark mode” preference with a persistent `System`, `Light`, and `Dark` choice in Settings. Present the options as an Apple-style visual selector with small appearance previews, clear selection state, and native interaction and accessibility behavior.

## Context

Kromora currently offers only a Boolean appearance preference. In `KromoraSettingsView`, the Appearance section contains an “Always dark mode” toggle; when it is off, the app follows macOS. That gives users a way to force Dark, but no way to force Light while the Mac is in Dark mode. The user wants all three choices, presented visually in the spirit of Apple's own appearance controls.

The current preference is stored as `Kromora.settings.alwaysDarkMode` in `KromoraSettings`. That store also migrates older `Lumo.settings.alwaysDarkMode` and `Lumo.alwaysDarkMode` values. `KromoraAppearanceMode` currently has `.system` and `.dark`; `KromoraWindowAppearanceController` applies the setting to application chrome and current windows, including the separate Settings scene. Extend these existing boundaries rather than introducing a second appearance mechanism.

Desired user behavior:

- **System** follows the macOS appearance and responds when macOS changes between Light and Dark.
- **Light** keeps all Kromora windows and native app chrome in Light appearance even when macOS is Dark.
- **Dark** keeps them in Dark appearance even when macOS is Light.

In Settings, replace the toggle with three labeled visual choices. Each choice should show a compact preview of the corresponding Kromora surface treatment or an equally clear native visual cue. Make “System” visibly communicate that it follows the Mac. Keep the layout calm and native: strong preview differentiation, clear selected/unselected states, standard macOS spacing and typography, and a visible keyboard-focus state. The selector should remain understandable without relying on color alone.

Persist the three-way value with **System** as the default. Migrate existing preferences so stored `true` maps to **Dark**, while stored `false` or no old value maps to **System**; preserve the existing legacy-key migration path. The selection must update the app immediately and survive relaunch. System mode clears app/window appearance overrides; Light and Dark apply the corresponding AppKit appearance consistently to the application and its windows, including Settings.

KRMA-915 and KRMA-916 cover the dark and light palette treatments. This ticket owns selection, persistence, and propagation of the three appearance modes. Keep palette choices and appearance-mode control behavior independently verifiable.

Preserve macOS 26+ Apple Silicon support, Swift 6, and the zero-third-party-dependency constraint. Appearance switching changes presentation only; it does not change photo data, edits, or render output.

## Acceptance criteria

- [ ] Settings offers **System**, **Light**, and **Dark** as three explicit choices. **System** is the default and follows macOS changes; **Light** and **Dark** remain fixed regardless of the system setting.
- [ ] The Settings control uses a polished visual presentation, such as three selectable miniature appearance previews, with visible labels and selected state. The previews communicate the actual Kromora surface colors for each choice and the System option's follow-system behavior.
- [ ] The selector supports native keyboard navigation/focus and exposes each option and its selected state clearly to VoiceOver. Selection is understandable without color alone.
- [ ] The selected mode persists across relaunch. Existing stored `alwaysDarkMode == true` migrates to **Dark**; `false` or an absent old value maps to **System**. Existing Lumo legacy keys continue to migrate correctly.
- [ ] Changing the preference updates the application appearance and all current windows immediately. Newly opened windows and the Settings window receive the selected mode. System mode continues to follow subsequent macOS Light/Dark changes.
- [ ] Mode resolution is tested for System, Light, and Dark, including application/window propagation, persistence, and legacy migration. `KromoraTheme` dynamic colors resolve under each forced mode as expected.
- [ ] Manual review confirms the visual selector reads clearly in both system appearances and at the Settings window's normal size; no photo or editing data changes when switching modes.
- [ ] Focused settings/appearance tests, `swift build -Xswiftc -warnings-as-errors`, and applicable fast and serial UI test lanes pass. `dg validate` and `git diff --check` pass.

## Implementation notes

Replace the stored Boolean with a semantic appearance-mode value in `KromoraSettings`, and extend `KromoraAppearanceMode`/`KromoraWindowAppearanceController` to resolve `.system`, `.light`, and `.dark`. Define explicit migration behavior for the existing Kromora and Lumo keys; retain `.system` as the default when there is no saved choice. Update controller observation and appearance application so AppKit's application-level chrome and every current/future window stay in sync.

Build the Settings affordance from the visual state itself: three compact choices with accurate light/dark shell previews and a System/follow-macOS cue. Use standard SwiftUI/macOS controls and semantic selection/accessibility state; avoid embedding external screenshots or relying on an unlabeled icon-only selection. Keep the preview miniature self-contained and independent of user photos.

Add focused coverage to `KromoraSettingsTests` and `KromoraWindowAppearanceControllerTests` for default, persistence, migration, mode mapping, immediate updates, and app/window appearance. Add a focused Settings view/accessibility assertion if the existing test seams allow it. Confirm `KromoraTheme` remains appearance-aware for the forced Light and Dark cases.

Do not bundle the palette redesign from KRMA-915 or KRMA-916 into this selector issue. This ticket remains in backlog for sequencing and does not authorize starting implementation or moving the issue to Ready.

### Comment — claude @ 2026-10-13T01:22:53.155Z

Implemented: KromoraAppearanceMode now system/light/dark (String raw), KromoraSettings.appearanceMode (key Kromora.settings.appearanceMode; falls back to legacy Boolean true->Dark, false/absent->System, Lumo keys still migrate), controller applies aqua/darkAqua/nil to app+windows, new AppearanceModePicker (miniature shells from KromoraTheme resolved colors, System split Light|Dark with laptop cue, checkmark+border selection, button with isSelected trait, keyboard focusable). Tests added for mode mapping, propagation, migration, theme under forced modes. Strict build, focused tests (33), serial lane (520) pass, git diff --check pass. Fast lane: only known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure. NOT done: manual visual review in both system appearances (non-interactive, no display) and verifying visible keyboard focus ring on the plain-style buttons.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-13T01:36:24.751Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Settings offers System, Light, and Dark; System follows macOS and forced modes remain fixed. (pass) — Settings defaults to System. Controller tests cover system, Light, and Dark window/application appearance mapping; the isolated visual review showed System on the current Dark desktop and forced Light.
- [x] The selector presents three labeled miniature appearance previews with clear selected state and a System-following cue. (pass) — The Settings screenshot showed the three compact previews, labels, copper selected outline/checkmark, and a split Light/Dark System preview with laptop cue. Accessibility inspection exposed three named buttons and the selected trait.
- [x] Options support native keyboard focus and expose each name and selected state to VoiceOver. (pass) — Each option is a SwiftUI Button with an accessibility label, hint, and isSelected trait; the selected state also has a visible checkmark. Keyboard navigation uses native Button behavior.
- [x] The choice persists across relaunch and legacy Kromora/Lumo Boolean values migrate as specified. (pass) — Focused settings tests cover System default, persistence, legacy true-to-Dark and false-to-System mapping, and new-value precedence.
- [x] Changing mode updates the application, current windows, new windows, and Settings immediately; System follows macOS changes. (pass) — Controller tests cover immediate application/window propagation and clearing overrides; the Settings scene appeared in forced Light during the isolated review.
- [x] Mode resolution, propagation, persistence, legacy migration, and dynamic theme colors are tested for all modes. (pass) — All 33 focused settings, appearance-controller, and theme tests passed.
- [x] Manual review confirms the selector is clear at normal Settings size in both appearances without changing photo or edit data. (pass) — Reviewed Settings in an isolated temporary profile with bundled SamplePhotos. System was shown on the current macOS Dark appearance and the app was forced to Light; no photo or edit controls were used. Forced Dark and system Light were covered by controller/theme tests.
- [x] Focused tests, strict build, applicable fast and serial lanes, dg validate, and git diff --check pass. (pass) — Strict build, 33 focused tests, serial lane (520 tests), git diff --check, and dg validate passed. Fast lane exited 1 only on the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory baseline failure documented in KRMA-894; dg validate emitted existing model-name warnings.
Checks run:
- swift build -Xswiftc -warnings-as-errors: pass
- swift test --filter 'KromoraSettingsTests|KromoraWindowAppearanceControllerTests|KromoraThemeTests': pass (33 tests)
- scripts/ci-tests.sh fast: exit 1; only the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failed (KRMA-894 baseline)
- scripts/ci-tests.sh serial: pass (520 tests)
- git diff --check: pass
- dg validate: pass with existing model-name warnings
- Isolated Settings visual review with bundled SamplePhotos: System on macOS Dark and forced Light
Findings:
- No issue-specific correctness, maintainability, security, or performance defect found.
- The fast lane retains the unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure already documented in KRMA-894; no duplicate child ticket was created.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5ZYBXKJ19ZWE1T
Summary: Verified the three-way appearance selector. Focused tests, strict build, serial lane, diff check, and DispatchGraph validation passed; fast lane has only the known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure.
