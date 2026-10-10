---
id: KRMA-867
title: "Culling keys: apply to every selected photo (filmstrip and Library) and stop auto-advancing"
type: bug
status: backlog
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:26:55.477Z
updated: 2026-10-10T19:26:55.844Z
blockers: []
order: zzzzv
board: product
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
