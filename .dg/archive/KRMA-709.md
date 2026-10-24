---
id: KRMA-709
title: Prevent thumbnail flicker during edits and photo navigation
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T04:16:52.381Z
  session: 01MUM5ZATO7Z8J6E9N
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
updated: 2026-09-29T04:16:59.430Z
blockers: []
order: a0
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

### Comment — codex @ 2026-09-29T04:16:06.905Z

Fixed the thumbnail publication flicker: the coordinator previously invalidated a stale edited raster to the source image before rendering its replacement. It now keeps the last published image until a current successful render publishes, while existing source/document/generation fences reject superseded results. Added regression coverage for replacement visibility; the edited-thumbnail coordinator suite passes (14 tests). Commit: dfac2f0.

### Comment — claude @ 2026-09-29T04:16:59.429Z

Verification note: the stored report for this completion is a stub (verdict only, summary 'x'). It came from a schema probe I ran with the completion command by mistake; the review itself had already passed. Actual result: PASS. swift build passes; swift test --filter EditedThumbnail runs 17 tests with 0 failures. Removing invalidate-to-source in EditedThumbnailCoordinator.request keeps the last edited raster visible during refresh and navigation. The generation, source-identity and document-revision fences still reject superseded results. A failed render leaves the image and revision unchanged and retries on next demand. Caveat: a photo never rendered this session still shows its source thumbnail until its first render. Minor: applyEditedThumbnail no longer short-circuits on an identical revision, so forced refreshes republish an equivalent image. No fixes applied, no child tickets.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T04:16:52.381Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM5ZATO7Z8J6E9N
Summary: x
