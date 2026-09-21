---
id: KRMA-329
title: Investigate Lumo-domain source-folder bookmark resolution failure (NSCocoa 259) masking restoreLibrary fallback
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the NSCocoa 259 resolution failure for the Lumo-suite bookmark under swift run and determine cause
      result: pass
      notes: "Prior comment (codex) reproduced: resolving stored bookmark with .withSecurityScope throws NSCocoaErrorDomain 259 under swift run while resolving without the option succeeds for the same path; consistent with a sandboxed/bundled-app bookmark contract mismatch, not a stale folder. Independently confirmed the fix does not regress this: all callers of setSourceFolder/restoreSourceFolder under swift test (same unbundled binary class as swift run) pass, including two pre-existing setSourceFolder call sites (ExportCutoverTests, ExportCoordinatorTests)."
    - criterion: Decide whether saveBookmark/restoreSourceFolder should validate or refresh the bookmark on failure instead of silently falling through to restoreLibrary()
      result: pass
      notes: ImageCollection.saveBookmark now round-trips (create -> resolve with .withSecurityScope -> access) before persisting, and returns Bool. AppViewModel.init's restore chain now checks collection.hasPersistedSourceFolderBookmark before falling through to restoreLibrary(), so an unreadable persisted bookmark no longer silently selects the managed library.
    - criterion: If user-visible recovery is warranted, surface it rather than silently showing the managed-library grid
      result: pass
      notes: AppViewModel.init presents an actionable alert ("Lumo could not restore the source folder. Choose Open Source Folder... to select it again.") via presentError when hasPersistedSourceFolderBookmark is true but restoreSourceFolder() failed, and no longer calls restoreLibrary() in that branch. Regression test testUnreadableSourceBookmarkDoesNotFallBackToManagedLibrary asserts an empty grid, statusMessage, and errorMessage.
  checks_run:
    - swift build (debug) - clean
    - swift test --filter AppViewModelTests - 27/27 passed
    - scripts/ci-tests.sh fast - 676/676 passed
    - git diff --check - no whitespace errors
    - dg validate - OK (pre-existing agents.pickup.runner model warning, unrelated)
  findings:
    - "Non-blocking: ImageCollection.saveBookmark's Bool persist-failure return is discarded by its only caller, setSourceFolder. If the immediate create/resolve/access round-trip fails, no bookmark is ever written to defaults, so on the next launch hasPersistedSourceFolderBookmark is false and the app falls through to restoreLibrary() exactly as before LUMO-329 -- the same masking behavior reached via the save path instead of the restore path. Not covered by this issue's acceptance criteria or regression test; filed as child ticket LUMO-331 (parent LUMO-329, label verification, low priority) rather than treated as a blocker."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T22:33:49.500Z
  session: 01MTUO9Y3QACKAKF3J
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
created: 2026-09-09T21:53:45.101Z
updated: 2026-09-10T12:53:57.304Z
parent: KRMA-325
order: a0
board: product
---

## Objective

Investigate Lumo-domain source-folder bookmark resolution failure (NSCocoa 259) masking restoreLibrary fallback

## Context

Filed as a non-blocking follow-up during verification of KRMA-325 (commit 63f51c9). KRMA-325's
root-cause writeup (step 3 of Scope/Steps) noted that `URL(resolvingBookmarkData:options:
[.withSecurityScope])` on the stored `imageSourceFolderBookmark` throws `NSCocoaErrorDomain
Code=259` when read back from the `Lumo` UserDefaults suite used by `swift run`. That failure is
why `AppViewModel.init` silently falls through from `restoreSourceFolder()` to
`restoreLibrary()` (grid-only, no `openFirstImageWhenScanned()`), which is one of the two
preconditions for the "32 of 32" brown-grid symptom that KRMA-325 fixed (the other being the
test-fixture pollution, which is now resolved). KRMA-325 fixed the pollution but did not touch
bookmark handling, so `restoreLibrary()` can still be reached via a corrupt/unreadable bookmark
even with a clean managed Library — the app would then show an empty-library grid rather than
the source folder, without any error surfaced to the user.

## Acceptance criteria

- [ ] Reproduce the NSCocoa 259 resolution failure for the `Lumo`-suite bookmark under `swift run`
      and determine whether it's a sandboxed-vs-unbundled bookmark mismatch or a genuinely stale
      bookmark.
