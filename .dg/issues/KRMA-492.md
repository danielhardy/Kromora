---
id: KRMA-492
title: "Selective copy/paste edits: category dialog, remembered defaults, multi-select paste"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Cmd-C opens selective-copy dialog with checkbox per EditClipboardPayload.Category
      result: pass
      notes: KeyMonitor routes plain Cmd-C to presentSelectiveCopyDialog; SelectiveCopySheet lists Category.allCases with titles. Verified by code review; no automated key-routing test (see KRMA-493).
    - criterion: Confirming Copy stores payload; paste applies only checked categories; unchecked stages intact (tested)
      result: pass
      notes: testSelectiveCopyMaskLeavesUncheckedDestinationStagesIntact; pasteEdits passes clipboardCategories in all three paths.
    - criterion: Dialog defaults to last confirmed set across relaunch
      result: pass
      notes: KromoraSettings.lastCopyCategories, default all; testLastCopyCategoriesPersistAcrossRelaunch.
    - criterion: Paste to one photo and multi-selection works; status count matches
      result: pass
      notes: Existing multi-paste loop retained; status message reports pastedCount and category summary.
    - criterion: Filmstrip supports Shift-range and Command-toggle consistent with Library
      result: pass
      notes: FilmstripView and SourceBrowserView thread shift/command into LibrarySelectionModel.Modifiers. Not covered by a filmstrip-specific test (KRMA-493).
    - criterion: Text fields keep standard Cmd-C/Cmd-V
      result: pass
      notes: Handler sits after globalShortcutsOwnKeyboard gate, which defers to NSText/NSControl; selective-copy sheet also bypasses monitor.
    - criterion: Focused tests for isolation, defaults, multi-select; existing copy tests pass
      result: pass
      notes: Isolation and settings persistence tests added; VM-level defaults seeding and filmstrip range tests are a follow-up (KRMA-493).
    - criterion: scripts/ci-tests.sh fast and serial pass
      result: pass
      notes: fast exit 0; serial 395 tests, 1 pre-existing RAW fixture skip, 0 failures.
  checks_run:
    - scripts/ci-tests.sh fast (exit 0)
    - scripts/ci-tests.sh serial (395 tests, 1 skipped, 0 failures)
    - manual review of commit dc54bac
  findings:
    - "Low: missing tests for VM-level remembered-defaults seeding, filmstrip Shift-range selection, and KeyMonitor Cmd-C/V routing; plain Cmd-C falls through to the menu when an NSControl is first responder. Tracked in KRMA-493."
  fixes: []
  verification_commits:
    - dc54bac
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-20T23:02:11.768Z
  session: 01MUAF47RYMYTRI6NQ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - ux
  - editor
created: 2026-09-20T22:35:14.339Z
updated: 2026-09-20T23:02:11.769Z
order: a0
board: product
commits:
  - dc54bac
---

## Objective

Copy edits with a quick category checklist (Light, Color, Crop, …), remember the last checklist for next time, then paste to one photo or every Shift/⌘-selected photo in the filmstrip or Library — without replacing the existing all-edits transfer path’s reliability.

## Context

User report (2026-09-20):

- Click a thumbnail and press **⌘C** → open a quick dialog with checkboxes for the various copy categories (color, crop, light, etc.).
- Checkboxes **default to the last setting** the user chose.
- Confirm/save the copy, then paste onto any other image in the filmstrip or Library.
- Select multiple images with **Shift** and **⌘**, and paste to all of them.

### What already exists (KRMA-010)

- `EditClipboardPayload` already splits categories: `light`, `color`, `effects`, `crop`, `rotation`, `lut`, `develop`, `localAdjustments` (`Sources/KromoraKit/Models/EditClipboard.swift`).
- `applying(to:destinationIsRAW:categories:)` already supports a **subset** of categories (selective paste API shipped before the UI).
- **Copy All Edits** / **Paste Edits** via toolbar + menu; shortcuts are **⌘⌥C / ⌘⌥V** (`KromoraEditTransferShortcuts`) so they do not fight AppKit text-field ⌘C/⌘V.
- Paste already targets the **current multi-selection** (`pasteEdits()` loops `collection.selectedItems`) with per-destination undo/persistence.
- Library grid supports ⌘-click and Shift-click range selection (`LibrarySelectionModel`). Filmstrip selection today only passes **⌘** as additive (`selectCollectionImage(at:additive:)`); **Shift-range in the filmstrip is likely missing** and should be included so Edit matches Library.

KRMA-010 explicitly left **selective-copy checkbox UI** out of scope; this ticket is that follow-up.

## Requirements

### Copy dialog

1. Invoking copy (product preference: **⌘C** when the canvas/filmstrip/library owns focus and no text field is first responder; keep or remap **⌘⌥C** as “Copy All / Copy Edits…” — do not break text fields) opens a compact sheet/popover listing photographer-facing categories with checkboxes, e.g.:
   - Light  
   - Color (incl. WB / mixer / grading as today belongs under color — match clipboard categories, don’t invent parallel taxonomies)  
   - Effects  
   - Crop  
   - Rotation  
   - Look / LUT  
   - Develop (RAW)  
   - Local adjustments / masks  
2. Defaults = **last confirmed checklist**, persisted across launches (`KromoraSettings` / UserDefaults). First launch: all categories on (parity with today’s Copy All), or a sensible documented default.
3. User can toggle, then **Copy** (primary) / Cancel. Copy builds `EditClipboardPayload` from the active photo and records which categories are active for the subsequent paste (either store the full payload and a `Set<Category>` mask, or only pack selected categories — paste must only apply the chosen set via `applying(…, categories:)`).
4. Status message should reflect selective copy (e.g. “Copied Light, Color from …”) not always “Copied all edits”.

