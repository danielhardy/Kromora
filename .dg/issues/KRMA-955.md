---
id: KRMA-955
title: "Menu cleanups: consistent ellipsis, clearer import/refresh titles"
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dialog or input menu titles use U+2026 and no title uses three periods.
      result: pass
      notes: MenuCommandTests coverage passed in the serial lane; visible title scan found no stale three-dot menu titles.
    - criterion: Open Source Folder is renamed Import Folder while preserving its route and shortcut.
      result: pass
      notes: Both menu surfaces use Import Folder… and retain the existing notification/handler route and ⌘⌥I shortcut.
    - criterion: Investigate Refresh Library and record whether to remove or rename it, with evidence.
      result: pass
      notes: Kept ⌘R as Rebuild Library Index. refreshSource() calls rebuildPortableIndex(), which rebuilds the package-backed library index and republishes page one; evidence recorded in the verification comment.
    - criterion: Update docs and tests and leave no stale user-visible menu titles.
      result: pass
      notes: Corrected stale A8 and A19 labels in docs/APP_STORE_ACCEPTANCE.md; old labels remain only in negative regression assertions.
    - criterion: swift build is warning-free and Swift 6 mode remains clean without prohibited escape hatches or availability branches.
      result: pass
      notes: swift build exited 0 with no diagnostics; required fast and serial test lanes also passed their package invariant coverage.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
    - criterion: scripts/ci-tests.sh serial exits 0.
      result: pass
      notes: 545 tests passed with 0 failures.
  checks_run:
    - swift build — exit 0; no warnings or other diagnostics.
    - scripts/ci-tests.sh fast — exit 0.
    - scripts/ci-tests.sh serial — exit 0; 545 tests, 0 failures.
    - Menu-title and stale-reference scan across Sources, Tests, docs, and README — no stale visible titles; prior labels occur only in negative regression assertions.
    - git diff --check -- docs/APP_STORE_ACCEPTANCE.md — exit 0.
    - Working-tree-wide git diff --check also reported pre-existing trailing whitespace in unrelated .dg/issues/KRMA-914.md:248; left untouched.
  findings:
    - Found two stale three-dot menu-title references in docs/APP_STORE_ACCEPTANCE.md (removable-media import and Export Originals) and corrected them.
  fixes:
    - Updated those two checklist labels to match the menu’s U+2026 titles in commit 9db74866.
  verification_commits:
    - 9db74866
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:52:17.218Z
  session: 01MV7G5XONF6GYBIPS
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - menus
  - ux
created: 2026-10-13T14:48:05.615Z
updated: 2026-10-14T01:52:17.221Z
parent: KRMA-922
depends_on:
  - KRMA-924
  - KRMA-925
blockers: []
order: zy
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T01:39:35.563Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 9db74866
---

## Objective

Make menu titles consistent and accurate for a package-backed library.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S11 (bullets 3-4). `Sources/KromoraKit/Views/MenuCommands.swift`:

- Titles mix three dots and the HIG ellipsis character: "Open Image...", "Choose Look Folder...",
  "Import Look...", "Import from Photos...", "Open Source Folder...", "Import from Removable
  Media...", "Export...", "Export Originals..." vs "Copy Edits…", "Derive Look from JPG…",
  "Save as Look/LUT…", "Keyboard Shortcuts…".
- "Open Source Folder…" actually IMPORTS a folder into the library (an import source), and "Refresh
  Library" (⌘R) is a leftover from the folder-backed design: the package library is the source of
  truth and indexes are projections (see `CLAUDE.md`, `docs/STORAGE_POLICY.md`).
- Titles may also appear in `KeyboardShortcutReferenceView`, tests (`MenuCommandTests`) and docs
  (`grep -rn "Open Source Folder\|Refresh Library" Sources Tests docs README.md`).

## Acceptance criteria

- [ ] All menu titles that open a dialog or need more input end with the single ellipsis character `…`
      (U+2026) and none use `...`. A `MenuCommandTests` assertion fails if a title in the menu model
      contains `...`.
- [ ] "Open Source Folder…" is renamed "Import Folder…" (keep its shortcut, notification and handler
      names unless trivial to rename; the user-visible string and docs change).
