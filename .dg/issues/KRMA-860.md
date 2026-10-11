---
id: KRMA-860
title: Investigate main-actor time before first suspension regressing to ~99 ms (budget 2 ms)
type: bug
status: verification
priority: high
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Identify the regression cause and offending code path
      result: pass
      notes: Package date precision and browsing placeholder signatures caused whole-file SHA-256 rehashes on main-actor ImageSource construction; the fixes address both paths.
    - criterion: After the fix, three direct runs show median p95 <= 3 ms, or document why the budget cannot hold on this hardware
      result: fail
      notes: The issue records a three-switch dev-build timeline with 2.8 ms selection sync, but not the required three direct Release p95 measurements. Existing guidance limits this ticket to one display-bound series of three, already used for the pre-fix measurements.
    - criterion: Update docs/TESTING.md with the post-fix measured state
      result: fail
      notes: The current measured-state section still calls the 99 ms regression probable and contains no post-fix measured-state results.
  checks_run:
    - "swift test --filter ImageSourceIdentityReuseTests: passed, 4 tests; 0 failures"
    - "Independent source and lifecycle review: verified tolerant snapshot comparison, real identity reuse for browsing observations, legacy placeholder hashing, and off-main materialized record refresh"
  findings:
    - "Blocking: required post-fix Release p95 evidence and its docs/TESTING.md measured-state entry are missing; the current dev-build timeline does not establish the specified median p95 acceptance criterion."
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T01:42:22.245Z
  session: 01MV35PFW2QAL2527B
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:30:37.048Z
updated: 2026-10-11T13:30:58.928Z
blockers:
  - id: evt_mv35unad_qoajp6
    type: human
    reason: Acceptance needs a post-fix Release last-known-frame median p95 (<= 3 ms). The one allowed display-bound series was spent pre-fix, and CLAUDE.md forbids another without approval; docs/TESTING.md now records the cause and the dev-build post-fix timeline (selection sync 100.9 -> 2.8 ms) but marks the Release p95 as unmeasured.
    action: Either approve one supervised post-fix series (caffeinate -dimu, unlocked display, scripts/run-kromora-capture.sh last-known-frame, 3 runs) and add the median p95 to the Post-fix state section of docs/TESTING.md, or accept the dev-build timeline plus ImageSourceIdentityReuseTests as sufficient and close the issue.
    created_at: 2026-10-11T01:44:48.997Z
    resolved_at: 2026-10-11T13:30:58.926Z
    resolved_by: cli
order: h
board: product
blocked_reason: Acceptance needs a post-fix Release last-known-frame median p95 (<= 3 ms). The one allowed display-bound series was spent pre-fix, and CLAUDE.md forbids another without approval; docs/TESTING.md now records the cause and the dev-build post-fix timeline (selection sync 100.9 -> 2.8 ms) but marks the Release p95 as unmeasured.
blocked_action: Either approve one supervised post-fix series (caffeinate -dimu, unlocked display, scripts/run-kromora-capture.sh last-known-frame, 3 runs) and add the median p95 to the Post-fix state section of docs/TESTING.md, or accept the dev-build timeline plus ImageSourceIdentityReuseTests as sufficient and close the issue.
blocked_from_status: ready
footprint:
  source: observed
  paths: []
  observed:
    paths:
      - path: Sources/KromoraKit/Models/ImageSource.swift
        access: write
        confidence: 1
      - path: Tests/KromoraKitTests/ImageSourceIdentityReuseTests.swift
        access: write
        confidence: 1
    base: f9add390ae9df09318f3c58f931554cb1b64b127
    head: 2eaef446ef1bd68bede1bfba7bc952831923acfd
    captured_at: 2026-10-10T20:11:12.457Z
commits:
  - 2eaef446ef1bd68bede1bfba7bc952831923acfd
  - 871d216d7028a7933d95d889b1555760361ce968
  - 0b152709dc116a1db407b6fd411d04f08e6a8528
---

## Objective

The 2026-10-10 last-known-frame direct Release runs show the main-actor time before the first suspension on warm Edit navigation at about 99 ms p95 (99.2 / 99.0 / 99.0 across three runs), against a <= 2 ms target and the 2.03 ms measured after KRMA-746/747 on 2026-10-01. Find out whether this is a real regression and, if so, which change introduced it.

## Evidence

