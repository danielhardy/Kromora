---
id: KRMA-709
title: Prevent thumbnail flicker during edits and photo navigation
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - thumbnail
  - filmstrip
  - library
  - navigation
  - rendering
created: 2026-09-29T03:27:27.964Z
updated: 2026-09-29T03:27:52.067Z
order: zx
board: product
---

## Objective

Keep photo thumbnails visually stable while edits update and navigation changes the active image.

## Context

Thumbnails continue to flicker when edits are made and when navigating between images. Determine
which thumbnail surfaces are affected (including the library grid and bottom filmstrip), and trace
the transitions between the current thumbnail, an in-progress refresh, and the settled result.
When navigating to a photo that already has edits, its thumbnail visibly cycles from the unedited
source to the edited version even though no edit was made to that photo during navigation. It should
show that photo's last edited state directly. Thumbnails should continue to reflect the latest edit
for their own photo once rendering completes.

## Acceptance criteria

- [ ] Reproduce flicker during both edit changes and navigation between photos, and identify the
      publication or loading transition that causes it.
- [ ] On navigation to a photo with edits, avoid swapping from its unedited source thumbnail to its
      edited thumbnail; present the last edited state without that visible cycle.
- [ ] While a new edit render is prepared, keep the last published edited thumbnail visible and
      avoid blank frames or repeated swaps through intermediate states.
- [ ] Ensure published thumbnails belong to the correct photo; discard an in-flight result when
      navigation or a newer edit supersedes its request.
- [ ] Add regression coverage for the thumbnail publication lifecycle, or document a repeatable
      visual check if the flicker only appears in asynchronous UI presentation.

## Implementation notes

Check both original and edited thumbnail publication paths and the filmstrip/grid consumers. For a
photo with edits, preserve its last edited thumbnail across navigation and while a current
replacement renders; prevent the original source or a superseded render from replacing it.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
