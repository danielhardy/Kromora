---
id: KRMA-930
title: Get CI green on the release candidate (push main, fix CI-only failures)
type: task
status: done
priority: high
human_review_required: true
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A human pushes the release-candidate commit and shares its Actions URL
      result: pass
      notes: Actions run 39956187906 was triggered by a push to main on 653f600dd11dc801c3f186583dfe3fa4b969de57.
    - criterion: All CI jobs pass on the pushed commit
      result: pass
      notes: All six configured jobs completed successfully, including Application smoke path and both test lanes.
    - criterion: Record the passing run URL and commit SHA in a comment on this ticket
      result: pass
      notes: The issue comment dated 2026-10-23T13:14:47.185Z records https://github.com/danielhardy/Kromora/actions/runs/39956187906 and the full commit SHA.
  checks_run:
    - gh run view 39956187906 --json event,headBranch,headSha,status,conclusion,jobs
    - git diff --check
    - Independent review of the KRMA-930 CI fixes and hosted run
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-24T12:49:26.780Z
  session: 01MVME99SO5RBKEKE7
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - ci
created: 2026-10-13T14:47:40.853Z
updated: 2026-10-24T13:05:09.129Z
parent: KRMA-922
depends_on:
  - KRMA-1090
blockers:
  - id: evt_mv7149c2_hsxffw
    type: human
    reason: CI has not run on the release candidate
    action: Push main (or a release branch) and share the Actions run URL
    created_at: 2026-10-13T18:43:24.098Z
    resolved_at: 2026-10-21T13:08:33.491Z
    resolved_by: cli
  - id: evt_mvi5kxr4_fuhwu8
    type: human
    reason: The CI fixes are committed locally, but the required Actions rerun needs a human push.
    action: Push commit 5680094721eb7b73a4e99ebc8526252310d96815 to main and share the new GitHub Actions run URL.
    created_at: 2026-10-21T13:33:48.640Z
    resolved_at: 2026-10-21T13:41:53.093Z
    resolved_by: cli
  - id: evt_mvi6him8_yo11kp
    type: human
    reason: The smoke-harness fix is committed locally; validating it requires a human push and another Actions run.
    action: Push commit c2f4f2a8 to main and share the new GitHub Actions run URL.
    created_at: 2026-10-21T13:59:08.672Z
    resolved_at: 2026-10-21T14:00:10.580Z
    resolved_by: cli
  - id: evt_mvi77ui7_c25u9r
    type: human
    reason: The smoke and AppKit test fixes are committed locally; full CI verification requires a human push.
    action: Push commit d158e448849e993bb531672e3845d7494a9b7e40 to main and share the new GitHub Actions run URL.
    created_at: 2026-10-21T14:19:37.135Z
    resolved_at: 2026-10-22T18:51:57.487Z
    resolved_by: cli
order: zr
board: product
blocked_reason: The smoke and AppKit test fixes are committed locally; full CI verification requires a human push.
blocked_action: Push commit d158e448849e993bb531672e3845d7494a9b7e40 to main and share the new GitHub Actions run URL.
blocked_from_status: ready
---

## Objective

CI must run on the exact release-candidate commit and be green. Today `main` is 156 commits ahead of
`origin/main` and CI has never run on it.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M4 (fourth bullet). `CLAUDE.md` describes CI: GitHub Actions arm64
`xcode-27` image runs `scripts/ci-tests.sh fast` (parallel) and `serial`, optional lanes on demand,
then builds and verifies the packaged app (`scripts/app-store-build.sh`). Pushing is a human-approved
action in this repo (`.dg/AGENTS.md`: push only when a human asks).

## Acceptance criteria

- [ ] A HUMAN pushes `main` (or a release branch) after tickets KRMA-927, KRMA-928, KRMA-929 are done and
      KRMA-920 is verified. Agents must NOT push.
- [ ] All CI jobs pass on the pushed commit. For each CI-only failure (different Xcode image,
      slower runners), either fix it with a commit `KRMA-<this>: …` or file a child ticket.
- [ ] The passing run URL and commit SHA are recorded in a comment on this ticket.

## Implementation notes

Block on the human with: reason "CI has not run on the release candidate", action "Push main (or a
release branch) and share the Actions run URL". Once the URL exists, an agent can read failures with
`gh run view --log-failed`.


### Comment — codex @ 2026-10-19T17:03:31.404Z

October 19 review follow-ups are under KRMA-1051: KRMA-1054 owns the reproduced production entitlement-allowlist failure; KRMA-1055 owns the retired export UI smoke path; KRMA-1056 and KRMA-1057 own emitted test-isolation warnings and enforcement. Consume those fixes when evaluating release-candidate CI. Ticket filing performed no push, CI rerun, or remote status claim.


