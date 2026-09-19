---
id: KRMA-453
title: Keep on-screen RAW probes alive across a failed open
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Documented investigation comment reproducing or disproving the stuck-.probing failure mode on current main
      result: pass
      notes: "codex's 2026-09-19T01:51:08Z comment documents the investigation: AppViewModel's load() eagerly clears rawCapabilities/metadata/activeAssetID for the outgoing source before begin() runs, so a failed open surfaces as an empty/failed state rather than a visibly-stuck-probing RAW. The underlying cancel-at-begin hazard inside SourceSessionCoordinator itself was confirmed independently of that masking behavior."
    - criterion: Cancellation changed so on-screen source probes survive a failed open; cancel/replace only on successful prepare
      result: pass
      notes: begin() no longer cancels metadataTask/capabilitiesTask up front (SourceSessionCoordinator.swift:109-113). Cancellation of the previous probes now happens only at the refresh site, right before onPreparation fires for a newly-succeeded request (SourceSessionCoordinator.swift:200-204), gated by a new isExpected() check distinct from isCurrent().
    - criterion: At most one capabilities probe and one metadata read in flight for the active source; successful open supersedes previous probe's answer
      result: pass
      notes: startMetadata/startCapabilities each cancel their own prior task before starting a new one. publishedRequest tracks the last successfully-admitted request; a new successful prepare replaces it and cancels the old probes. Verified directly by testSuccessfulOpenSupersedesThePreviousProbe.
    - criterion: Metadata publication tied to a stored task handle with currency check before publishing
      result: pass
      notes: startMetadata now stores the detached read itself in metadataTask (previously an unstored Task.detached raced inside a stored wrapper task). publishMetadata() checks isCurrent(request) (publishedRequest == request) and !Task.isCancelled before calling onMetadata.
    - criterion: "Automated regression coverage: good-then-failing-source keeps prior state unstuck, plus the converse supersede-on-success case"
      result: pass
      notes: SourceSessionCoordinatorTests.testFailedOpenKeepsPublishedSourceProbesAlive and testSuccessfulOpenSupersedesThePreviousProbe (added in d4b2b48) cover both directions directly against the coordinator, gating a probe via FakeRenderEngine to force the race window.
    - criterion: No Swift 6 isolation regressions; CIImage/CIRAWFilter stay inside the engine boundary
      result: pass
      notes: swift build succeeds with zero new diagnostics; no @unchecked Sendable/nonisolated(unsafe)/@preconcurrency introduced. The change only touches Sendable Request/ImageMetadata values and task lifecycle; CIImage/CIRAWFilter are untouched.
  checks_run:
    - swift build
    - swift test --filter SourceSessionCoordinatorTests (4/4 pass)
    - swift test --filter DevelopInspectorTests (34 executed, 2 skipped for missing local RAW fixture, 0 failures)
    - git diff --check (clean)
    - ./scripts/ci-tests.sh fast (one pre-existing unrelated failure investigated below)
  findings:
    - "AppViewModel's own onMetadata/onCapabilities gating compares against the live (monotonically-advancing) sourceSession.sourceRevision rather than the last successfully-published revision, so a late-arriving probe for a superseded request is dropped at the AppViewModel layer even after this fix lets it survive inside SourceSessionCoordinator. Scenario: Not currently reachable: AppViewModel.load() always synchronously reassigns activeAssetID and blanks metadata/rawCapabilities for the new target before calling begin(), for every navigation, success or failure. So there is today no code path where AppViewModel keeps displaying a previous asset while a later request is pending/failing. This is purely a latent layering note, not an active bug — flagging for awareness if AppViewModel's teardown-on-navigate behavior ever changes. Verdict: PLAUSIBLE"
    - "EffectsInspectorTests.testBindingsRoundTripAndIndividualResetsPreserveOtherEffects fails deterministically (41.0 vs 40.0) on main, unrelated to this change. Scenario: Reproduced on HEAD (d4b2b48) with the KRMA-453 diff fully applied and also independently by stashing all unrelated in-progress working-tree changes — the failure is present in committed history, in an unrelated Effects slider area, not touched by this ticket's diff. Verdict: CONFIRMED"
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-19T01:58:32.722Z
  session: 01MU7QE5YQO50JNDDZ
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - raw
  - develop
  - correctness
  - source-session
created: 2026-09-18T22:38:55.078Z
updated: 2026-09-19T01:58:32.724Z
order: a0
board: product
---

## Objective

Ensure RAW capability (and metadata) probes that describe the **photo still on screen** are not cancelled by a subsequent open that ultimately fails — so Develop does not spin forever on `.probing` after stepping onto an unreadable file.

## Context

### Upstream bug (B15)

LUTzy `fdcf2b1` / `LoadCancellationTests`:

