---
id: KRMA-490
title: "Edit filmstrip chrome: hide key hints, compact filter bar, tighten bottom padding"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Edit with open collection: no keyboard-shortcut hint chips; status and Cancel affordances still work"
      result: pass
      notes: StatusBar gained showsKeyHints (default true); ContentView Edit branch passes false. Status/progress/Cancel code untouched.
    - criterion: Culling/filter bar visibly shorter/tighter; all controls still work
      result: pass
      notes: Vertical padding 7->4, small control size, tighter spacing, caption2 fonts; all controls and accessibility modifiers retained.
    - criterion: Less empty padding under filmstrip thumbs without clipping
      result: pass
      notes: Padding 8->4, frame 116->110. Cell height with names is about 101pt, fitting the 102pt inner height; tight but not clipped.
    - criterion: Keyboard shortcuts and menu commands unchanged
      result: pass
      notes: No changes to KeyboardShortcuts or menus; only on-screen hints gated.
    - criterion: Library grid unchanged or intentionally shared
      result: pass
      notes: LibraryGridView uses CullingBarView default isCompact=false; Library StatusBar keeps hints.
    - criterion: scripts/ci-tests.sh fast and serial pass
      result: pass
      notes: fast reached 1101/1101 with no failure output seen; serial 396 tests, 1 skipped (RAW fixture), 0 failures.
  checks_run:
    - git diff --check HEAD~1 HEAD
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
  findings:
    - "info: Filmstrip height 110 leaves about 1pt slack when photo names are shown; larger fonts could clip and no layout test covers it. Non-blocking."
    - "info: Hiding hints removes on-screen discoverability of Look audition (up/down arrows) in Edit; per ticket requirements."
  fixes: []
  verification_commits:
    - 18dd515
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-20T23:21:16.296Z
  session: 01MUAFUBAIXB7EGPEP
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - ux
  - library
created: 2026-09-20T22:28:19.129Z
updated: 2026-09-20T23:21:16.298Z
order: a0
board: product
commits:
  - 18dd515
---

## Objective

In Edit view, tighten the bottom chrome under the photo: hide the keyboard-shortcut hint strip, make the culling/filter bar more compact, and reduce empty space below the filmstrip thumbnails — without changing any culling, filter, selection, or shortcut **behaviour**.

## Context

User report (2026-09-20): when in Edit, the thumbnail carousel area does not need to show the keyboard shortcuts (bottom); make the filter bar smaller; reduce the padding between the bottom of the thumbnail and the bottom of the screen. Functionality stays as today — visual cleanup only.

Edit layout today (`ContentView.detailContent` when a collection is active and crop is off):

1. `PreviewView`
2. `CullingBarView` — pick/reject/stars + `LibraryFilterControls` (“Filter” label, flag/rating pickers, count)
3. `FilmstripView` — fixed `.frame(height: 116)`, inner `.padding(.vertical, 8)` around 72×72 thumbs
4. `StatusBar` — status text on the left; **KeyHint** row on the trailing side (`G/E`, `←→`, `P/X`, `0–5`, comparison, `⌘S`, …)

The KeyHint strip is documentation chrome, not required once the culling bar and menus expose the same actions. Filmstrip + status padding stacks into noticeable empty space under the thumbs.

## Requirements

**Edit view only** (Library grid may keep current spacing unless a shared compact style is clearly better; default to Edit-scoped or a density parameter so Library does not regress accidentally).

1. **Hide keyboard shortcut hints** in Edit’s bottom chrome. Remove or gate the `StatusBar` `KeyHint` cluster while in Edit (navigation mode `.edit` / non-grid). Status / progress / Cancel for import, export, and Auto must remain. Keyboard shortcuts themselves (`KeyboardShortcuts`, menus) stay fully active — only the on-screen reminder goes away. Prefer hiding in Edit rather than deleting `KeyHint` forever unless product wants them gone everywhere.

2. **Compact the filter / culling bar** (`CullingBarView`). Reduce vertical padding (currently `.padding(.vertical, 7)`), control size (e.g. `.controlSize(.small)` on bordered pick/reject and menu pickers), spacing, and optionally drop or shrink the literal “Filter” label so the row is shorter and quieter. Pick, Reject, stars, flag filter, rating filter, count, and Clear must all remain and behave the same.