### Comment — codex @ 2026-10-21T13:33:45.867Z

The Actions run https://github.com/danielhardy/Kromora/actions/runs/39605333307 failed on d022893fe973f72ed18299bb8a07238d34fb710a: first-run onboarding blocked the smoke picker; CropKeyboardWindowTests ran in the parallel lane; LookPreviewTests relied on a fixed 10 ms cancellation window; and the slider animation test relied on a fixed 430 ms wait. Fixed in 5680094721eb7b73a4e99ebc8526252310d96815. Checks passed: CI lane audit (2,755 tests partitioned), 38 focused tests, Swift format, shell syntax, AppleScript compile, and git diff check. Human action: push this commit to main and share the new Actions run URL; repo policy prohibits agent pushes.


### Comment — codex @ 2026-10-21T13:59:02.898Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39610173168 on 5680094721eb7b73a4e99eb8bb? failed the Application smoke path at Open Image panel did not appear; the invocation used Command-O after readiness, but the panel never opened. Packaging, Xcode build, formatting, and the parallel test lane passed. The serial test lane was still running at the last check. Changed the harness to click the enabled File > Open Image… menu item directly and committed as c2f4f2a8. Local checks passed: zsh syntax, compiled AppleScript, and git diff check. Repo policy requires a human push for the next Actions run.


### Comment — codex @ 2026-10-21T13:59:06.599Z

Correction: the full head SHA for run 39610173168 is 5680094721eb7b73a4e99ebc8526252310d96815; the SHA in my previous comment was mistyped.


### Comment — codex @ 2026-10-21T14:19:36.913Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39612853644 on  c2f4f2a842ea7a8065a47f19f67c1bb9582a10cb failed in two places. Application smoke still searched for Open Image as a standalone window; AppKit presents NSOpenPanel as a sheet attached to the main window. The serial lane had four assertions fail across CropKeyboardWindowTests because NSApp.sendEvent did not deliver synthesized keys from the inactive XCTest app. Formatting, package build, Xcode app build, and the parallel test lane passed. Fixed the smoke sheet hierarchy in 8a343d7c and changed the crop tests to send these no-menu-equivalent keys through the target NSWindow in d158e448849e993bb531672e3845d7494a9b7e40. Local verification: both CropKeyboardWindowTests pass, changed-file Swift format passes, shell syntax and AppleScript compilation pass, and git diff check passes. Repo acceptance requires a human push for the next full Actions run.


### Comment — codex @ 2026-10-22T19:06:11.315Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39834730308 on 6a7bdcc4b23cb4ddd89e73f5af591ac036797c40 finished with FAILURE. Passed: Swift-format, serial render/UI tests, deterministic/model tests, packaging/signing, and Xcode build. Application smoke path failed in “Launch, import, Settings/menu, and export smoke path”; bundle build passed. Could not fetch failed-step logs: GitHub returned HTTP 403 for the unauthenticated API rate limit, and gh auth status reports the configured token is invalid. Leaving KRMA-930 in verification until the failure details can be inspected and fixed or filed as a child ticket.

### Comment — codex @ 2026-10-22T19:08:28.657Z

The current local branch contains c00d5692 (KRMA-930: harden smoke dialog polling), but Actions run 39834730308 tested the earlier SHA 6a7bdcc4b23cb4ddd89e73f5af591ac036797c40. The local commit is outside this run and still needs a human push and separate CI verification.

### Comment — codex @ 2026-10-22T20:08:12.010Z

The smoke failure output supplied by the user is: “System Events got an error: Can’t get window 1 of process 1 whose unix id = 11537. Invalid index. (-1719).” This is consistent with a transient accessibility query during a window or sheet transition. Local commit c00d56926450c7a17a12434e387ebad77b365511 adds retry guards around Open Image sheet polling and passes zsh syntax validation. Run 39834730308 tested earlier SHA 6a7bdcc4b23cb4ddd89e73f5af591ac036797c40, so it does not verify c00d5692.

### Comment — codex @ 2026-10-22T23:46:35.492Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39872317432 on 328a3fb1b66d4ecaf507ad84ca514aa779953c21 completed with FAILURE. Failed: Swift-format (changed files), Tests (Core Image/render/AppKit/UI, serial), and Application smoke path. Passed: Tests (deterministic/model, parallel), Package/sign/verify app, and Build/verify Xcode app. Job summaries show the failed steps, but GitHub denied log retrieval (HTTP 403: admin rights required; the serial job details also hit the unauthenticated API rate limit). The smoke error from the prior run was an invalid System Events window index (-1719); the current run needs logs before we can confirm whether it is the same failure.

### Comment — codex @ 2026-10-23T02:51:28.229Z