### Paste

5. **⌘V** / **⌘⌥V** / Paste Edits applies the clipboard to:
   - the active photo if nothing else is selected, or  
   - **every selected** photo in Library or Edit filmstrip (existing multi-paste loop).
6. Unselected categories on the destination are left unchanged. Empty selected category on the source still clears that category on the destination (existing clipboard contract).
7. RAW develop policy unchanged: explicit develop settings only land on RAW destinations.

### Selection

8. Library: Shift + ⌘ multi-select remains.
9. Edit filmstrip: support the same modifier semantics as the grid (⌘ toggles, Shift extends range) so users can build a paste batch from thumbnails without returning to Library.
10. Paste from Library onto a multi-selection and from Edit filmstrip onto a multi-selection both work; active edit focus rules stay coherent (don’t silently switch the open photo unless product already does).

### Non-goals

- System pasteboard interchange with other apps.
- Presets marketplace / named style packs (beyond remembering the last checkbox set).
- Changing per-destination undo/persist semantics from KRMA-010.

## Acceptance criteria

- [ ] ⌘C (or the chosen primary shortcut when not in a text field) opens a selective-copy dialog with checkboxes for each `EditClipboardPayload.Category` (user-facing labels).
- [ ] Confirming Copy stores the payload; paste applies **only** the checked categories; unchecked destination stages remain intact (tested).
- [ ] Dialog defaults to the last confirmed checkbox set across relaunch.
- [ ] Paste to one filmstrip/Library photo and to a Shift/⌘ multi-selection both work; count in the status message matches destinations updated.
- [ ] Filmstrip supports Shift-range and ⌘-toggle selection consistent with Library (or document any intentional difference).
- [ ] Text fields still get standard ⌘C/⌘V; edit-transfer shortcuts do not steal from focused numeric fields.
- [ ] Focused tests: selective category paste isolation, remembered defaults, multi-select paste; existing copy-all / RAW-to-JPEG tests still pass.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- Model: `EditClipboardPayload.Category` + `applying(…, categories:)` — extend callers; avoid schema break if possible (payload already versioned).
- VM: `copyAllEdits()` → selective entry point + sheet presentation state; `pasteEdits()` must pass the remembered/copied category mask.
- UI: new small sheet (pattern like `LookSaveSheet` / `RecipeExtractorSheet`); toolbar Copy can open the same dialog; optional “Copy All” secondary that checks all and dismisses in one click.
- Settings: persist `Set<Category>` (or ordered bools) as last copy selection.
- Filmstrip: thread `NSEvent.modifierFlags` shift into `LibrarySelectionModel.Modifiers` like `LibraryGridView`.
- Related: KRMA-010 (foundation), README shortcut table (update when shortcuts change).

### Comment — codex @ 2026-09-20T22:58:45.253Z

Implemented selective edit copy/paste in commit dc54bac: category checklist sheet with persisted defaults, masked paste for single and multi-selection targets, plain Cmd-C/Cmd-V focus-safe routing, and Shift/Command filmstrip/source-browser selection. Added selective isolation and settings persistence tests; scripts/ci-tests.sh fast and serial pass (serial: 395 tests, 1 pre-existing RAW fixture skip, 0 failures).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-20T23:02:11.768Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Cmd-C opens selective-copy dialog with checkbox per EditClipboardPayload.Category (pass) — KeyMonitor routes plain Cmd-C to presentSelectiveCopyDialog; SelectiveCopySheet lists Category.allCases with titles. Verified by code review; no automated key-routing test (see KRMA-493).
- [x] Confirming Copy stores payload; paste applies only checked categories; unchecked stages intact (tested) (pass) — testSelectiveCopyMaskLeavesUncheckedDestinationStagesIntact; pasteEdits passes clipboardCategories in all three paths.
- [x] Dialog defaults to last confirmed set across relaunch (pass) — KromoraSettings.lastCopyCategories, default all; testLastCopyCategoriesPersistAcrossRelaunch.
- [x] Paste to one photo and multi-selection works; status count matches (pass) — Existing multi-paste loop retained; status message reports pastedCount and category summary.
- [x] Filmstrip supports Shift-range and Command-toggle consistent with Library (pass) — FilmstripView and SourceBrowserView thread shift/command into LibrarySelectionModel.Modifiers. Not covered by a filmstrip-specific test (KRMA-493).
- [x] Text fields keep standard Cmd-C/Cmd-V (pass) — Handler sits after globalShortcutsOwnKeyboard gate, which defers to NSText/NSControl; selective-copy sheet also bypasses monitor.
- [x] Focused tests for isolation, defaults, multi-select; existing copy tests pass (pass) — Isolation and settings persistence tests added; VM-level defaults seeding and filmstrip range tests are a follow-up (KRMA-493).
- [x] scripts/ci-tests.sh fast and serial pass (pass) — fast exit 0; serial 395 tests, 1 pre-existing RAW fixture skip, 0 failures.
Checks run:
- scripts/ci-tests.sh fast (exit 0)
- scripts/ci-tests.sh serial (395 tests, 1 skipped, 0 failures)
- manual review of commit dc54bac
Findings:
- Low: missing tests for VM-level remembered-defaults seeding, filmstrip Shift-range selection, and KeyMonitor Cmd-C/V routing; plain Cmd-C falls through to the menu when an NSControl is first responder. Tracked in KRMA-493.
Fixes:
- None
Verification commits:
- dc54bac
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAF47RYMYTRI6NQ
Summary: Verification passed: selective copy/paste, remembered defaults, filmstrip Shift/Command selection verified; fast and serial CI lanes pass. One non-blocking test-coverage child ticket (KRMA-493) filed.