- Reports: `/tmp/kromora-capture/lkf-direct-{1,2,3}.jsonl` and logs `lkf-direct-N.log`; each log also prints `LAST_KNOWN_FRAME_SELECTION_SYNC_MS` of about 98 ms. Section "Last-known-frame measured state on Apple M4 Pro (2026-10-10)" in docs/TESTING.md has the table.
- Machine differs from the earlier table: Apple M4 Pro, macOS 27.2, viewport 1440x1032 (earlier: M1 Pro, macOS 27.0, 1440x897). A faster chip should not make this slower.
- Runs were direct (no xctrace), so tracing overhead is not the cause.
- Also elevated vs 2026-10-01: warm Edit first-pixel p95 387 ms (was 293 ms). Grid re-entry improved (235 to 147 ms) but still misses 100 ms.
- 72 ms was the pre-KRMA-746/747 figure (whole-file SHA-256 on the main actor); 99 ms is the same order, so a re-introduced synchronous hash or similar is a candidate.

## Work

1. Bisect: run `scripts/ci-tests.sh`-style direct runs (see docs/TESTING.md section above for the env vars) on 4bbc5c5f (2026-10-01 baseline commit) rebuilt on this machine, then bisect to the first commit above 3 ms. Commits since then include KRMA-753 (persisted identity hash reuse), KRMA-839 (streaming imports), KRMA-843, and the 2026-10 library/edit work.
2. Profile the selection call (Time Profiler) once xctrace works, or add a signpost inside the pre-suspension path, to identify what runs synchronously on the main actor.
3. Fix or document with a measured explanation.

## Acceptance criteria

- The cause is identified with a baseline run on this machine and the offending commit or code path named.
- After the fix, three direct runs show median p95 <= 3 ms (ADR-LKF-001 amendment), or the ticket records why the budget cannot hold on this hardware.
- docs/TESTING.md gets an updated measured-state section.
- Per CLAUDE.md, at most one series of three display-bound runs per ticket; use window-independent tests where possible.

## Verification blocker

Verification confirms the synchronous SHA-256 rehash cause and the localized fixes; all four
`ImageSourceIdentityReuseTests` pass. The remaining acceptance evidence is incomplete: the recorded
post-fix result is a three-switch dev-build timeline (selection sync 2.8 ms), not three direct
Release measurements reporting the median p95 required by this issue. `docs/TESTING.md` still
labels the 99 ms measurement as a probable regression and has no post-fix measured-state entry.

Before completion, add the post-fix measured-state entry to `docs/TESTING.md` and provide qualifying
three-run Release p95 evidence (or record a measured hardware limitation). The repo guidance limits
display-bound capture to one series of three per ticket, and the pre-fix series is already recorded;
do not start another series. Resolve the acceptance gap using compliant existing evidence or an
approved measurement plan, then rerun the focused identity tests and report the result.


### Comment — claude @ 2026-10-10T20:11:11.864Z

ROOT CAUSE FOUND via the KRMA-869 photo-switch timeline: loadSyncPrefix planMs was 49-50 ms in every switch and selectPortableItem collectionSelectMs came in multiples of ~50 ms (0/50/98/252). ImageSource.makePortableIdentity compared the persisted PhotoSourceFingerprint with a fresh one using ==; the package JSON coder stores dates as ISO-8601 whole seconds (asset.json: 2026-10-09T16:17:37Z, file mtime 16:17:37.384), so they never matched, and every open (and every adjacent-photo ImageSource) fell through to PortablePortableSourceFingerprint.file, a whole-file SHA-256 on the main actor (~50 ms for a 126 MB ARW). Stat plus the 64 KiB sample digest was measured at under 1 ms, so it was not the cause. Fix 2eaef446ef1bd68bede1bfba7bc952831923acfd switches to isSameFileSnapshot (existing, tolerates sub-second truncation); test fails without it. Expect the synchronous span to fall from about 100 ms to a few ms; re-measure with lkf-direct and the photo-switch log.


### Comment — claude @ 2026-10-10T20:14:55.114Z

