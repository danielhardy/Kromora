---
id: KRMA-497
title: "Toolbar: remove Copy/Paste and Export Selected; menu Export Originals"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Toolbar no longer shows Copy Edits, Paste Edits, or Export Selected / bulk-export icon
      result: pass
      notes: Blocks removed from ContentView.toolbarContent; contract test asserts absence.
    - criterion: File menu offers Export Originals... (Cmd-Shift-E) that still exports the current selection via the existing batch path
      result: pass
      notes: Button posts .exportSelected, which still routes to exportSelectedDialog(); shortcut unchanged.
    - criterion: Copy/Paste remain available from the menu and shortcuts; selective copy sheet still works
      result: pass
      notes: Edit menu Copy Edits…, Copy All Edits, Paste Edits intact; Cmd-C/Cmd-V key monitor path unchanged.
    - criterion: Single Export (Cmd-S) still works from toolbar and/or menu
      result: pass
      notes: Toolbar Export button and File > Export… untouched.
    - criterion: scripts/ci-tests.sh fast and serial pass; menu tests updated
      result: pass
      notes: Implementer reported fast 1106 passed and serial 403 passed (1 pre-existing RAW-fixture skip). Verifier re-ran MenuCommandTests (8/8) after the comment fix; did not re-run the full lanes since the only verifier change is a comment.
  checks_run:
    - git show a0d8893 diff review
    - grep for stale Export Selected/Copy Edits/Paste Edits references in README, docs, Sources
    - swift test --filter MenuCommandTests (8 tests, 0 failures)
  findings:
    - "[low] Comment in KeyboardShortcuts.swift still referred to a Copy Edits… toolbar button that no longer exists. (fixed)"
    - "[info] Menu/toolbar contract tests assert on source-file strings, which is brittle to reformatting but consistent with existing tests in MenuCommandTests."
  fixes:
    - Updated the stale comment in Sources/KromoraKit/Views/KeyboardShortcuts.swift to point at the Edit menu action (comment-only).
  verification_commits:
    - b756865
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T01:36:32.967Z
  session: 01MUAKPYVWWECQQECK
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - ux
  - toolbar
created: 2026-09-21T01:31:14.155Z
updated: 2026-09-21T01:36:32.969Z
order: a0
board: product
commits:
  - b756865
---

## Objective

Declutter the Edit window toolbar: remove the Copy Edits and Paste Edits icons, and remove the bulk-export toolbar control. Expose bulk export from the File menu as **Export Originals** (same behaviour as today’s Export Selected).

## Context

User report (2026-09-20):

- Remove the copy / paste icons from the top bar.
- Add “Export Originals” to the menu and remove the toolbar icon.

Today (`ContentView.toolbarContent`):

- **Copy Edits…** / **Paste Edits** toolbar buttons (menu already has Copy Edits…, Copy All Edits, Paste Edits — KRMA-492).
- **Export** (active photo, ⌘S) and **Export Selected** (`square.and.arrow.up.on.square`, ⌘⇧E) when a collection is active.
- File menu already has `Export Selected...` → `exportSelectedDialog()` (batch export of the selection from originals + saved edits).

Product intent: copy/paste and bulk export are menu/shortcut actions, not always-on toolbar chrome. Rename the menu item to **Export Originals** to match how users talk about exporting the selected library files (keep wiring to the existing selected-batch export unless product later splits “unedited originals only”).

## Requirements

1. **Remove** toolbar buttons for Copy Edits and Paste Edits. Keep File-menu Copy Edits… / Copy All / Paste and existing shortcuts (⌘C selective dialog, ⌘⌥C/⌘⌥V as today).
2. **Remove** the toolbar **Export Selected** control.
3. File menu: rename **Export Selected...** → **Export Originals...** (or add that title as the primary label). Same action, shortcut ⌘⇧E, same `exportSelectedDialog` / batch path. Help text can stay accurate about applying saved edits if that is still what the exporter does.
4. Keep the single-photo **Export** toolbar button and File ▸ Export… (⌘S) unless a follow-up asks to demote that too.
5. Update README / shortcut docs if they mention toolbar copy-paste or “Export Selected” by name.
6. No change to copy/paste semantics or export pixel pipeline — chrome and naming only.

## Acceptance criteria

- [ ] Toolbar no longer shows Copy Edits, Paste Edits, or Export Selected / bulk-export icon.
- [ ] File menu offers **Export Originals...** (⌘⇧E) that still exports the current selection via the existing batch path.
- [ ] Copy/Paste remain available from the menu (and shortcuts); selective copy sheet still works.
- [ ] Single Export (⌘S) still works from toolbar and/or menu.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass; menu/command tests updated for the new title if they assert the old string.

## Implementation notes

- `Sources/KromoraKit/Views/ContentView.swift` — toolbar edit-transfer + export-selected blocks.
- `Sources/KromoraKit/Views/MenuCommands.swift` — rename Export Selected button label.
- Related: KRMA-492 (selective copy), KRMA-489 (crop toolbar chrome).

### Comment — codex @ 2026-09-21T01:35:35.803Z

Implemented in a0d8893: removed Copy Edits, Paste Edits, and bulk Export Selected from the edit toolbar; renamed the File-menu action to Export Originals... while preserving exportSelectedDialog() and ⌘⇧E; added menu/toolbar contract tests. Verified scripts/ci-tests.sh fast (1106 passed) and serial (403 passed, 1 pre-existing RAW-fixture skip).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T01:36:32.967Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Toolbar no longer shows Copy Edits, Paste Edits, or Export Selected / bulk-export icon (pass) — Blocks removed from ContentView.toolbarContent; contract test asserts absence.
- [x] File menu offers Export Originals... (Cmd-Shift-E) that still exports the current selection via the existing batch path (pass) — Button posts .exportSelected, which still routes to exportSelectedDialog(); shortcut unchanged.
- [x] Copy/Paste remain available from the menu and shortcuts; selective copy sheet still works (pass) — Edit menu Copy Edits…, Copy All Edits, Paste Edits intact; Cmd-C/Cmd-V key monitor path unchanged.
- [x] Single Export (Cmd-S) still works from toolbar and/or menu (pass) — Toolbar Export button and File > Export… untouched.
- [x] scripts/ci-tests.sh fast and serial pass; menu tests updated (pass) — Implementer reported fast 1106 passed and serial 403 passed (1 pre-existing RAW-fixture skip). Verifier re-ran MenuCommandTests (8/8) after the comment fix; did not re-run the full lanes since the only verifier change is a comment.
Checks run:
- git show a0d8893 diff review
- grep for stale Export Selected/Copy Edits/Paste Edits references in README, docs, Sources
- swift test --filter MenuCommandTests (8 tests, 0 failures)
Findings:
- [low] Comment in KeyboardShortcuts.swift still referred to a Copy Edits… toolbar button that no longer exists. (fixed)
- [info] Menu/toolbar contract tests assert on source-file strings, which is brittle to reformatting but consistent with existing tests in MenuCommandTests.
Fixes:
- Updated the stale comment in Sources/KromoraKit/Views/KeyboardShortcuts.swift to point at the Edit menu action (comment-only).
Verification commits:
- b756865
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAKPYVWWECQQECK
Summary: Verified: toolbar declutter and Export Originals rename correct; fixed one stale comment.
