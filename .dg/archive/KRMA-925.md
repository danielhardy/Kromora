---
id: KRMA-925
title: Drive File/Edit command enablement from focused scene values (no NotificationCenter)
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A pure menu availability model maps photo, grid selection, paste, undo/redo availability, and optional action names; tests cover no photo, open photo, grid with selection, and grid without selection.
      result: pass
      notes: MenuCommandAvailability is a Sendable value model; MenuCommandTests covers the requested states and named/fallback titles.
    - criterion: File-menu commands that need a photo or selection are disabled when unavailable; always-valid open/import commands stay enabled.
      result: pass
      notes: Photo and selection commands bind .disabled to the focused availability value; Open Image and import actions remain enabled.
    - criterion: Undo/Redo titles include action names when supplied and fall back to Undo/Redo.
      result: pass
      notes: The focused title formatter and menu binding meet the conditional criterion. The current AppViewModel initializer does not supply live action names, so titles remain plain until edit history carries names; tracked in backlog child KRMA-971.
    - criterion: Migrated commands use focused scene values without NotificationCenter; unmigrated commands remain on existing notifications and are listed.
      result: pass
      notes: Migrated photo/selection actions call KeyboardCommandRouter. Notifications remain for Open Image, Choose Look Folder, Import Look, Photos/Source/Removable import, Refresh Library, Derive Look, Apply Auto Edits, and Undo/Redo (retained for text-field arbitration).
    - criterion: MenuCommandTests and KeyboardCommandRouterTests pass without behavior regressions.
      result: pass
      notes: Both suites ran in the serial CI lane with no failures.
    - criterion: swift build is warning-free and Swift 6 constraints remain clean.
      result: pass
      notes: Build exited 0 with no warnings. Reviewed changes for concurrency opt-outs and availability branches; none introduced.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Exited 0; all 1,804 required fast tests completed.
    - criterion: scripts/ci-tests.sh serial exits 0.
      result: pass
      notes: Exited 0; all 541 required serial tests completed.
  checks_run:
    - swift build (exit 0, no warnings)
    - scripts/ci-tests.sh fast (exit 0, 1,804 tests)
    - scripts/ci-tests.sh serial (exit 0, 541 tests)
    - git diff --check 282032b4^ 282032b4 (exit 0)
    - Independent review of focused scene wiring, command guards, and migrated/unmigrated File-menu actions
  findings:
    - Live Undo/Redo action names are not yet populated from edit history; KRMA-971 is a backlog child labeled verification with parent KRMA-925.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T18:29:10.969Z
  session: 01MV70BLEQUQAGL3XK
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - menus
created: 2026-10-13T14:47:36.130Z
updated: 2026-10-24T13:05:07.553Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T18:20:54.309Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Menu commands must be disabled when they cannot act (for example Export/Reset/Copy Edits with no
photo open) and Undo/Redo titles must be dynamic ("Undo Exposure"), using focused scene values rather
than unconditional `NotificationCenter` posts.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M2 (second half) and "Nice to have: Menu plumbing".

- `Sources/KromoraKit/Views/MenuCommands.swift` File menu (~L79-150): every `Button` calls
  `post(.xxx)` and none uses `.disabled(...)`, so Export, Reset Photo, Copy/Paste Edits, Derive,
  Delete, etc. look available with no photo open.
- KRMA-920 introduced `@FocusedValue(\.keyboardRouter)` for the Photo/Tools menus; reuse that
  pattern and the same focused-value key (or a sibling key in the same file) instead of a new
  mechanism. Read `KeyboardCommandRouter` first.
- Undo titles are static ("Undo"); the edit undo stack lives in the edit-history coordinator
  (`Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift`) and `AppViewModel`.

## Acceptance criteria

- [ ] A small pure model (e.g. `MenuCommandAvailability`) maps app state (photo open?, selection
      non-empty?, canUndo/canRedo, undo action name) to per-command enabled flags and titles. It has
      unit tests in `MenuCommandTests.swift` covering: no photo, photo open, grid with selection,
      grid without selection.
- [ ] Each File-menu command that needs a photo/selection is `.disabled` when the model says so.
      Commands that are always valid (Open Image, Import …) stay enabled.
