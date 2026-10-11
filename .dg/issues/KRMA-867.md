---
id: KRMA-867
title: "Culling keys: apply to every selected photo (filmstrip and Library) and stop auto-advancing"
type: bug
status: done
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: P/X/U/0-5 and culling bar apply to every selected photo in Library and Edit filmstrip while preserving active selection.
      result: pass
      notes: Confirmed by selection-batch implementation and focused culling/view-model tests; culling controls read their displayed state from the active photo.
    - criterion: P/X/U do not auto-advance; arrow navigation remains available.
      result: pass
      notes: Shortcut entry point no longer advances; navigation and culling tests passed.
    - criterion: One Undo restores a whole batch.
      result: pass
      notes: Grouped undo test passed.
    - criterion: Library, filmstrip, keyboard and culling checks pass.
      result: pass
      notes: Ran 57 tests covering culling, LibraryBrowsingCoordinator, KeyMonitor and FilmstripNavigation.
  checks_run:
    - swift test --filter LibraryCullingTests — passed, 11 tests.
    - swift test --filter 'LibraryCullingTests|LibraryBrowsingCoordinatorTests|KeyMonitorTests|FilmstripNavigationTests' — passed, 57 tests.
  findings: []
  fixes:
    - Corrected stale Pick/Reject culling button help text that still said the action advances.
  verification_commits:
    - ccb6588220fffabb098e729e474cf2e5ad5b62eb
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:01:57.272Z
  session: 01MV38KFCHQXQ47UFN
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:26:55.477Z
updated: 2026-10-11T03:01:57.276Z
blockers: []
order: z
board: product
commits:
  - 9816b8d851aab132383534acc039c0c20808c173
  - ccb6588220fffabb098e729e474cf2e5ad5b62eb
---

## Objective

1. Culling keys (P pick, X reject, U clear flag, 0-5 rating) only affected the active photo even when several photos were selected with Shift or Command in the Edit filmstrip. They should apply to every selected photo.
2. P, X and U auto-advanced to the next photo after marking. They should only mark, so the arrow keys stay free for navigation.
3. The Library grid should behave the same way.

## Root cause

- `AppViewModel.setFocusedFlag/setFocusedRating` went to `ImageCollection.setFlag/setRating`, which act on `selectedItem` (the single active photo). The filmstrip, the Library grid and the culling bar all share `LibrarySelectionModel`, so the selection existed but was ignored.
- `KeyboardShortcuts` and `CullingBarView` passed `advance: true`.
- The undo stack and catalog persistence tracked a single photo (`lastCullingAssetID`).

## Work done

- `ImageCollection`: `cullingTargetIDs` (the whole selection in order, else the active photo), `setFlagForSelection` and `setRatingForSelection`. A batch only touches photos that actually change, keeps the selection and active photo, and does not advance. A single photo keeps the old behavior. The culling undo stack now holds one group per action, so one undo reverts a whole batch; `lastCullingAssetIDs` lists everything the last action changed.
- `LibraryBrowsingCoordinator`: uses the selection methods, persists every changed photo to the package (previously only the last), and reports "N photos: Picked / Rejected / Rated n stars" in the status line.
- `AppViewModel.perform(_ command: LibraryCullingCommand)` is the single entry point for culling keys; `KeyboardShortcuts` calls it, and neither it nor `CullingBarView` advances. The `advance:` parameter on `setFlag`/`setFocusedFlag` remains for explicit callers and existing tests.
- Tests (`LibraryCullingTests`): batch flag and rating across a Shift-selection and grouped undo; only changed photos recorded; key marks without moving the selection; multi-selection through the view model; batch persistence to the package after relaunch.

## Acceptance criteria

- With several photos selected in the filmstrip or the Library grid, P/X/U/0-5 and the culling bar apply to all of them and the selection is unchanged afterwards.
- X, P and U never change the active photo; arrow keys navigate.
- One Undo reverts the whole batch.
- Library, filmstrip, keyboard and culling tests pass (308 related tests did). Not yet confirmed by hand in the running app.


### Comment — claude @ 2026-10-11T01:13:16.272Z

Handoff to verification (implementer: claude; reporter has reviewed). Commit 9816b8d8. Culling keys (P/X/U/0-5) and the Library culling bar now apply to every selected photo, in the Edit filmstrip and the Library grid, and no longer auto-advance. ImageCollection: cullingTargetIDs, setFlagForSelection, setRatingForSelection (only changed photos recorded, selection and active photo kept); undo stack holds one group per action so one undo reverts a batch; lastCullingAssetIDs drives catalog persistence in LibraryBrowsingCoordinator, which now persists every changed photo (previously only the last) and reports 'N photos: ...'. AppViewModel.perform(_:) is the single entry point for culling keys. The advance: parameter remains for explicit callers and existing tests. Tests: 5 new in LibraryCullingTests (batch flag/rating with grouped undo, only-changed recorded, no advance, view-model multi-selection, batch persistence after package relaunch); 308 related tests green. Check: undo grouping after a partial batch and that the culling bar controls reflect the active photo while acting on all.


### Comment — claude @ 2026-10-11T01:13:25.367Z

Commits for KRMA-867 (oldest first; review with git show <sha>):
- 9816b8d851aab132383534acc039c0c20808c173 KRMA-867: apply culling keys to every selected photo and stop auto-advancing

## Agent log

- 2026-10-11T03:01:57.272Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] P/X/U/0-5 and culling bar apply to every selected photo in Library and Edit filmstrip while preserving active selection. (pass) — Confirmed by selection-batch implementation and focused culling/view-model tests; culling controls read their displayed state from the active photo.
- [x] P/X/U do not auto-advance; arrow navigation remains available. (pass) — Shortcut entry point no longer advances; navigation and culling tests passed.
- [x] One Undo restores a whole batch. (pass) — Grouped undo test passed.
- [x] Library, filmstrip, keyboard and culling checks pass. (pass) — Ran 57 tests covering culling, LibraryBrowsingCoordinator, KeyMonitor and FilmstripNavigation.
Checks run:
- swift test --filter LibraryCullingTests — passed, 11 tests.
- swift test --filter 'LibraryCullingTests|LibraryBrowsingCoordinatorTests|KeyMonitorTests|FilmstripNavigationTests' — passed, 57 tests.
Findings:
- None
Fixes:
- Corrected stale Pick/Reject culling button help text that still said the action advances.
Verification commits:
- ccb6588220fffabb098e729e474cf2e5ad5b62eb
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38KFCHQXQ47UFN
Summary: Verification passed; fixed stale culling help text.