- [ ] "Refresh Library" is investigated: find what `.refreshSourceFolder` does today. If it is a no-op
      or only meaningful for legacy folder mode, remove the item and its ⌘R shortcut (⌘R becomes free);
      if it still has a purpose (rescan import source), rename it to say what it does and keep it.
      Record the decision and evidence in the review comment.
- [ ] All doc/test references updated; no stale titles (`grep` shows none).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.


### Comment — claude @ 2026-10-14T01:39:29.497Z

Decision: kept ⌘R, renamed 'Refresh Library' -> 'Rebuild Library Index'. Evidence: .refreshSourceFolder -> AppViewModel.refreshSource() -> libraryBrowsingCoordinator.rebuildPortableIndex(), which rebuilds the disposable index from package membership (manual recovery for a grid that disagrees with the package); not a no-op. 'Open Source Folder…' -> 'Import Folder…'. All menu titles use U+2026; MenuCommandTests asserts none contain '...'. Docs/shortcut catalog/QA checklist/help tooltip updated. swift build clean; ci-tests fast and serial exit 0.


### Comment — codex @ 2026-10-14T01:52:02.199Z

Counterpoint verification passed. Decision: keep ⌘R and the menu item as ‘Rebuild Library Index’. Evidence: .refreshSourceFolder routes through AppViewModel.refreshSource() to LibraryBrowsingCoordinator.rebuildPortableIndex(), which calls the package library’s rebuildIndex() and republishes the first page; its docs describe this as recovery when the disposable index disagrees with package membership. ‘Import Folder…’ still routes through the existing source-folder notification and handler. Found two stale three-dot references in APP_STORE_ACCEPTANCE.md (A8 removable-media import and A19 Export Originals) and corrected them in verification commit 9db74866. swift build had no warnings; fast and serial lanes passed.

## Agent log

- 2026-10-14T01:52:17.218Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dialog or input menu titles use U+2026 and no title uses three periods. (pass) — MenuCommandTests coverage passed in the serial lane; visible title scan found no stale three-dot menu titles.
- [x] Open Source Folder is renamed Import Folder while preserving its route and shortcut. (pass) — Both menu surfaces use Import Folder… and retain the existing notification/handler route and ⌘⌥I shortcut.
- [x] Investigate Refresh Library and record whether to remove or rename it, with evidence. (pass) — Kept ⌘R as Rebuild Library Index. refreshSource() calls rebuildPortableIndex(), which rebuilds the package-backed library index and republishes page one; evidence recorded in the verification comment.
- [x] Update docs and tests and leave no stale user-visible menu titles. (pass) — Corrected stale A8 and A19 labels in docs/APP_STORE_ACCEPTANCE.md; old labels remain only in negative regression assertions.
- [x] swift build is warning-free and Swift 6 mode remains clean without prohibited escape hatches or availability branches. (pass) — swift build exited 0 with no diagnostics; required fast and serial test lanes also passed their package invariant coverage.
- [x] scripts/ci-tests.sh fast exits 0. (pass)
- [x] scripts/ci-tests.sh serial exits 0. (pass) — 545 tests passed with 0 failures.
Checks run:
- swift build — exit 0; no warnings or other diagnostics.
- scripts/ci-tests.sh fast — exit 0.
- scripts/ci-tests.sh serial — exit 0; 545 tests, 0 failures.
- Menu-title and stale-reference scan across Sources, Tests, docs, and README — no stale visible titles; prior labels occur only in negative regression assertions.
- git diff --check -- docs/APP_STORE_ACCEPTANCE.md — exit 0.
- Working-tree-wide git diff --check also reported pre-existing trailing whitespace in unrelated .dg/issues/KRMA-914.md:248; left untouched.
Findings:
- Found two stale three-dot menu-title references in docs/APP_STORE_ACCEPTANCE.md (removable-media import and Export Originals) and corrected them.
Fixes:
- Updated those two checklist labels to match the menu’s U+2026 titles in commit 9db74866.
Verification commits:
- 9db74866
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7G5XONF6GYBIPS
Summary: Counterpoint verification passed; corrected two stale menu-title references in the acceptance checklist.