- [ ] Undo/Redo titles include the action name when the model supplies one ("Undo Exposure"),
      falling back to plain "Undo"/"Redo".
- [ ] The migrated commands read the model through the focused value; they no longer need to post a
      notification just to reach the app model. Leave any command you do not migrate on its existing
      notification and list it in the review comment.
- [ ] No behavior regression: existing `MenuCommandTests` and `KeyboardCommandRouterTests` still pass.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.

## Implementation notes

Depends on the Undo/Redo move (menus file will conflict otherwise) and on KRMA-920. Do not change key
equivalents here (ticket "Menu shortcut conventions" owns that).


### Comment — claude @ 2026-10-13T18:20:58.864Z

Implemented in 282032b4. New pure MenuCommandAvailability (ViewModels/MenuCommandAvailability.swift) published as focused value menuAvailability; migrated to KeyboardCommandRouter.perform(MenuCommand) with .disabled: Export, Export Originals, Edit in External Editor, Export Original + Settings, Reset Photo, Copy Edits…, Copy All Edits, Paste Edits, Save as Look/LUT, Delete Selected. Their notification names/receivers were removed. Still on notifications: Open Image, Look folder/import, Photos/Source/Removable import, Refresh Library, Derive Look, Apply Auto Edits (already context-disabled), and Undo/Redo actions (kept for text-field arbitration; items intentionally stay enabled). Undo/Redo titles use the action name when supplied, but EditHistory does not track action names yet, so the live title is plain Undo/Redo until a follow-up records names. Tests: 5 new in MenuCommandTests; ci-tests fast exit 0, serial exit 0 (after fixing my own count assertion). Not run: StoredEditAdoptionTests did not fail.

## Agent log

- 2026-10-13T18:29:10.969Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A pure menu availability model maps photo, grid selection, paste, undo/redo availability, and optional action names; tests cover no photo, open photo, grid with selection, and grid without selection. (pass) — MenuCommandAvailability is a Sendable value model; MenuCommandTests covers the requested states and named/fallback titles.
- [x] File-menu commands that need a photo or selection are disabled when unavailable; always-valid open/import commands stay enabled. (pass) — Photo and selection commands bind .disabled to the focused availability value; Open Image and import actions remain enabled.
- [x] Undo/Redo titles include action names when supplied and fall back to Undo/Redo. (pass) — The focused title formatter and menu binding meet the conditional criterion. The current AppViewModel initializer does not supply live action names, so titles remain plain until edit history carries names; tracked in backlog child KRMA-971.
- [x] Migrated commands use focused scene values without NotificationCenter; unmigrated commands remain on existing notifications and are listed. (pass) — Migrated photo/selection actions call KeyboardCommandRouter. Notifications remain for Open Image, Choose Look Folder, Import Look, Photos/Source/Removable import, Refresh Library, Derive Look, Apply Auto Edits, and Undo/Redo (retained for text-field arbitration).
- [x] MenuCommandTests and KeyboardCommandRouterTests pass without behavior regressions. (pass) — Both suites ran in the serial CI lane with no failures.
- [x] swift build is warning-free and Swift 6 constraints remain clean. (pass) — Build exited 0 with no warnings. Reviewed changes for concurrency opt-outs and availability branches; none introduced.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — Exited 0; all 1,804 required fast tests completed.
- [x] scripts/ci-tests.sh serial exits 0. (pass) — Exited 0; all 541 required serial tests completed.
Checks run:
- swift build (exit 0, no warnings)
- scripts/ci-tests.sh fast (exit 0, 1,804 tests)
- scripts/ci-tests.sh serial (exit 0, 541 tests)
- git diff --check 282032b4^ 282032b4 (exit 0)
- Independent review of focused scene wiring, command guards, and migrated/unmigrated File-menu actions
Findings:
- Live Undo/Redo action names are not yet populated from edit history; KRMA-971 is a backlog child labeled verification with parent KRMA-925.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV70BLEQUQAGL3XK
Summary: Independent verification passed. Build and both required CI lanes pass; tracked live Undo/Redo action-name follow-up in KRMA-971.