- [ ] Decide whether `saveBookmark`/`restoreSourceFolder` should validate or refresh the bookmark
      on failure instead of silently falling through to `restoreLibrary()`.
- [ ] If user-visible recovery is warranted, surface it (e.g. prompt to reselect the source folder)
      rather than silently showing the managed-library grid.

## Implementation notes

See `Sources/LumoKit/ViewModels/AppViewModel.swift` (`restoreSourceFolder`, `restoreLibrary`) and
`Sources/LumoKit/Models/ImageCollection.swift` (`saveBookmark`/bookmark resolution). Related: KRMA-325.

### Comment — codex @ 2026-09-09T22:30:50.943Z

Reproduced the stored Lumo-suite bookmark failure under swift run: resolving with .withSecurityScope throws NSCocoaErrorDomain Code=259, while resolving without the security-scope option succeeds for the same path. This is consistent with a sandboxed bundled-app bookmark being read by the unbundled binary, rather than evidence that the folder is stale. Implemented in commit 049c2d5: newly saved bookmarks are validated with the same security-scope contract used at relaunch; an existing unreadable bookmark is retained and surfaced as an actionable alert to choose Open Source Folder again, and restoreLibrary is no longer used to mask that failure. Added a regression proving a managed-library image is not loaded in this state. Verification: swift test --filter AppViewModelTests (27 passed), swift test --parallel (1047 passed), swift build -c release, git diff --check, dg validate (OK; pre-existing runner-model warning).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T22:33:49.500Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the NSCocoa 259 resolution failure for the Lumo-suite bookmark under swift run and determine cause (pass) — Prior comment (codex) reproduced: resolving stored bookmark with .withSecurityScope throws NSCocoaErrorDomain 259 under swift run while resolving without the option succeeds for the same path; consistent with a sandboxed/bundled-app bookmark contract mismatch, not a stale folder. Independently confirmed the fix does not regress this: all callers of setSourceFolder/restoreSourceFolder under swift test (same unbundled binary class as swift run) pass, including two pre-existing setSourceFolder call sites (ExportCutoverTests, ExportCoordinatorTests).
- [x] Decide whether saveBookmark/restoreSourceFolder should validate or refresh the bookmark on failure instead of silently falling through to restoreLibrary() (pass) — ImageCollection.saveBookmark now round-trips (create -> resolve with .withSecurityScope -> access) before persisting, and returns Bool. AppViewModel.init's restore chain now checks collection.hasPersistedSourceFolderBookmark before falling through to restoreLibrary(), so an unreadable persisted bookmark no longer silently selects the managed library.
- [x] If user-visible recovery is warranted, surface it rather than silently showing the managed-library grid (pass) — AppViewModel.init presents an actionable alert ("Lumo could not restore the source folder. Choose Open Source Folder... to select it again.") via presentError when hasPersistedSourceFolderBookmark is true but restoreSourceFolder() failed, and no longer calls restoreLibrary() in that branch. Regression test testUnreadableSourceBookmarkDoesNotFallBackToManagedLibrary asserts an empty grid, statusMessage, and errorMessage.
Checks run:
- swift build (debug) - clean
- swift test --filter AppViewModelTests - 27/27 passed
- scripts/ci-tests.sh fast - 676/676 passed
- git diff --check - no whitespace errors
- dg validate - OK (pre-existing agents.pickup.runner model warning, unrelated)
Findings:
- Non-blocking: ImageCollection.saveBookmark's Bool persist-failure return is discarded by its only caller, setSourceFolder. If the immediate create/resolve/access round-trip fails, no bookmark is ever written to defaults, so on the next launch hasPersistedSourceFolderBookmark is false and the app falls through to restoreLibrary() exactly as before KRMA-329 -- the same masking behavior reached via the save path instead of the restore path. Not covered by this issue's acceptance criteria or regression test; filed as child ticket KRMA-331 (parent KRMA-329, label verification, low priority) rather than treated as a blocker.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTUO9Y3QACKAKF3J
Summary: Verified: validated bookmark save/restore contract closes the NSCocoa 259 masking path; 27 AppViewModelTests + 676 fast-lane tests + build pass. Filed KRMA-331 (non-blocking, low severity) for the analogous save-side gap where a failed persist silently re-opens the same fallback on next launch.