A post-fix capture (14:13) still showed planMs=49 and collectionSelectMs=254. All 105 library assets whose files are present compare equal with isSameFileSnapshot (probe against the reporter's library), so the likely cause is a stale binary. 871d216d7028a7933d95d889b1555760361ce968 adds a PhotoSwitchPhase wholeFileRehash line (hashMs, hadStoredSignature, mainThread) on the expensive path: if it never appears during a Library to Edit switch the rehash is gone; if it does, that line says why.


### Comment — claude @ 2026-10-10T20:34:06.043Z

The wholeFileRehash log (14:30 capture) showed the first fix was not the whole story: dozens of 49-52 ms whole-file hashes on the MAIN THREAD, hadStoredSignature=true, about 35 back to back at idle with no switch, plus 3-7 inside every photo switch (collectionSelectMs 246-254, planMs 48-50). Cause: browsing assets carry a real content hash but a placeholder change signature (PhotoAsset init(browsingPortableAsset:), no byteCount/mtime/resourceIdentifier), so no comparison can succeed. Callers: EditedThumbnailCoordinator (x2), PreviewAdmissionCoordinator adjacent prefetch, IdleFrameWarmer candidates, AppViewModel.openImage. 0b152709dc116a1db407b6fd411d04f08e6a8528 keeps the stored hash for that case; legacy browsing-v1 identities still hash. Off-main rehashes (hadStoredSignature=false, mainThread=false) in source preparation remain and could reuse the record's persisted sourceChangeSignature as a follow-up. 501 related tests pass.


### Comment — claude @ 2026-10-10T21:13:52.612Z

Post-fix capture (15:13, dev build, three Library to Edit switches). selectPortableItem 2.4 ms (was 50.8), selectionSyncReturned 2.8 ms (was 100.9, 303.8 in one run), planMs 0 (was 49-50), collectionSelectMs 1-2 (was 0/50/98/252), beginLoadScheduled 32 ms (was 520, so the old 420 ms gap was main-thread starvation by the rehashes, not SwiftUI), sourcePrepared 131-180 ms (was 500-580), firstPixel storedFrame 74/192/205 ms (was 1,313-1,955), rendered confirm 609-640 ms. No wholeFileRehash on the main thread; the remaining ones are off-main in source preparation (hadStoredSignature=false, 50-62 ms each).


### Comment — claude @ 2026-10-11T01:13:15.036Z

Handoff to verification (implementer: claude; reporter has reviewed). Commits 2eaef446, 871d216d, 0b152709. The 99 ms main-actor stall before the first suspension was whole-file SHA-256 hashing on the main thread: ImageSource compared a persisted file-change signature with == (package dates are whole seconds, so it never matched), and browsing assets carry a placeholder signature, so every ImageSource built by edited-thumbnail requests, adjacent-preview prefetch, the idle warmer and open rehashed the file (about 50 ms for a 126 MB ARW; about 35 in a row at idle). Fixes: use the existing tolerant isSameFileSnapshot; keep the stored content hash when the signature is a browsing observation and the identity is real (legacy browsing-v1 identities still hash); log wholeFileRehash. Evidence from the KRMA-869 timeline on the reporter's library: selection sync 100.9 ms -> 2.8 ms, planMs 49 -> 0, beginLoadScheduled 520 -> 32 ms, first pixel 1.3-1.95 s -> 74-205 ms. Tests: ImageSourceIdentityReuseTests (4; the round-trip test fails without the fix), plus 501 related identity/thumbnail/preview/relaunch tests green. Check: the new tests, the reasoning on trusting the stored hash for package-embedded originals, and that the off-main rehash in source preparation (hadStoredSignature=false) is acceptable or worth a follow-up.


### Comment — claude @ 2026-10-11T01:13:24.019Z

Commits for KRMA-860 (oldest first; review with git show <sha>):
- 2eaef446ef1bd68bede1bfba7bc952831923acfd KRMA-860: stop rehashing the whole file on the main actor at every photo switch
- 871d216d7028a7933d95d889b1555760361ce968 KRMA-860: log whole-file rehashes so a stall on the main actor names itself
- 0b152709dc116a1db407b6fd411d04f08e6a8528 KRMA-860: reuse a browsing asset's content hash instead of rehashing the file on the main actor

### Comment — human @ 2026-10-11T13:30:58.686Z

Release capture 2026-10-11 (M4 Pro, macOS 27.2, 873684f2, --no-trace): main-actor before first suspension p95 1.47 ms (budget <= 3 ms). Recorded in docs/TESTING.md. Report: /tmp/kromora-capture/KRMA860-nt-run1-DSC01019-20261011-073013-report.jsonl

## Agent log

- 2026-10-11T01:42:22.411Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Identify the regression cause and offending code path (pass) — Package date precision and browsing placeholder signatures caused whole-file SHA-256 rehashes on main-actor ImageSource construction; the fixes address both paths.
- [ ] After the fix, three direct runs show median p95 <= 3 ms, or document why the budget cannot hold on this hardware (fail) — The issue records a three-switch dev-build timeline with 2.8 ms selection sync, but not the required three direct Release p95 measurements. Existing guidance limits this ticket to one display-bound series of three, already used for the pre-fix measurements.
- [ ] Update docs/TESTING.md with the post-fix measured state (fail) — The current measured-state section still calls the 99 ms regression probable and contains no post-fix measured-state results.
Checks run:
- swift test --filter ImageSourceIdentityReuseTests: passed, 4 tests; 0 failures
- Independent source and lifecycle review: verified tolerant snapshot comparison, real identity reuse for browsing observations, legacy placeholder hashing, and off-main materialized record refresh
Findings:
- Blocking: required post-fix Release p95 evidence and its docs/TESTING.md measured-state entry are missing; the current dev-build timeline does not establish the specified median p95 acceptance criterion.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV35PFW2QAL2527B
Summary: Cause and fixes verified; post-fix Release p95 acceptance evidence and measured-state documentation remain incomplete.
