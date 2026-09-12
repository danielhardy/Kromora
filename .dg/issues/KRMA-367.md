---
id: KRMA-367
title: Recognize SD card media plugged in after app launch
type: feature
status: done
priority: medium
created: 2026-09-12T01:42:10.366Z
updated: 2026-09-12T02:37:08.367Z
order: a0
board: product
commits:
  - ae7310f
---

## Objective

Recognize SD card media when an SD card is plugged in after Kromora is already open.

## Context

Kromora should notice and make newly mounted SD card media available without requiring an app restart.

## Acceptance criteria

- [ ] Detect an SD card volume mounted after app launch.
- [ ] Make the newly connected SD card media available in the app without restarting Kromora.
- [ ] Preserve existing behavior for media already connected at app launch.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-12T02:18:41.552Z

## Cause analysis

Primary cause identified: removable-volume discovery is one-shot from the UI lifecycle. ContentView calls refreshRemovableMedia() only from onAppear (Sources/KromoraKit/Views/ContentView.swift:61-63). refreshRemovableMedia() calls provider.discover() and publishes the result, but nothing invokes it when a volume is mounted later (Sources/KromoraKit/ViewModels/AppViewModel.swift:2237-2246). The Import menu displays the cached removableMediaVolumes and offers only a manual Refresh action (ContentView.swift:306-319). KromoraApp/AppDelegate has no NSWorkspace mount/unmount observer or activation/scene refresh hook. Therefore an SD card inserted after launch will remain absent until the user manually refreshes or restarts the app.

Likely secondary causes to distinguish during QA:

- If the card appears after Refresh but is labeled Access needed, this is the expected App Sandbox permission path, not the lifecycle bug. The packaged entitlements include com.apple.security.files.removable-media.read-only, and the provider preserves unreadable removable volumes for the Open-panel grant flow (Sources/Kromora/Kromora.entitlements:9; Sources/KromoraKit/Models/MediaVolume.swift:183-195).
- If the card appears but contains no selectable images, discovery intentionally requires a supported/readable image extension for readable volumes and skips hidden files; scan also rejects unsupported/damaged files (MediaVolume.swift:187 and 200 onward). This can explain a card-specific result, but not why a newly mounted supported card is missing from the menu entirely.
- Discovery and scan are asynchronous and cancellable, but cancellation is only triggered by another explicit discovery/import action. There is no mount-triggered task to race with, so this is not the primary explanation for the reported after-launch behavior.

Evidence:

- Existing MediaVolumeImportTests pass: 6 tests, 0 failures. They cover explicit discovery, scanning, empty state, permission labeling, bookmark recovery, and import, but no simulated post-launch mount notification.
- Static search found no NSWorkspace mount notification, didMount/didUnmount observer, scenePhase hook, or application-activation refresh associated with removable media.

Recommended fix direction: add a lifecycle-owned NSWorkspace notification observer for didMountNotification (and didUnmountNotification to remove stale entries), route events to a debounced main-actor refresh, and retain activation/manual refresh as a fallback. Add an injected notification/lifecycle seam and a regression test proving a volume mounted after initial discovery appears without restart. No source changes made in this analysis pass.

### Comment — codex @ 2026-09-12T02:25:11.674Z

Follow-up split out as KRMA-370: Release removable-media security scope after import to support clean eject. KRMA-367 remains focused on detecting cards mounted after app launch; KRMA-370 tracks releasing the collection-owned security-scoped access after copied imports.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T02:37:08.365Z: Added AppViewModel-owned NSWorkspace mount/unmount observation with 200 ms debounced discovery, app-activation fallback refresh, explicit observer/task shutdown cleanup, and an injected notification-center regression test proving a card mounted after initial discovery appears without restart. Verified MediaVolumeImportTests (7/7), swift build -c release, git diff --check, and dg validate.