- `load()` cancelled probe tasks **up front**, before knowing whether the new file would decode.
- Cancelling work for the *incoming* image is correct.
- Cancelling work that still describes the *currently displayed* image is wrong when the new open fails: failure never publishes a replacement source and never restarts the probe.
- Symptom: within the ~25–170 ms probe window, step onto an unreadable file → `rawCapabilities` stays nil with `sourceIsRAW == true` → develop panel stuck in `.probing` until another successful open.
- Rule they adopted: **cancel at the refresh site, not the load-start site.** The refresh site is the only place that knows a replacement is actually coming. Metadata had the same bug (unstored `Task.detached` races).

### Current Kromora shape

`Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift`:

- `begin(...)` immediately cancels `metadataTask`, `capabilitiesTask`, `firstFrameTask`, and `storedLoadTask` when a new request starts.
- `prepare` only calls `startMetadata` / `startCapabilities` after a **successful** `engine.prepareSource`.
- On `preparation == nil`, it publishes `onFailure` and does **not** restart probes for the previous source.

Whether this reproduces depends on AppViewModel failure UX:

- If a failed open **keeps** the previous `imageSource` / selection visible but capabilities were cleared at `begin` → same forever-probe bug.
- If a failed open **clears** the selection into an empty/failed state and resets RAW flags → different UX; still verify no stuck `.probing` and no stale metadata publish from a racing task.

Also note `AppViewModel` clears `rawCapabilities = nil` / `capabilitiesProbeCompleted = false` on source teardown paths — confirm failure handling does not leave Develop claiming “probing” for a still-visible RAW.

### Related ticket

- KRMA-452 makes garbage RAW-named files fail at decode (good failure fixture for this test). Prefer depending on that behavior conceptually; this ticket may still use any prepare failure (missing file, unsupported type) as the trigger.

## Acceptance criteria

- [ ] Documented investigation comment on the issue **or** in code: reproduce or disprove the stuck-`.probing` failure mode on current `main` with a failing open while a RAW is displayed.
- [ ] If reproduced (or if analysis shows the cancel-at-begin hazard remains): change cancellation so probes for the on-screen source survive a failed open; only cancel/replace them when a new source is **successfully** prepared / published.
- [ ] At most one capabilities probe and one metadata read in flight for the active source; a successful open must still supersede the previous probe’s answer (pin the converse — “never cancel” is not an acceptable fix).
- [ ] Metadata publication must be tied to a stored task handle and checked for currency/`isCurrent(request)` before publishing (no unstored detached race onto the wrong Info panel).
- [ ] Automated regression coverage opens a good source then a failing source and asserts develop/capabilities state for the still-relevant source (or empty/failed UI) is not stuck in probing; plus the converse supersede-on-success case.
- [ ] No Swift 6 isolation regressions; keep `CIImage`/`CIRAWFilter` inside the engine boundary.

## Out of scope

- Reworking the entire source-session architecture.
- Changing Develop control semantics unrelated to probe lifecycle.
- Implementing KRMA-452 (but using its corrupt `.dng` fixture once available is encouraged).

## Implementation notes

1. Start by writing the failing test against current behavior — if it already passes, record evidence in the completion comment and close with no code change (or only a clarifying comment/guard).
2. Likely fix shape: defer `capabilitiesTask`/`metadataTask` cancel until `onPreparation` success for the new request; on failure, leave prior publication intact **or** explicitly re-issue probes for the still-current source revision.
3. Watch `AppViewModel` hooks (`onCapabilities`, `onFailure`, source clear at ~1853) so UI state machines (`DevelopPanelState`) stay consistent.
4. Prefer extending `SourceSessionCoordinator` tests / load-cancellation style tests over UI snapshot tests.
5. Upstream `LoadCancellationTests` is a good behavioral checklist, not a file to copy.

## Verification

- Focused source-session / develop-panel / image-loading tests.
- `swift build`
- `git diff --check`
- Mention in the handoff comment whether the bug was confirmed on Kromora or already absent.

### Comment — cursor @ 2026-09-18T22:40:12.814Z

Provenance: upstream B15 from fdcf2b1 / LoadCancellationTests — cancel probes at refresh/success, not at load-start, or a failed open leaves Develop stuck probing the still-visible RAW. First write a regression test; if current Kromora already passes, document evidence and close without a drive-by rewrite.

### Comment — codex @ 2026-09-19T01:51:08.299Z