Run https://github.com/danielhardy/Kromora/actions/runs/39888846287 on 423c1e4adce70b3d5f8ba6510cdbf4d0d44a90f4 finished with five passing jobs and only Application smoke path failing. The smoke error is the same invalid text-field index (-1719) as run 39883149380 on fa14407572711e98401778e05383260638c8358c.

Reproduced on a fresh isolated development profile: the first-run welcome sheet remained open because its SwiftUI buttons are nested in a group and their attributed accessibility labels are not readable by System Events as button names. Open Image then opened over the welcome sheet, invalidating the harness's assumed sheet hierarchy. Added welcome.startEmpty to the empty-library action, explicitly wait for and dismiss onboarding before import, and wait for actionable file-dialog controls. AppleScript element lists are resolved before iteration. UI-stage failures now exit explicitly so zsh runs the cleanup trap.

Run 39883149380 also reported formatting violations in ContentView.swift and LibraryHandoffStateTests.swift; these are formatted. The formatter passed on 39888846287 because that merge introduced no changed Swift files, rather than because the old files had been corrected. The earlier serial failure from run 39872317432 is now accessible: NeutralOriginSliderTests.testPhotoSwitchHoldsSliderAtOutgoingValueUntilIncomingDocumentArrives asserted -0.5 while the slider was still at -0.462538 after a fixed delay. Replaced that final delay with the existing bounded completion wait, preserving the intermediate animation assertions.

Local verification passed: current SwiftPM Release build; 36 focused LibraryHandoffStateTests, NeutralOriginSliderTests, and OnboardingTests; strict formatting for all four changed Swift files; zsh syntax; compilation of all seven AppleScript stages; git diff check. The complete smoke harness passed against the rebuilt unsandboxed development app with its own bundle ID, preferences, and temporary library: a fresh profile exported 000-Kromora-Smoke.jpg and a repeat launch with saved naming exported pre-000-Kromora-Smoke-sfx.jpg, both decoded as 256x256 JPEGs. These are local development-app checks; the signed hosted-runner path still needs a new Actions run after a human push. No passing CI run is claimed.

### Comment — codex @ 2026-10-23T02:53:14.350Z

Fixes are committed on main as 0c91ee95a1ba5543047def4e44339eebbe0f2bc4 (KRMA-930: fix fresh-profile CI smoke and slider timing). All local checks recorded above passed, including fresh-profile and saved-naming smoke runs. A human must push this commit for the next signed hosted-runner verification; the latest Actions run remains failed and does not contain these fixes.

### Comment — codex @ 2026-10-23T03:11:45.361Z

Run 39892049431 on 0c91ee95a1ba5543047def4e44339eebbe0f2bc4 passed the smoke path, Swift-format, packaging/signing, Xcode build, and deterministic/model lane. The only failure was one serial test: PreviewSurfaceTests.testStaleSettledReplacementCrossfadesFor120MillisecondsThenReleasesOldTexture, where a fixed 145 ms sleep expired before the main-actor crossfade cleanup task released its texture. Replaced the fixed sleep with a bounded wait for the release condition. The retouch stress corpus also prints rows marked FAIL, but its XCTest passed; those are report metrics. Local validation passed the focused test, all 53 PreviewSurfaceTests, strict formatting, and git diff --check. A human push and a new Actions run are still required for hosted verification.

### Comment — codex @ 2026-10-23T03:13:33.920Z

Follow-up CI fix committed as 91b95b83. Run 39892049431 had one serial-test failure: PreviewSurfaceTests.testStaleSettledReplacementCrossfadesFor120MillisecondsThenReleasesOldTexture timed out its fixed 145 ms assumption. The test now waits up to 2 s for the actual crossfade texture release. Local focused test, all 53 PreviewSurfaceTests, repository changed-file formatter, and diff check passed. This commit still needs a human push and a fresh hosted run.

### Comment — codex @ 2026-10-23T03:57:09.550Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39893920950 on 91b95b83 passed formatting, smoke, packaging/signing, Xcode build, and the serial test lane, but the deterministic/model parallel lane failed two tests. PortableLibrarySessionTests.testAsynchronousStartupRebuildPublishesFirstPageAndReleasesLeaseOnShutdown saw 25 assets instead of 550 after a fixed 20,000-yield loop; the sequential-open thumbnail test incorrectly required navigation loading to remain true after a valid provisional thumbnail could already be presented. Both assumptions now use bounded, lifecycle-correct verification.

The local full parallel lane additionally exposed a 2-second image-open deadline and Retina screenshot tests using point coordinates as pixel coordinates. Those tests now use the shared bounded wait and scale sample points to bitmap pixels. Local verification passed all five affected tests together and scripts/ci-tests.sh fast (2,001 required tests), plus changed-file Swift format and git diff --check. A new hosted Actions run is still required after a human pushes the implementation commit.

