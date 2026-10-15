# Kromora release readiness and quality review — 2026-10-14

**Reviewed snapshot:** `main`, `312f0537c4e388fc46fe05e01458668b7097fa1f`. This document is the assessment. Tickets were filed afterward and are mapped below; they are not a change to product scope. Current product scope remains in [PRODUCT_SCOPE.md](../docs/PRODUCT_SCOPE.md).

Tracking epic: [KRMA-994](../.dg/issues/KRMA-994.md). Must-fix work is KRMA-995 through KRMA-1001. Findings that already had a ticket were updated in place and remain children of the 2026-10-13 epic [KRMA-922](../.dg/issues/KRMA-922.md).

## Assessment

Kromora has a credible product architecture, substantial regression coverage, and considerably better engineering foundations than a typical prerelease application. The separation of canonical package data from disposable projections, shared rendering pipeline, explicit task shutdown, and attention to stale-result fencing are real strengths. The recent progress is visible in both code and passing verification.

**I would not approve this snapshot for public v1 release yet.** There are reproducible failures in batch export, culling persistence, selection, and recovery preconditions, plus a thumbnail-retention problem that undermines long-session stability. These concern the ordinary trust contract of a photo editor, rather than missing competitor features. They should be addressed before release.

The higher aspiration—instant, precise, exceptionally polished native interaction—also remains ahead of the evidence. Warm navigation still misses the recorded responsiveness targets, retouch quality is weak on the documented synthetic corpus, and there is no current end-to-end signed-app qualification in this review. Passing the test suite establishes a strong foundation; it does not establish that the whole product meets that aspiration.

| Area | Assessment |
| --- | --- |
| Architecture and code quality | Strong foundations; ownership is substantially improved, but some workflows still bypass their intended authority or lifecycle. |
| Data integrity and correctness | Good transaction/persistence machinery with important holes at orchestration and failure boundaries. Resolve findings 1–6 before public release. |
| Performance | Thoughtful renderer and scheduling design; navigation latency, retained thumbnails, export memory, and remaining synchronous I/O need attention. |
| Image quality | Shared pipeline is a major advantage. Retouch needs a stronger acceptance bar; sRGB preview is an explicit ceiling on wide-gamut fidelity. |
| Native UI and transitions | Good platform direction, focus routing, accessibility work, and Reduce Motion support in important surfaces. Some behavior and motion policies remain inconsistent. Visual excellence is not established by this static review. |
| Release verification | Required local tests and packaging checks pass. Developer/distribution signing, TestFlight, macOS 26 runtime behavior, and complete sandbox acceptance remain separate qualifications. |

Effort estimates were deliberately excluded. Priorities below reflect user impact, correctness, and the quality bar requested.

## Scope, method, and verification

The tree contains **269 Swift source files, approximately 89,939 Swift source lines**. This was a broad, risk-directed review, not a claim that every line was exhaustively audited. I read the canonical project guidance and reviewed the current product/architecture/storage/testing/release guides, render and presentation boundaries, package/session/transaction code, persistence, browsing/selection, export/share, launch/termination, representative views, and relevant tests. I compared yesterday's review with current implementation; there have been 70 commits since its reviewed snapshot.

The pre-existing changes were confined to `.dg/.project/events.jsonl` and issues `KRMA-963`, `KRMA-965`, `KRMA-967`, and `KRMA-991`. They were preserved. No product implementation was changed. Temporary test probes were added solely to verify findings and removed afterward; this report is the only retained task artifact.

Verification host: **Apple M4 Pro Mac mini, 48 GB, macOS 27.2 (26B5112a), Xcode 27.0 beta (27A5252f), Swift 6.4**. The product deployment floor remains macOS 26 / Apple Silicon.

| Check | Result and limits |
| --- | --- |
| `scripts/ci-tests.sh warning-gate` | **Pass**, 30.5 s. Sources and tests build with Swift warnings promoted to errors. |
| `scripts/ci-tests.sh fast` | **Pass**, 1,908 required tests, 152.3 s including lane discovery/build. |
| `scripts/ci-tests.sh serial` | **Pass**, 561 tests, zero failures; 209.6 s test time, 213.1 s command time. |
| Lane discovery | 2,522 tests: 1,908 fast, 561 serial, 53 optional. Optional RAW/benchmark methods were not run. |
| `scripts/app-store-build.sh` | **Pass**, 157.5 s. Release app, bundled Looks/resources, icon, strict signature, and five expected sandbox entitlements verified. The resulting executable is arm64 only. |
| Signing qualification | The verified app is **ad hoc signed**, with no TeamIdentifier. This is packaging evidence, not Apple Developer signing, TestFlight, or App Store validation. Xcode emitted its App Intents metadata-extraction warning; the Swift warnings-as-errors build above was clean. |
| Six disposable-fixture probes | All six confirmed the behaviors described below. Their passing assertions describe observed defects/retention, not product acceptance. Evidence is reproduced near the end of this report. |
| Display-bound benchmarks | Not rerun, following `CLAUDE.md`. The dated measurements below come from `docs/TESTING.md`. |
| Hands-on qualification | No full interactive sandbox, real sharing-service, Photos-permission, external-volume, VoiceOver, or visual-transition pass was performed. No TestFlight upload or user-library manipulation was performed. |
| Remote CI | Not queried. Local `main` and its locally recorded upstream were equal; this is not proof of current remote CI status. |

Build/test logs for this session are `/tmp/kromora-review-2026-10-14-{warning-gate,fast,serial,package,probes}.log`. These are temporary diagnostics, not durable release evidence.

## Improvements since the previous review

Several findings in [the 2026-10-13 review](2026-10-13-release-readiness-review.md) no longer describe this snapshot:

