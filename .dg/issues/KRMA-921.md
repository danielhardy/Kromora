---
id: KRMA-921
title: "Spike: determine beep-free key handling mechanism (menu key equivalents vs onKeyPress vs key NSView)"
type: task
status: claimed
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - keyboard
  - spike
created: 2026-10-13T13:18:51.360Z
updated: 2026-10-13T13:21:28.079Z
blockers: []
order: a0
board: product
claim:
  actor: claude
  session: 01MV6PJ77LNSJCMLWQ
  claimed_at: 2026-10-13T13:19:05.793Z
  expires_at: 2026-10-13T14:19:05.793Z
---

## Objective

Establish, with a real `NSWindow` and real key events, which key-handling mechanism satisfies *both* "no system alert beep" and "text fields stay typeable", so KRMA-920 can commit to one design. Output is findings plus a reusable test seam, not production behavior.

## Context

Parent: KRMA-920 (replace the global `NSEvent` key monitor). That ticket's Layer B choice (SwiftUI `.onKeyPress` on a focusable surface vs. a custom key `NSView`) and the extent of menu key equivalents cannot be decided from reading code: `MenuCommands.swift` records that menu key equivalents are resolved before text-input focus policy, and `FilmstripView.swift` records that a focused `NSButton` beeped even after `.onKeyPress` returned `.handled`.

## Acceptance criteria

- [ ] A serial-lane test host (real `NSWindow` + SwiftUI hosting view, no display-bound capture) can post synthesized `keyDown`/`keyUp` events through `NSWindow.sendEvent` and report whether the event was claimed or reached the default `NSResponder.keyDown` (beep path). The seam is documented and reusable by KRMA-920's no-beep matrix.
- [ ] Findings recorded in this ticket's comment for each mechanism × first-responder state (surface, `NSSegmentedControl`, `NSPopUpButton`, `NSButton`, list, `TextField` field editor, `NSSlider`): (a) menu key equivalent, plain letter and Shift+letter, fires or not while a text field is editing; (b) disabled menu item swallows or beeps; (c) `.onKeyPress` `.handled` / `.ignored` beep behaviour; (d) custom key `NSView` first responder, including whether it keeps/regains focus after a toolbar click.
- [ ] A clear recommendation naming the Layer B candidate (and which keys, if any, may use menu key equivalents), with the evidence. If no candidate meets both criteria, say so and propose the narrowest fallback.
- [ ] Spike code that is not reusable test seam is not committed; `scripts/ci-tests.sh serial` still exits 0.

## Implementation notes

Keep it small: one test file under `Tests/KromoraKitTests/` plus, if reusable, a tiny helper. Prefer a window-independent display (do not require an unlocked display; `NSWindow` need not be ordered front visibly - verify `makeKeyAndOrderFront` is not required for `sendEvent` routing, otherwise use an offscreen window). Do not run capture benchmarks.

### Comment — claude @ 2026-10-13T13:21:28.078Z

Findings (real NSWindow + NSApp.sendEvent; beep path observed via NSWindow.noResponder(for: keyDown:), the AppKit hook that beeps by default). Test: KeyRoutingProbeTests (serial lane).
1. Bug reproduced: plain 'c' and arrows reach the beep path when NSButton / NSSegmentedControl / NSSlider is first responder and nothing claims them.
2. Plain-letter menu key equivalent = AppKit's last chance before the beep: fires from NSButton/NSSegmentedControl/NSSlider with no beep, does NOT fire while a text field is editing (c and Shift+A both typed normally), and a DISABLED item still swallows the key (no beep). This contradicts the stale comment in MenuCommands.swift (L17-20). NSPopUpButton type-select swallows letters itself (no beep).
3. Arrow menu key equivalents fire from every control including an editing NSTextField, so arrows cannot be menu-only (would steal caret movement).
4. SwiftUI .onKeyPress(phases: .all) on a focused surface: .handled = no beep, key-down and key-up both delivered; .ignored = beep. Only reaches keys while SwiftUI focus is on/under that surface; an NSControl first responder elsewhere still beeps (see 1).
5. A custom key NSView as first responder claims plain keys and arrows (no beep, no menu needed), but is not required for the bulk of the work.
Recommendation for KRMA-920:
- Layer A: plain letters/digits/brackets (c, v, i, q, g, e, b, l, r, p, x, u, 0-5, [ ]) and shifted/modified commands become Commands menu items with .keyboardShortcut (unmodified/shift). Delete/Return/Esc remain in Layer B.
- Layer B: focusable editor surface with .onKeyPress(phases: .all), always returning .handled for owned keys (arrows, Space hold, Esc ladder, Return, Delete, ⌘\ hold). Pure-click toolbar controls (workspace picker, culling menu) must refuse first responder (.focusable(false)) so arrows are not stranded on an NSControl; keep value-editing controls (slider/stepper/text) focusable.
- Residual risk: arrows with a toolbar NSControl focused in the real app (SwiftUI focus vs AppKit first responder). KRMA-920 must verify with the real-app focus path and, if needed, gate arrow menu equivalents on a text-input-active focused value as fallback.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