Investigation confirmed the cancel-at-begin hazard in SourceSessionCoordinator: a gated RAW capability probe for the successfully prepared source was canceled/suppressed when a later prepare failed. Current AppViewModel clears the failed-open surface, so its failure UX is empty/failed rather than visibly stuck, but the coordinator could still strand the displayed source's probe and metadata lifecycle. Fixed in d4b2b48: retain published-source probe/read handles across pending opens, replace them only after successful preparation, keep metadata in a stored task with currency checks, and guard AppViewModel publications by source revision/asset. Added failed-open preservation and successful-supersession regressions. Checks: swift test --filter SourceSessionCoordinatorTests; swift test --filter DevelopInspectorTests (34 executed, 2 skipped for missing local RAW); swift build; git diff --check; dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-19T01:58:32.722Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Documented investigation comment reproducing or disproving the stuck-.probing failure mode on current main (pass) — codex's 2026-09-19T01:51:08Z comment documents the investigation: AppViewModel's load() eagerly clears rawCapabilities/metadata/activeAssetID for the outgoing source before begin() runs, so a failed open surfaces as an empty/failed state rather than a visibly-stuck-probing RAW. The underlying cancel-at-begin hazard inside SourceSessionCoordinator itself was confirmed independently of that masking behavior.
- [x] Cancellation changed so on-screen source probes survive a failed open; cancel/replace only on successful prepare (pass) — begin() no longer cancels metadataTask/capabilitiesTask up front (SourceSessionCoordinator.swift:109-113). Cancellation of the previous probes now happens only at the refresh site, right before onPreparation fires for a newly-succeeded request (SourceSessionCoordinator.swift:200-204), gated by a new isExpected() check distinct from isCurrent().
- [x] At most one capabilities probe and one metadata read in flight for the active source; successful open supersedes previous probe's answer (pass) — startMetadata/startCapabilities each cancel their own prior task before starting a new one. publishedRequest tracks the last successfully-admitted request; a new successful prepare replaces it and cancels the old probes. Verified directly by testSuccessfulOpenSupersedesThePreviousProbe.
- [x] Metadata publication tied to a stored task handle with currency check before publishing (pass) — startMetadata now stores the detached read itself in metadataTask (previously an unstored Task.detached raced inside a stored wrapper task). publishMetadata() checks isCurrent(request) (publishedRequest == request) and !Task.isCancelled before calling onMetadata.
- [x] Automated regression coverage: good-then-failing-source keeps prior state unstuck, plus the converse supersede-on-success case (pass) — SourceSessionCoordinatorTests.testFailedOpenKeepsPublishedSourceProbesAlive and testSuccessfulOpenSupersedesThePreviousProbe (added in d4b2b48) cover both directions directly against the coordinator, gating a probe via FakeRenderEngine to force the race window.
- [x] No Swift 6 isolation regressions; CIImage/CIRAWFilter stay inside the engine boundary (pass) — swift build succeeds with zero new diagnostics; no @unchecked Sendable/nonisolated(unsafe)/@preconcurrency introduced. The change only touches Sendable Request/ImageMetadata values and task lifecycle; CIImage/CIRAWFilter are untouched.
Checks run:
- swift build
- swift test --filter SourceSessionCoordinatorTests (4/4 pass)
- swift test --filter DevelopInspectorTests (34 executed, 2 skipped for missing local RAW fixture, 0 failures)
- git diff --check (clean)
- ./scripts/ci-tests.sh fast (one pre-existing unrelated failure investigated below)
Findings:
- AppViewModel's own onMetadata/onCapabilities gating compares against the live (monotonically-advancing) sourceSession.sourceRevision rather than the last successfully-published revision, so a late-arriving probe for a superseded request is dropped at the AppViewModel layer even after this fix lets it survive inside SourceSessionCoordinator. Scenario: Not currently reachable: AppViewModel.load() always synchronously reassigns activeAssetID and blanks metadata/rawCapabilities for the new target before calling begin(), for every navigation, success or failure. So there is today no code path where AppViewModel keeps displaying a previous asset while a later request is pending/failing. This is purely a latent layering note, not an active bug — flagging for awareness if AppViewModel's teardown-on-navigate behavior ever changes. Verdict: PLAUSIBLE
- EffectsInspectorTests.testBindingsRoundTripAndIndividualResetsPreserveOtherEffects fails deterministically (41.0 vs 40.0) on main, unrelated to this change. Scenario: Reproduced on HEAD (d4b2b48) with the KRMA-453 diff fully applied and also independently by stashing all unrelated in-progress working-tree changes — the failure is present in committed history, in an unrelated Effects slider area, not touched by this ticket's diff. Verdict: CONFIRMED
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU7QE5YQO50JNDDZ
Summary: Verified KRMA-453: SourceSessionCoordinator no longer cancels metadata/capabilities probes for the on-screen source at begin(); cancellation now happens only at the refresh site after a new source successfully prepares. Coordinator-level regression tests (failed-open-preserves-probe, successful-open-supersedes-probe) pass, build is clean, no Swift 6 isolation regressions. Noted a latent (currently unreachable) layering gap in AppViewModel's own revision-gating, and an unrelated pre-existing EffectsInspectorTests failure outside this ticket's scope.