- The Metal view now sets its color space explicitly: [PreviewSurface.swift:1180](../Sources/KromoraKit/Views/PreviewSurface.swift#L1180). The previous missing canvas color-tag finding is resolved at the implementation level; this does not establish wide-gamut preview support.
- Undo/Redo moved to the standard group with field-editor routing and meaningful photo action names. Focused menu availability is implemented. [MenuCommands.swift](../Sources/KromoraKit/Views/MenuCommands.swift)
- `AppViewModel` and supporting state now use Observation; root notification fan-in is removed, and body/invalidation tests protect narrower subscriptions. [ObservationInvalidationTests.swift](../Tests/KromoraKitTests/ObservationInvalidationTests.swift), [ObservationBodyBaselineTests.swift](../Tests/KromoraKitTests/ObservationBodyBaselineTests.swift)
- Library opening is asynchronous, and computer-name resolution no longer uses the previous `Host.current()` approach. [AppLaunch.swift](../Sources/KromoraKit/Presentation/AppLaunch.swift), [PackageOpening.swift](../Sources/KromoraKit/Models/PackageOpening.swift), [DeviceName.swift](../Sources/KromoraKit/Models/DeviceName.swift)
- Culling writes coalesce by asset and commit by shard off the main actor. Virtual-copy and removal transactions also have worker paths; the writer mutation boundary now uses a serial queue rather than holding an unfair lock around full transactions. [PortableLibrarySession.swift](../Sources/KromoraKit/Models/PortableLibrarySession.swift), [PortablePackageTransaction.swift:202](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L202)
- Native panels generally use asynchronous sheets. Quit confirmation covers batch exports and imports. [SheetPresenting.swift](../Sources/KromoraKit/Presentation/SheetPresenting.swift), [TerminationGuard.swift](../Sources/KromoraKit/Presentation/TerminationGuard.swift)
- Share now presents immediately from a control anchor and lazily renders a bounded-size HEIC/JPEG representation. [ExportWorkflowCoordinator.swift](../Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift)
- Grid rows have asset-based identity, bounded row construction, and `onScrollGeometryChange`. Yesterday's row-index/continuous-offset criticisms should not be repeated. [LibraryGridView.swift:93](../Sources/KromoraKit/Views/LibraryGridView.swift#L93)
- Backup/restore is explicitly post-MVP, the unsupported Finder document-opening claim was removed, and Settings can choose a library for the next launch. This is a legitimate scope decision, not a missing v1 feature to quietly reinstate.
- Both required test lanes and the Swift warning gate passed today. Yesterday's failing gate is not a current failure claim.

## Findings to resolve before public release

### 1. P1 — Batch export applies the active photo's edits to untouched photos and hides unreadable edits

**Ticket:** [KRMA-995](../.dg/issues/KRMA-995.md).

**Confirmed with two disposable-fixture probes.** `ExportCoordinator.resolvedDocument` reduces the load outcome to `found`. Every missing result becomes the caller's fallback document, whether the photo has never been edited or its stored edit is corrupt/unreadable. [ExportCoordinator.swift:815](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L815)

The production caller supplies the **active photo's document and Look** as that fallback. Unopened items have no in-memory document and therefore take this path. [AppViewModel.swift:4102](../Sources/KromoraKit/ViewModels/AppViewModel.swift#L4102)

For example: edit photo A to +2 EV; select A and an untouched, unopened B; batch export. B can receive A's +2 EV instead of neutral edits. If B's saved revision is damaged, it can also receive A's edits and count as successfully exported. The probes verified both variants: one output, zero failures, fallback exposure `2.0`.

The store already distinguishes a healthy missing revision from an actionable failure. Prefetch even uses that distinction, but export discards it. [EditDocumentStore.swift:310](../Sources/KromoraKit/Models/EditDocumentStore.swift#L310), [EditDocumentLoadResult.isUsableForPrefetch](../Sources/KromoraKit/Models/EditDocumentStore.swift#L75)

**Required outcome:** a healthy package asset with no saved edit exports a neutral document; an unreadable/corrupt edit fails that item with an actionable explanation. Applying the active edit to multiple photos must be an explicit operation. Missing Look dependencies must likewise be surfaced rather than silently described as a fully reproduced edit. Cover mixed edited/untouched/unreadable selections and lazy multi-photo Share, which uses the same resolution helper.

### 2. P1 — Failed rating/flag writes stop being dirty, and quit can report success

**Ticket:** [KRMA-996](../.dg/issues/KRMA-996.md).

**Confirmed with a disposable-fixture probe.** The culling drain removes its batch from `pendingLibraryStateUpdates` before writing. On failure it reports an error but does not restore the batch, revert the optimistic UI, or retain a failed-write result. A later flush has nothing to retry. [PortableLibrarySession.swift:1874](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L1874), [PortableLibrarySession.swift:1944](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L1944)

The browsing coordinator has already updated the visible state; its failure callback only presents an error. [LibraryBrowsingCoordinator.swift:551](../Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift#L551)

`flushPendingLibraryState()` returns `Void`, and the app's termination flush returns only the edit-document persistence result. Thus failed culling cannot participate in Retry Saving / Quit Without Saving. [AppViewModel.swift:4224](../Sources/KromoraKit/ViewModels/AppViewModel.swift#L4224)

The probe made a disposable membership shard unreadable, queued rating 4, waited for the reported failure, repaired the shard, and flushed again. The durable rating remained 0.

**Required outcome:** culling has the same dirty/retry/flush contract as edit persistence. Retain the latest failed values without overwriting newer intent; return a meaningful flush result; make quit honor it. Handle partial success across shards explicitly so successful commits remain visible and unsuccessful ones remain recoverable. Add transient write-failure and retry tests, beyond the existing “error reported once” test.

### 3. P1 — Expired-writer recovery mutates transactions before validating recovery ownership

**Tickets:** [KRMA-997](../.dg/issues/KRMA-997.md) (ownership before rollback), [KRMA-998](../.dg/issues/KRMA-998.md) (directory durability failures).

**Ordering defect confirmed with a low-level probe; a two-process race was not reproduced.** `recoverExpiredWriter` invokes transaction recovery first, then calls `breakExpired`, which is where the current lease expiry is checked. [PortablePackageTransaction.swift:278](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L278)

Calling this helper with an unexpired lease and a staged transaction removes the transaction journal/staging and only afterward throws contention. The probe verified that behavior on a disposable package. Rejecting takeover must not first alter the current writer's transaction.

The production path first observes an expired lease in a separate acquisition attempt. That observation is not exclusive recovery ownership. Another opener/recoverer, or a renewal already in flight, can change the situation before recovery runs. The same-session serial queue does not coordinate different processes. [PortableLibrarySession.swift:260](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L260), [PortablePackageTransaction.swift:292](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L292)

**Required outcome:** recovery acquires exclusive interprocess ownership, validates the exact lease owner and recovery eligibility, then replays journals under that fence. A failed precondition must have zero mutation. A demonstrably live local writer should not be rolled back merely because a timestamp expired. Add two-process contention, renewal/takeover overlap, and crash-point tests in addition to in-process fault injection.

**Related durability weakness:** `fullSyncDirectory` returns silently if opening the directory fails and ignores the `fsync` result despite its throwing signature. The transaction cannot accurately report that persistence failed. Propagate genuine durability failures and test them. This is code evidence, not a claim that power-loss corruption was observed. [PortablePackageTransaction.swift:1232](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L1232)

### 4. P1 — Scrolling can retain every visited photo's decoded thumbnails

**Ticket:** [KRMA-999](../.dg/issues/KRMA-999.md). The 16 GB soak is part of [KRMA-1016](../.dg/issues/KRMA-1016.md), not this code ticket.

**Ownership behavior confirmed with a disposable-fixture probe; large-library resident memory was not measured.** Each collection item strongly retains original, edited, and displayed thumbnail references. Loading later pages appends items. `releaseThumbnail(for:)` removes demand and cancels some unfinished work, but retains already loaded images; it returns early when a thumbnail exists. [ImageCollection.swift:57](../Sources/KromoraKit/Models/ImageCollection.swift#L57), [ImageCollection.swift:679](../Sources/KromoraKit/Models/ImageCollection.swift#L679), [ImageCollection.swift:851](../Sources/KromoraKit/Models/ImageCollection.swift#L851)

The probe confirmed that both original and edited images remain attached after release and that paging accumulates items. Lazy SwiftUI row construction bounds hosted views, not those retained pixel buffers. The thumbnail provider's 32 MB cache does not bound references retained elsewhere. [Thumbnails.swift:39](../Sources/KromoraKit/Models/Thumbnails.swift#L39)

For scale, 1,000 pairs of distinct 1200×800 RGBA8 images represent approximately **7.2 GiB of raw pixels**, before other allocations. This is a sizing example, not a measured footprint; sharing, lazy decoding, source dimensions, and actual formats affect residency. Nevertheless, the ownership grows with session traversal rather than viewport size.

**Required outcome:** bound decoded thumbnails across all owners. Retain lightweight identity/metadata for arbitrary library positions, but keep pixels in a costed working set for visible cells and a small navigation neighborhood. Evict offscreen item references while preserving durable thumbnail frames. Verify a complete scroll through thousands of edited photos and back, under memory pressure on a 16 GB Apple Silicon Mac; memory should plateau and revisits should hydrate without unnecessary rendering.

### 5. P1 — Export operation ownership is incomplete, especially repeated export and quit

**Ticket:** [KRMA-1000](../.dg/issues/KRMA-1000.md). Extends the batch/import quit confirmation already shipped in KRMA-946.

**Confirmed by source tracing; overlapping-export runtime behavior was not separately exercised.** A new single export overwrites `singleTask` without rejecting, cancelling, or retaining the previous task. The previous task's unconditional defer can subsequently clear the newer handle. `isExporting` is also shared rather than derived from active jobs. [ExportCoordinator.swift:283](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L283)

The sheet guard only prevents a second sheet while one is presented. Export menu availability has no active-export condition, so another export can start once the first sheet closes. Shutdown cancels/awaits only the currently stored single and batch handles. [MenuCommandAvailability.swift](../Sources/KromoraKit/ViewModels/MenuCommandAvailability.swift), [ExportCoordinator.swift:485](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L485)

There are additional unowned operations: original-plus-settings export spawns an inner task, lazy Share creates provider tasks without registering them, and `ExportWorkflowCoordinator` has no shutdown barrier. Item providers return no `Progress` cancellation handle. These jobs are outside the app's otherwise careful task-lifetime design. [ExportWorkflowCoordinator.swift:194](../Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift#L194), [ExportWorkflowCoordinator.swift:300](../Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift#L300)

Quit confirmation only includes **batch** exports. A single export, Share render, or original bundle can be interrupted without being represented in the decision. [AppViewModel.swift:780](../Sources/KromoraKit/ViewModels/AppViewModel.swift#L780)

**Required outcome:** give every accepted export/share/bundle/handoff a durable operation identity, immutable input snapshot, owned task, progress/cancellation state, and terminal outcome. Derive UI activity and quit confirmation from that inventory. Either explicitly serialize repeated commands or support multiple jobs correctly. Drain accepted operations or obtain a truthful cancellation decision before releasing library access or terminating. Test old-job completion after a new job starts, cancellation during write, and quit during each export type.

### 6. P1 — Select All bypasses the authoritative selection and only covers loaded items

**Ticket:** [KRMA-1001](../.dg/issues/KRMA-1001.md). Page-order caching is the separate ticket [KRMA-1012](../.dg/issues/KRMA-1012.md).

**Confirmed with a three-photo, two-item-page probe.** The responder's Select All action calls `collection.selectAll()`, which selects only `filteredItems` already materialized in the collection. It does not call the package controller's existing `selectAllPortable(query:)`. [KeyboardSurface.swift:52](../Sources/KromoraKit/Views/KeyboardSurface.swift#L52), [ImageCollection.swift:864](../Sources/KromoraKit/Models/ImageCollection.swift#L864), [PortableLibrarySession.swift:841](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L841)

The probe selected two loaded items out of a three-photo library while the package authority still had one selected. Synchronization then collapsed the collection selection back to that one item. Batch requests also derive from materialized `collection.selectedItems`. [ImageCollection.swift:712](../Sources/KromoraKit/Models/ImageCollection.swift#L712), [AppViewModel.swift:4080](../Sources/KromoraKit/ViewModels/AppViewModel.swift#L4080)

**Required outcome:** one selection authority, independent of viewport/materialization. Select All should mean every match in the current query; bulk export, culling, copy/paste, and deletion should consume that authoritative selection in bounded chunks. Loading a page or synchronizing presentation must not alter selection intent. Cover cross-page selection, query changes, reload, and bulk operations without materializing all decoded images.

## Performance and image-quality work needed for the requested standard

### 7. Warm navigation still has a visible responsiveness gap

**Tickets:** [KRMA-1002](../.dg/issues/KRMA-1002.md) (window-independent profile; no new capture), [KRMA-952](../.dg/issues/KRMA-952.md) (human decision on the closed 50/100 ms budgets; depends on KRMA-1002).

The latest recorded Release evidence is a **single supervised 30-iteration M1 Pro run**, commit `aef050e8`, 16 GB, 60 MP ARW, backing viewport 2880×1794. It is not a fresh measurement made by this review. [TESTING.md:642](../docs/TESTING.md#L642)

| Metric | Recorded result | Interpretation |
| --- | ---: | --- |
| Warm Edit first pixel p95 | 286 ms | Misses the recorded 50 ms target. |
| Warm 30-cell grid re-entry p95 | 247 ms | Misses the recorded 100 ms target. |
| Main-actor selection before suspension p95 | 1.32 ms | Good; inside the target. |
| Cold grid hydration | 1,270 ms, one visit | Useful observation, not a percentile or established budget. |
| Warm navigation render admissions | 0 | More GPU optimization alone will not resolve this measured interval. |

The document notes that some presentation timestamps are callback-handler fallbacks. Those qualifications should travel with the numbers. The M4 Pro capture from October 11 reported 187–197 ms warm Edit p95 and 154–157 ms grid p95, under a different method; do not blend the two into a controlled hardware comparison.

Closing the old 50/100 ms work as won't-do does not make the interaction instant. For the requested standard, this remains a high-value product gap. Profile view mounting, layout, state publication, frame hydration, and drawable presentation separately; use the zero-render warm case to isolate the presentation path. Preserve critical canvas/inspector identity where the profile justifies it, and avoid reconstructing large subtrees on workspace changes.

Set acceptance targets for first meaningful pixels, usable controls, final-quality settlement, p99 frame gaps, and cancellation under rapid navigation. Judge pan/zoom/crop/mask interactions on both 60 Hz and ProMotion displays: frame periods are about 16.7 and 8.3 ms, respectively. Include backing-scale/display changes and thermal/low-power conditions. Existing structural tests are valuable, but zero renders or one confirmed frame is not a substitute for perceptual latency.

### 8. Retouch's passing tests do not establish acceptable repair quality

**Tickets:** [KRMA-1003](../.dg/issues/KRMA-1003.md) (shipping gate versus stress report), [KRMA-1004](../.dg/issues/KRMA-1004.md) (dust/speck repair after that gate). Camera-scale inspection is in [KRMA-1016](../.dg/issues/KRMA-1016.md).

The documented synthetic corpus reports **8/36 manual Heal**, **7/36 Clone**, and **5/36 automatic Heal** rows meeting its limits. Dust detection's small generated subset reports fixture recall **1/12**, despite high measured precision. The docs candidly describe these limitations. [RETOUCH.md](../docs/RETOUCH.md)

The key testing problem is that `testGroundTruthGateReportsCurrentHealAndCloneResults` asserts that Heal **must fail at least one case in every defect family** and only requires automatic Heal to pass more than zero rows. That is a behavior report, not a sufficient quality acceptance gate; a sufficiently large improvement could even break the failure-preservation assertion. [RetouchQualityEvaluationTests.swift:101](../Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift#L101)

These are tiny synthetic fixtures, not proof that real-camera retouch always fails. Conversely, green XCTest results are not evidence of camera-quality repairs. Wires and broad removal need not become v1 scope; the documented weakness also includes ordinary dust/speck on sky and skin-like backgrounds, directly relevant to the supported small-defect task.

**Recommendation:** establish acceptance for the supported defects using repeatable camera-scale crops and clean/damaged references where possible, backed by perceptual inspection. Preserve the stress corpus, distinguish expected hard cases from shipping acceptance, and gate meaningful per-class quality floors and regressions. Investigate source-patch choice, boundary continuity, structure preservation, and texture reconstruction rather than relaxing thresholds to green the dashboard.

### 9. Full-resolution export still creates avoidable memory peaks

**Ticket:** [KRMA-942](../.dg/issues/KRMA-942.md), updated in place. The 16 GB / 60–100 MP qualification stays on [KRMA-1016](../.dg/issues/KRMA-1016.md).

Export renders a full `CGImage`, encodes into `NSMutableData`, returns `Data`, and then writes it. For non-panel paths the write adds atomic staging around an already staged file. Serial batches limit concurrent items, which is good, but they do not bound one very large TIFF's raster-plus-encoded peak. [RenderEngine.swift:1198](../Sources/KromoraKit/Models/RenderEngine.swift#L1198), [ExportCoordinator.swift:714](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L714)

**Recommendation:** introduce a file/data-consumer encoding output so large encoded payloads need not all reside in memory. Image I/O already underlies the encoder. Preserve the shared pipeline, metadata/GPS policy, exclusive destination/collision semantics, security-scope ownership, and failure cleanup. Direct encoding does not eliminate the full raster or decoder intermediates; measure total process footprint and export/editing contention, not just `Data.count`. Qualify 60–100 MP sources and 16-bit TIFF on the lower-memory supported machines before claiming exceptional stability.

### 10. Some main-actor filesystem work remains after the worker migration

**Tickets:** [KRMA-1005](../.dg/issues/KRMA-1005.md) (lease renewal for virtual copy and removal), [KRMA-1006](../.dg/issues/KRMA-1006.md) (Settings validation and shutdown index write).

`createVirtualCopy` and `removeFromLibraryOffMain` still begin with main-actor `ensureWritableLease()`. That synchronously calls `lease.renew`, which reads the lock and durably replaces it, including full synchronization. The large transaction is off-main now; its preflight still is not. [PortableLibrarySession.swift:756](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L756), [PortableLibrarySession.swift:1253](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L1253), [PortableLibrarySession.swift:1745](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L1745), [PortablePackageTransaction.swift:320](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L320)

Settings' library choice also validates the full package synchronously on the main actor. Shutdown can write the whole disposable index synchronously. No timings for those remaining paths were measured here. [ActiveLibraryChooser.swift:63](../Sources/KromoraKit/Presentation/ActiveLibraryChooser.swift#L63), [ActiveLibrarySelection.swift:57](../Sources/KromoraKit/Models/ActiveLibrarySelection.swift#L57), [PortableLibrarySession.swift:732](../Sources/KromoraKit/Models/PortableLibrarySession.swift#L732)

**Recommendation:** keep UI preflight to in-memory state, then perform lease verification/renewal and package validation on the worker that owns the mutation. Maintain the authority checks at the actual write boundary. Verify slow external storage and contention, not only the internal SSD. Returning promptly while the actual write fails later is insufficient unless the dirty/retry contract in finding 2 is also correct.

### 11. Reduce repeated identity work and make allocation reuse evidence-driven

**Tickets:** [KRMA-954](../.dg/issues/KRMA-954.md) (structural identity plan, updated), [KRMA-953](../.dg/issues/KRMA-953.md) (shared hex helper, updated). Texture pooling stays [KRMA-963](../.dg/issues/KRMA-963.md), moved back to `backlog` until GPU-completion ownership is proven.

Render request/cache construction repeatedly JSON-encodes and SHA-256 hashes document, RAW, and mask values; hexadecimal conversion uses per-byte `String(format:)`. Large brush recipes amplify this CPU/allocation work on repeated interactions. [RenderCacheKey.swift:155](../Sources/KromoraKit/Models/RenderCacheKey.swift#L155), [RenderEngine.swift:214](../Sources/KromoraKit/Models/RenderEngine.swift#L214), [RenderEngine.swift:2285](../Sources/KromoraKit/Models/RenderEngine.swift#L2285), [RenderEngine.swift:2766](../Sources/KromoraKit/Models/RenderEngine.swift#L2766)

**Recommendation:** compute immutable identity once per relevant mutation; use revision/structural keys for session-local caches and stable digests for durable cross-launch identity. Do not persist Swift's randomized `Hasher` output or remove source/Look/pipeline-version fences. Measure large brush/mask recipes, since a neutral document benchmark will hide this cost.

Processing textures are allocated per completed render. A bounded texture pool may help if allocation shows up in profiles, but reuse must wait until GPU completion and all retained presentation references are finished. Pooling without that ownership protocol risks pixel corruption. [RenderEngineResources.swift:320](../Sources/KromoraKit/Models/RenderEngineResources.swift#L320)

### 12. Diagnostic storage grows with the whole session

**Ticket:** [KRMA-1007](../.dg/issues/KRMA-1007.md).

`ImageWorkScheduler.admissionLog` appends every admitted job without a retention limit. The production-default shared `FrameLookupLedger` also stores every lookup; its summaries scan the complete accumulated record list. [ImageWorkScheduler.swift:140](../Sources/KromoraKit/Models/ImageWorkScheduler.swift#L140), [Observability.swift:42](../Sources/KromoraKit/Models/Observability.swift#L42)

This is separate from pixel retention, and likely much smaller, but unnecessary lifetime growth is inconsistent with a stable long-running editor. Use cumulative counters plus a fixed ring buffer, or enable detailed capture only for an explicitly bounded diagnostic session. `LiveEditTelemetry.maximumRetainedSamples = 256` already demonstrates a bounded approach. [LiveEditTelemetry.swift:85](../Sources/KromoraKit/Models/LiveEditTelemetry.swift#L85)

### 13. Color-managed sRGB is correct within its scope, but wide-gamut preview remains limited

**Ticket:** [KRMA-941](../.dg/issues/KRMA-941.md), updated in place. HDR/EDR stays out of that plan. KRMA-923 (canvas color tag) is already done.

The missing Metal layer color tag has been fixed. However, `WorkingSpace.current` remains sRGB and the drawable uses 8-bit BGRA. Sources with colors outside sRGB cannot be fully assessed on the editing canvas even though the render/export value model supports Display P3. [WorkingSpace.swift:24](../Sources/KromoraKit/Models/WorkingSpace.swift#L24), [PreviewSurface.swift:1179](../Sources/KromoraKit/Views/PreviewSurface.swift#L1179)

For a focused SDR v1, explicitly accurate sRGB is a valid boundary. For the requested premium photo-editing standard, Display P3 preview and precision through the final presentation boundary are worthwhile improvements. Do not simply change `.current`: derived LUTs are explicitly fitted in sRGB, so their interpretation must be migrated or tagged correctly; persistent frame signatures and gamut tests must follow. HDR/EDR can remain post-MVP rather than being smuggled in as a release requirement.

Qualify saturated P3 images, smooth gradients, canvas/thumbnail/export agreement, display changes, and derived-Look round trips. Matching a color-space enum in a unit test is useful but does not establish end-to-end display accuracy.

## Native interaction, maintainability, and documentation

### Concrete UI/policy inconsistencies

- **Batch output sharpening is silently discarded.** The accessory exposes sharpening, and single export passes it into `ExportOptions`; `startBatchExport` omits it. Choosing the same setting should produce the same policy across single and batch export. [ExportCoordinator.swift:255](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L255), [ExportCoordinator.swift:447](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L447). **Ticket:** [KRMA-1008](../.dg/issues/KRMA-1008.md).
- **“Export Originals…” renders edited outputs.** That menu routes to selected batch export with each photo's edit document. Reserve “original” for untouched source bytes; name this action “Export Selected Photos…” or otherwise accurately describe the result. The original-plus-settings bundle is a different operation. [MenuCommands.swift](../Sources/KromoraKit/Views/MenuCommands.swift), [AppViewModel.swift:4080](../Sources/KromoraKit/ViewModels/AppViewModel.swift#L4080). **Ticket:** [KRMA-1009](../.dg/issues/KRMA-1009.md).
- **Reduce Motion is inconsistent.** Canvas/crop/sidebar paths consult it, while workspace/collection transitions, filmstrip scrolling, disclosure expansion, and some advanced-control reveals still request animation unconditionally. Consolidate the motion policy and test these paths with Reduce Motion enabled. This is a confirmed policy inconsistency, not a claim of observed nausea or visual defects. [ContentView.swift:281](../Sources/KromoraKit/Views/ContentView.swift#L281), [FilmstripView.swift:66](../Sources/KromoraKit/Views/FilmstripView.swift#L66), [InspectorDisclosure.swift:148](../Sources/KromoraKit/Views/InspectorDisclosure.swift#L148), [EffectsInspectorView.swift:259](../Sources/KromoraKit/Views/EffectsInspectorView.swift#L259). **Ticket:** [KRMA-1010](../.dg/issues/KRMA-1010.md).
- **Relaunch starts the replacement before termination has succeeded.** The launcher ignores the new process's result and then requests termination. Choosing the currently open library can race its lease; cancelling quit or failing to launch also lacks a coherent outcome. Coordinate relaunch with successful flush/lease release and handle launch failure. This risk was identified statically. [ActiveLibraryChooser.swift:11](../Sources/KromoraKit/Presentation/ActiveLibraryChooser.swift#L11). **Ticket:** [KRMA-1011](../.dg/issues/KRMA-1011.md).
- **Complete the real accessibility/focus pass.** The tree contains meaningful labels, values, and custom mask actions, which deserves credit. Verify VoiceOver selection/open/delete, custom slider adjustment, numeric-field editing, Full Keyboard Access, focus restoration after sheets, and pointer-tool alternatives in the packaged app. No String Catalog was found; decide explicitly whether v1 is English-only and avoid spreading formatted user-facing sentences through more workflow code. **Tickets:** the hands-on pass is [KRMA-1016](../.dg/issues/KRMA-1016.md). The language decision is [KRMA-960](../.dg/issues/KRMA-960.md), updated so a catalog is not started before that choice.

### Make ownership simpler, rather than merely splitting large files

`AppViewModel.swift` is **4,998 lines**, **6,479 including its extensions**. Other dense boundaries include `RenderEngine` (2,803), `MaskingWorkspace` (2,315), `PreviewSurface` (2,149), and `PortableLibrarySession` (2,054). Line counts are signals, not defects by themselves. The coordinator extractions and typed requests are valuable; a mechanical file split would not resolve the findings above.

The next improvements should enforce a small number of comprehensible contracts:

1. **One authoritative library selection and query order.** Presentation windows are projections. Reuse a query result/order by index generation rather than sorting/filtering the full index for each requested page. The current controller's `page` computes a fresh `orderedEntries` each time. [LibraryQueryController.swift:648](../Sources/KromoraKit/Models/LibraryQueryController.swift#L648). Selection authority is [KRMA-1001](../.dg/issues/KRMA-1001.md). The page-order cache is [KRMA-1012](../.dg/issues/KRMA-1012.md).
2. **One owned operation model for long-running user work.** Imports, edits, export variants, and shutdown should not have different answers to “who is waiting for this task?” Findings 2 and 5 are symptoms of that inconsistency. Concrete tickets: [KRMA-996](../.dg/issues/KRMA-996.md) and [KRMA-1000](../.dg/issues/KRMA-1000.md). No separate framework ticket was filed.
3. **One truthful load result.** Model `absent`, `available`, and `unreadable` as outcomes that callers must handle; avoid a boolean `found` plus a neutral document that makes failure easy to ignore. Export and Share are [KRMA-995](../.dg/issues/KRMA-995.md). That ticket does not require every other loader to migrate.
4. **Fine-grained presentation values with an immutable canonical recipe.** Observation is now in place, but `document` remains one observed value; tests intentionally show Light, Color, Effects, and preview readers invalidate together. Consider category/control projections where profiling justifies them, while keeping render/undo/persistence snapshots coherent. [ObservationBodyBaselineTests.swift:119](../Tests/KromoraKitTests/ObservationBodyBaselineTests.swift#L119). No implementation ticket. [KRMA-1002](../.dg/issues/KRMA-1002.md) files a child only if the warm-path profile shows this invalidation.
5. **Semantic architecture guards.** Keep the warning and concurrency gates, but do not confuse source-string/line-count checks with runtime guarantees. `Thumbnails.swift` still uses `uncheckedState`/`withLockUnchecked`, outside the three syntactic escape hatches checked by the package tests. Audit the reason and express the lock's safety with checked APIs where the SDK permits it; this review did not demonstrate a race. [Thumbnails.swift:194](../Sources/KromoraKit/Models/Thumbnails.swift#L194). **Ticket:** [KRMA-959](../.dg/issues/KRMA-959.md), updated in place.

Avoid broad rewrites of already-correct rendering or transaction code merely to look cleaner. Replace the ambiguous ownership and outcome contracts that are producing concrete failures, and retain the existing stale-result and durability protections during that work.

### Verification quality needs to match product quality

The suite is unusually substantial and passed today. Improve what it proves:

- Make every async test wait bounded and fail by unwinding. For example, `StoredEditAdoptionTests.waitForPreparationToStart` records an XCTest timeout assertion but never exits its loop when the deadline passes. A regression can still hang the run. Release all gates in teardown and add a CI-level timeout as containment. [StoredEditAdoptionTests.swift:89](../Tests/KromoraKitTests/StoredEditAdoptionTests.swift#L89). **Tickets:** [KRMA-1013](../.dg/issues/KRMA-1013.md) for this wait. [KRMA-967](../.dg/issues/KRMA-967.md) (already `ready`) now has acceptance criteria for the remaining `Task.yield()` loops.
- Audit lane classification by actual resource use. `RetouchQualityEvaluationTests` and real-render Auto tests currently execute in the fast lane despite using Core Image. The regex partition counts every discovered test, but that arithmetic alone cannot establish deterministic/parallel safety. **Ticket:** [KRMA-1014](../.dg/issues/KRMA-1014.md).
- Add externally visible trust tests: mixed-state batch export, failed culling retry, authoritative cross-page selection, repeated export/quit, and recovery rejected without mutations. These are more valuable than additional assertions that mirror helper implementation. Those tests are acceptance criteria on KRMA-995, KRMA-996, KRMA-1001, KRMA-1000, and KRMA-997.
- Pair fault injection with process-crash and real filesystem failure tests. Injected exceptions exercise selected branches; they do not prove interprocess exclusion or directory durability. Covered by KRMA-997 and KRMA-998.
- Keep machine/date/commit/configuration metadata with performance evidence. The 100k single-shard debug mutation timing in `LIBRARY_SCALE_REGRESSION.md` is a useful contention stress result, not normal Release user latency; the docs correctly distinguish that boundary. KRMA-1002 requires that metadata on any new numbers.

### Refresh current behavior docs and keep historical evidence clearly dated

Documentation is extensive and mostly thoughtful about scope. Some current-facing statements lag behind recent work. The doc pass is [KRMA-1015](../.dg/issues/KRMA-1015.md). Menu-title assertions that move with the rename are [KRMA-1009](../.dg/issues/KRMA-1009.md).

| Document | Drift to resolve |
| --- | --- |
| [README.md:43](../README.md#L43) | Promises selectable sizing, color, bit-depth, and alpha options. The current save-panel accessory exposes format, metadata/GPS, Photos delivery, and sharpening; those other capabilities exist in the value model but are not offered there. Either expose a coherent options flow or describe the shipping controls accurately. |
| [INTEROP_EXPORT.md](../docs/INTEROP_EXPORT.md) | Describes Share as eagerly rendered TIFFs; current Share uses lazy 4096 px HEIC/JPEG. It also describes the bundle's GPS policy differently from the current explicit keep-original-metadata confirmation and `locationMetadataIncluded: true`. |
| [APP_STORE_ACCEPTANCE.md, A21](../docs/APP_STORE_ACCEPTANCE.md#L162) | Still describes delete-before-copy derived-Look replacement as current behavior. Current `DeriveCoordinator.performSave` stages then renames. Update the expected result, while preserving the need to test external sandbox destinations and replacement failure. |
| [APP_STORE_SANDBOX_AUDIT.md](../docs/APP_STORE_SANDBOX_AUDIT.md) | Some early sections still cite old locations and scope ownership. Mark historical findings with disposition or update the current-source sections. Static fixes do not substitute for a fresh sandbox run. |
| [KEYBOARD_QA_CHECKLIST.md](../docs/KEYBOARD_QA_CHECKLIST.md) | Preserves the useful October 13 spot check, but also contains obsolete “always enabled” wording and resolved failure observations. Clearly separate the original observation from current behavior and verification. The previous human waiver should remain recorded, not be silently undone. |
| [APP_ARCHITECTURE.md](../docs/APP_ARCHITECTURE.md) | Some embedded root line counts are stale. Prefer dated inventories over several hard-coded copies. Keep the authority/lifetime contracts, which are much more useful. |

Several source comments also recount old “Step 4/Step 6” migrations or promise a lazy Core Image chain becomes one GPU pass. Describe current invariants and measured behavior instead; a lazy graph does not itself prove a single GPU pass. Keep implementation history in dated records where it helps future investigation.

## What is already worth preserving

- Native SwiftUI/AppKit/Metal/Core Image implementation, Apple Silicon/macOS 26 scope, no third-party runtime dependency burden, and a clean Swift warnings-as-errors build.
- A single ordered render stack and value-oriented requests, with explicit source/Look/pipeline identities and meaningful preview/export parity coverage.
- Separate export and interactive render engines, bounded renderer caches, resolution planning, completed-texture handoff, and demand-aware scheduling.
- Package-owned originals, metadata and edit revisions; disposable indexes/caches; immutable revisions and transaction recovery primitives. The storage model is substantially more trustworthy than an ad hoc directory of sidecars.
- Coalesced edit persistence that retains failed snapshots, generation fencing across source changes, and explicit shutdown barriers in most coordinators.
- Improved Observation boundaries, grid virtualization, keyboard responder-chain integration, asynchronous panels, and extensive custom-control accessibility work.
- Honest product boundaries: a focused local editor does not need cloud sync, layered PSD, comprehensive DAM, backup UI, or HDR breadth to be a good v1.

## Release qualification I would require

Hands-on evidence is [KRMA-1016](../.dg/issues/KRMA-1016.md). It stays in the backlog with human review required, and it depends on the must-fix tickets plus the retouch gate. Do not treat it as an implementation ticket.

1. Resolve findings 1–6 with behavioral tests. Verify the cases through the app boundary, not only isolated helpers, and rerun the required lanes on the exact candidate.
2. Bound decoded-image and diagnostic retention; run a long-session traversal/edit/export soak on a lower-memory supported Mac. Include memory pressure, interrupted media, and disk exhaustion on disposable data.
3. Establish supported retouch quality acceptance and inspect the results at camera scale. Do not treat a report that expects failures as the release quality gate.
4. Qualify the actual signed sandboxed build on **macOS 26**, as well as the newer OS/toolchain used here. Run the full Library → Edit → Export → Quit → Relaunch loop in a disposable profile, including denied Photos access, bookmarks after relaunch, external save destinations, and cancellation.
5. Test derived-Look staging/replacement under the actual sandbox outside Pictures. A file-only panel grant plus sibling staging remains a runtime qualification target; this review did not reproduce a sandbox denial.
6. Perform a deliberate visual/focus/accessibility pass: rapid workspace and photo changes, crop/rotation/comparison, mask overlays, resize/full screen, mixed-DPI displays, Reduce Motion, VoiceOver, and keyboard focus around sheets. Look for stale pixels, layout jumps, focus loss, flashes, and transitions that delay useful input.
7. For the exceptional-performance claim, agree on and meet perceptual latency/frame-gap budgets using one supervised release capture series under the repository policy. Do not repeatedly rerun unchanged misses or quietly lower the bar to existing numbers.
8. Produce an Apple-signed archive, App Store validation, and an internal TestFlight installation/update; complete the submission worksheet's owner-provided URLs and account details. Preserve the exact candidate commit and evidence with the results.

This is a finishing and hardening stage with specific correctness work remaining. The strongest path to the requested quality is to make user intent, operation ownership, memory bounds, and failure outcomes as rigorous as the rendering and package architecture already aim to be.

## Tickets filed from this review

Filed 2026-10-14 into the DispatchGraph backlog after comparing the findings with open work. Epic: [KRMA-994](../.dg/issues/KRMA-994.md). Pre-existing children of [KRMA-922](../.dg/issues/KRMA-922.md) were updated instead of duplicated.

| Finding | Ticket | Disposition |
| --- | --- | --- |
| 1. Batch export fallback | KRMA-995 | New, urgent. Filed to the backlog; pickup claimed it after the board briefly promoted it |
| 2. Culling dirty/retry/quit | KRMA-996 | New, urgent, backlog |
| 3. Recovery ownership | KRMA-997 | New, urgent, backlog |
| 3. Directory durability | KRMA-998 | New, high, backlog |
| 4. Thumbnail retention | KRMA-999 | New, high, backlog. Soak is KRMA-1016 |
| 5. Export/share/bundle ownership | KRMA-1000 | New, high, backlog. Builds on done KRMA-946 |
| 6. Select All authority | KRMA-1001 | New, high, backlog |
| 7. Warm navigation | KRMA-1002, KRMA-952 | Profile is new. Decision ticket updated and now depends on KRMA-1002 |
| 8. Retouch quality | KRMA-1003, KRMA-1004 | Gate, then repair. KRMA-1004 depends on KRMA-1003 |
| 9. Export memory peak | KRMA-942 | Updated in place |
| 10. Main-actor filesystem | KRMA-1005, KRMA-1006 | Lease renewal, then Settings/shutdown I/O |
| 11. Render identity and texture reuse | KRMA-954, KRMA-953, KRMA-963 | Plans updated. KRMA-963 returned to backlog until ownership is proven |
| 12. Diagnostic retention | KRMA-1007 | New, medium, backlog |
| 13. Display P3 preview | KRMA-941 | Updated. HDR/EDR left post-MVP. KRMA-923 already done |
| Batch sharpening | KRMA-1008 | New |
| Export Originals naming | KRMA-1009 | New |
| Reduce Motion | KRMA-1010 | New |
| Relaunch sequencing | KRMA-1011 | New |
| Query page cache | KRMA-1012 | New. Separate from Select All |
| Adoption-test hang | KRMA-1013 | New. Sibling of ready KRMA-967, whose empty criteria were filled |
| Core Image test lane | KRMA-1014 | New |
| Doc drift | KRMA-1015 | New |
| Unchecked thumbnail lock | KRMA-959 | Updated in place |
| v1 language / String Catalog | KRMA-960 | Updated. Human decision required before a catalog |
| Signed-app qualification | KRMA-1016 | New checklist. Human review required. Depends on KRMA-995–KRMA-1001 and KRMA-1003 |

Not given a new implementation ticket: a general operation framework, HDR/EDR, Observation splits unless KRMA-1002's profile justifies one, and any new display-bound capture before KRMA-952 reopens a budget. Open work that does not match this review was left as it stood, including KRMA-055/056/059 (MVP gate; KRMA-059 points at KRMA-1016), KRMA-967, KRMA-991, and the in-review tickets KRMA-561, KRMA-818, KRMA-930, and KRMA-914.

## Reproduction evidence from temporary probes

Six focused probes used generated images and temporary library packages, never a user library. They were run serially through XCTest and removed from the working tree afterward. All six completed in 1.83 s after compilation. Assertions intentionally pinned the observed behavior so a “pass” here means the finding reproduced.

```text
REVIEW-PROBE untouched-edit: saved-revisions=0 exported=1 exposure=2.0
REVIEW-PROBE corrupt-edit: exported=1 failed=0 exposure=2.0
REVIEW-PROBE culling: failure-reported=1 requested-rating=4 after-repair-and-flush=0
REVIEW-PROBE recovery: unexpired-lease-rejected=true active-journal-removed=true
REVIEW-PROBE thumbnail-retention: original-retained=true edited-retained=true loaded-items-after-next-page=3
REVIEW-PROBE select-all: library=3 loaded-selected=2 authoritative-selected=1 after-sync=1
```

To reproduce the important conditions when implementing fixes:

- **Untouched export:** import a photo into a temporary package, leave `currentRevision` at zero, supply the package store to `ExportCoordinator`, omit the item's in-memory document, and export with a +2 EV fallback. Inspect the fake engine's request document.
- **Unreadable export:** save a distinct edit to that photo, replace its current native revision JSON with malformed bytes, confirm `load.found == false` and actionable status, and repeat export. Inspect both the requested document and outcome count.
- **Culling retry:** save the original membership shard bytes, temporarily replace the shard with malformed JSON, enqueue rating 4, await the reported error/flush, restore the shard bytes, flush again, and read the durable rating.
- **Recovery precondition:** acquire an unexpired lease, begin and stage an uncommitted transaction, confirm its journal exists, call `recoverExpiredWriter` at the same time value, and inspect journal presence after the contention error. This verifies helper ordering; it is not a simulation of two concurrent processes.
- **Thumbnail retention:** populate an item's original and edited `NSImage` slots, begin demand-driven browsing, release that ID, inspect both image slots, then append another browsing page. This verifies strong ownership; it does not measure resident pixel memory.
- **Selection authority:** use a three-photo package with page size two, select one photo in the package authority, mirror it into the collection, call the exact `collection.selectAll()` method used by the responder action, inspect both selections, and synchronize again.