3. **Tighten space under thumbnails.** Reduce `FilmstripView` vertical padding and/or the hard-coded `116` height in `ContentView` so the gap between the bottom of the thumb (and name caption if shown) and the window bottom / status bar is smaller. Do not clip thumbs, selection rings, reject overlays, or name labels (`settings.showPhotoNames`). Status bar can stay; if hiding KeyHints already shortens it, account for that in the filmstrip height.

4. **No behaviour changes.** Same selection, additive ⌘-click, arrow navigation, filters, ratings, flags, thumbnail demand priorities, and accessibility labels/values. This is density / chrome only.

## Acceptance criteria

- [ ] In Edit with an open collection: no keyboard-shortcut hint chips (G/E, P/X, 0–5, etc.) in the bottom bar; status and in-progress Cancel affordances still work.
- [ ] Culling/filter bar is visibly shorter / tighter than today; all controls still work.
- [ ] Noticeably less empty padding under filmstrip thumbnails without clipping content.
- [ ] Keyboard shortcuts and menu commands unchanged.
- [ ] Library grid either unchanged or intentionally sharing the compact bar with a note in the ticket; no accidental loss of filter/culling there.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass (no new flaky layout tests required; optional snapshot or frame-height assertion if cheap).

## Implementation notes

- `Sources/KromoraKit/Views/StatusBar.swift` — KeyHint `HStack`; gate with navigation mode or an `showsKeyHints` parameter from `ContentView`.
- `Sources/KromoraKit/Views/CullingBarView.swift` — padding / controlSize / Filter label.
- `Sources/KromoraKit/Views/FilmstripView.swift` + `ContentView` `.frame(height: 116)` — coordinate height with thumb size (72) + name line + padding.
- Related: KRMA-471 hid filmstrip in crop; this is Edit chrome density only.

### Comment — codex @ 2026-09-20T23:18:59.928Z

Implemented Edit-only bottom chrome density cleanup in commit 18dd515: StatusBar key hints are gated off in Edit while status/progress/Cancel remain; CullingBarView gets an explicit compact style used only by Edit; filmstrip padding is reduced from 8 to 4 and its Edit frame from 116 to 110 without changing interaction or accessibility code. Verification: swift build passed; scripts/ci-tests.sh fast passed 1101/1101; serial passed 396/396 with one expected RAW-fixture skip; git diff --check passed. Library keeps the default culling density.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-20T23:21:16.296Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Edit with open collection: no keyboard-shortcut hint chips; status and Cancel affordances still work (pass) — StatusBar gained showsKeyHints (default true); ContentView Edit branch passes false. Status/progress/Cancel code untouched.
- [x] Culling/filter bar visibly shorter/tighter; all controls still work (pass) — Vertical padding 7->4, small control size, tighter spacing, caption2 fonts; all controls and accessibility modifiers retained.
- [x] Less empty padding under filmstrip thumbs without clipping (pass) — Padding 8->4, frame 116->110. Cell height with names is about 101pt, fitting the 102pt inner height; tight but not clipped.
- [x] Keyboard shortcuts and menu commands unchanged (pass) — No changes to KeyboardShortcuts or menus; only on-screen hints gated.
- [x] Library grid unchanged or intentionally shared (pass) — LibraryGridView uses CullingBarView default isCompact=false; Library StatusBar keeps hints.
- [x] scripts/ci-tests.sh fast and serial pass (pass) — fast reached 1101/1101 with no failure output seen; serial 396 tests, 1 skipped (RAW fixture), 0 failures.
Checks run:
- git diff --check HEAD~1 HEAD
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
Findings:
- info: Filmstrip height 110 leaves about 1pt slack when photo names are shown; larger fonts could clip and no layout test covers it. Non-blocking.
- info: Hiding hints removes on-screen discoverability of Look audition (up/down arrows) in Edit; per ticket requirements.
Fixes:
- None
Verification commits:
- 18dd515
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAFUBAIXB7EGPEP
Summary: Verified: Edit-only chrome density change is correct and behaviour-neutral; build and fast/serial lanes pass.