### Comment — codex @ 2026-10-23T03:58:27.053Z

Commit 76c41250b138010019ef2f3d6bcc274882d6a0b0 fixes the two failures in Actions run 39893920950 and three host-sensitive test assumptions found during local full-lane verification. The async startup test now waits for index completion; the sequential-open test accounts for a valid provisional frame ending navigation loading; the image-open test uses its bounded suite helper; and the color-wheel/library-grid screenshot tests scale point coordinates to Retina bitmap pixels.

Validation passed locally: five focused tests, scripts/ci-tests.sh fast (2,001 required tests), changed-file Swift format, and git diff --check. Hosted verification still needs a human push of 76c41250 and a fresh Actions run.

### Comment — codex @ 2026-10-23T12:29:42.109Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39898513497 on 76c41250b138010019ef2f3d6bcc274882d6a0b0 failed only in the serial render/UI lane. The sole failure was NeutralOriginSliderTests.testRepeatedPresentationOfTheSameTargetDoesNotRestartAnimation at NeutralOriginSliderTests.swift:364: after a fixed 440 ms, the slider was at 0.9936407415575286 instead of exactly 1.0. The 380 ms animation updates on a main-actor task and applies its exact endpoint only after that task resumes; the hosted runner reached the assertion before endpoint cleanup ran. Replaced the fixed 260 ms post-repeat sleep with a bounded endpoint wait (320 ms), preserving a deadline before a restarted 380 ms animation could finish. Local validation: all 25 NeutralOriginSliderTests passed, the formerly failing test passed five consecutive runs, changed-file Swift format passed, and git diff --check passed. Hosted verification still needs a human push and a fresh Actions run.

### Comment — codex @ 2026-10-23T12:30:03.918Z

Run 39898513497 on 76c41250 failed only in the serial lane due to NeutralOriginSliderTests.testRepeatedPresentationOfTheSameTargetDoesNotRestartAnimation applying its final slider value late on the hosted runner. The focused fix is committed as 653f600d45e41cc8f62b75b2b642feef899fcfcf. All 25 NeutralOriginSliderTests and five repeated runs of the previously failing test pass locally; Swift format and git diff --check pass. The commit needs a human push and a fresh Actions run before KRMA-930 can be considered green.

### Comment — codex @ 2026-10-23T13:14:47.185Z

Hosted acceptance passed: Actions run https://github.com/danielhardy/Kromora/actions/runs/39956187906 completed successfully on commit 653f600dd11dc801c3f186583dfe3fa4b969de57. All six CI jobs passed, including the serial render/UI tests that failed in run 39898513497. The same-target slider timing fix is verified on the pushed commit. This run URL and SHA satisfy the hosted CI acceptance criterion.

## Agent log

- 2026-10-22T19:07:29.353Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] A human pushes the release-candidate commit and shares its Actions URL (pass) — Run 39834730308 is on 6a7bdcc4b23cb4ddd89e73f5af591ac036797c40.
- [ ] All CI jobs pass on the pushed commit (fail) — Only Application smoke path failed; formatting, both test lanes, packaging/signing, and Xcode build passed.
- [ ] Record a passing run URL and SHA on this ticket (fail) — The run URL and SHA are recorded, but the run is not passing.
Checks run:
- gh run view 39834730308 --json url,headSha,status,conclusion,jobs
- gh run view 39834730308 --job 120019923858
- gh run view 39834730308 --log-failed (HTTP 403 rate limit)
Findings:
- Application smoke path failed at Launch, import, Settings/menu, and export smoke path; bundle build passed.
- Failed-step log retrieval is blocked by GitHub unauthenticated API rate limiting and an invalid configured gh token.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MVJWDZAJDXXVAK13
Summary: CI verification is blocked: the app smoke path failed, but GitHub will not provide its logs until CLI authentication is repaired.

- 2026-10-24T12:49:26.780Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A human pushes the release-candidate commit and shares its Actions URL (pass) — Actions run 39956187906 was triggered by a push to main on 653f600dd11dc801c3f186583dfe3fa4b969de57.
- [x] All CI jobs pass on the pushed commit (pass) — All six configured jobs completed successfully, including Application smoke path and both test lanes.
- [x] Record the passing run URL and commit SHA in a comment on this ticket (pass) — The issue comment dated 2026-10-23T13:14:47.185Z records https://github.com/danielhardy/Kromora/actions/runs/39956187906 and the full commit SHA.
Checks run:
- gh run view 39956187906 --json event,headBranch,headSha,status,conclusion,jobs
- git diff --check
- Independent review of the KRMA-930 CI fixes and hosted run
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MVME99SO5RBKEKE7
Summary: Verification passed: Actions run 39956187906 succeeded on 653f600dd11dc801c3f186583dfe3fa4b969de57; all six CI jobs passed.
