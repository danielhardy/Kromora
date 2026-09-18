---
id: KRMA-453
title: Keep on-screen RAW probes alive across a failed open
type: bug
status: ready
priority: medium
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
updated: 2026-09-18T22:40:12.815Z
order: w
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
