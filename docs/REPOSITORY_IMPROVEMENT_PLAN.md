# Stability, performance, and architecture improvement plan

> **Superseded as an execution plan (2026-09-22).** This file preserves the 2026-09-12 baseline
> findings and acceptance ideas; its original R1–R8 ordering is no longer the live backlog. Use the
> current issue records and architecture docs for present ownership. Status below is intentionally
> conservative: a related completed issue closes only the named overlap, not every original acceptance
> item. Reopen or create a scoped issue before treating any remaining historical acceptance text as
> current work.

## Historical work-package status

| Item | Status | Current record / disposition |
| --- | --- | --- |
| R1 import durability and truthful outcomes | Superseded/implemented | [KRMA-517](../.dg/issues/KRMA-517.md) completed truthful outcomes across import entry points. |
| R2 cancellation and lifecycle ownership | Open for re-triage | [KRMA-517](../.dg/issues/KRMA-517.md) and [KRMA-520](../.dg/issues/KRMA-520.md) cover import outcomes and removal of the legacy mode; this does not certify every cancellation scenario in the historical acceptance list. |
| R3 bounded import work and memory | Partially implemented | [KRMA-518](../.dg/issues/KRMA-518.md) moved package hashing/index refresh off the main actor; [KRMA-519](../.dg/issues/KRMA-519.md) records paged production-path work. Peak memory and the historical 1/10/50 import benchmark remain unclaimed here. |
| R4 ROI mask work bounds and parity | Open for re-triage | The old proposed implementation/measurements are not a current verified contract. Re-scope from current mask code and tests before scheduling. |
| R5 AppViewModel ownership decomposition | Partially implemented | Current ownership is documented in [APP_ARCHITECTURE.md](APP_ARCHITECTURE.md); [KRMA-521](../.dg/issues/KRMA-521.md) covers Observation fan-in. Further decomposition is not asserted complete by this document. |
| R6 observation and repeated projection work | Partially implemented | [KRMA-521](../.dg/issues/KRMA-521.md) completed the root publisher fan-in change. Any remaining projection optimization needs a current measured issue. |
| R7 executable boundaries and evidence discipline | Open/ongoing | [KRMA-535](../.dg/issues/KRMA-535.md) reconciles documentation; [KRMA-542](../.dg/issues/KRMA-542.md) and [KRMA-547](../.dg/issues/KRMA-547.md) track observed test-lane failures. The historical R7 acceptance list is not a single active ticket. |
| R8 real crop/slider interaction coverage | Open for re-triage | No completion is claimed here. Reassess against current UI and test lanes before creating scoped work. |

The portable-library work in this historical review has its own shipped sequence: [KRMA-519](../.dg/issues/KRMA-519.md)
records the production query/window path, [KRMA-520](../.dg/issues/KRMA-520.md) records the package-only
product and migration boundary, and [KRMA-531](../.dg/issues/KRMA-531.md) records package-backed edit
cache persistence. This plan does not supersede those decisions.

Reviewed 2026-09-12. Primary baseline: **`a29b4ee`**, covering the ten commits
`74d4cfb..a29b4ee`. This is a recommendations and implementation handoff document.
No application source was changed during this review.

## Assessment

Prioritize import correctness and lifecycle ownership before further organizational refactors.
The recent work establishes useful seams: Photos has an injectable provider, mask controls share
one value model, panel models have moved out of views, and ROI mask rendering preserves full-frame
coordinates. However, a successful transfer is still confused with a successful durable import,
application state and task ownership remain widely coupled, and the ROI correction exposes an
expensive full-frame brush rasterization path.

The main architectural problem is **responsibility count**, not simply file length. Moving methods
into extensions or renaming a type does not make its workflow independently testable, reduce its
observation footprint, or give it a complete cancellation boundary.

## Scope and evidence

| Commit | Reviewed change | Main follow-up |
| --- | --- | --- |
| `a29b4ee` | Domain/platform separation | R7: enforce behavior and dependency boundaries beyond names/import checks |
| `17f6657` | Panel models moved to ViewModels | R2/R7: cancellation and independent model tests |
| `59657fc` | Documentation reconciliation | R7: distinguish committed implementation from pending work |
| `2da4856` | Starter Looks and My Looks | R6: cache collection projections and narrow observation |
| `cf6ca17` | Slider tracks and circular thumbs | R8: real input, focus, accessibility, and drawing checks |
| `4bb85e4` | Looks acknowledgement UI | No separate defect found; preserve packaged provenance metadata |
| `1bdb550` | Crop interior dragging | R8: actual gesture coverage |
| `8adf7cf` | Photos orchestration extraction | R1–R3: durability, lifecycle, memory, and I/O |
| `9cbd39e` | Local adjustment control alignment | Preserve shared ranges, neutral values, and layer-scoped mutations |
| `9b043c1` | ROI mask coverage fix | R4: broader parity coverage and bounded brush work |

Findings below distinguish **reproduced behavior**, **static evidence**, and **performance hypotheses**.
Some problems predate these commits but are directly on the workflows being extracted. Do not
attribute those problems to the refactor merely because it exposed them.

### Concurrent work: reconcile before implementing

The checkout was already dirty when review began. The committed snapshot was exported to a temporary
directory for building and testing; existing source changes were not modified. During review, HEAD
advanced to `6853276` (a blank-line cleanup). All source line numbers below refer to **`a29b4ee`**;
use the named symbols when working against a newer revision.

Observed pending work includes `EditorDocumentCoordinator`, `ComparisonFramePolicy`, a root-owned
`PhotosImportCoordinator` with `PhotosImportDestination`, and corresponding façade/test changes.
These address part of R2/R5. Review and extend them; do not create competing coordinators.
The local issue records identify KRMA-382/383 as done and KRMA-380 as claimed, while some associated
implementation is still uncommitted. Status labels alone are not proof that a dependency landed.

The portable-library backlog already has KRMA-389–393 beneath KRMA-384. KRMA-384 is locally blocked
on its design/migration decision. This plan complements that work: it does not replace the package
plan or authorize its data-disposition choices. Native dialog/drop extraction overlaps KRMA-380.

### Verification performed

- Debug build of the exported committed baseline: **passed** with compiler warnings. SwiftPM and
  compiler caches were redirected to the temporary directory; the SwiftPM manifest sandbox was
  disabled inside the existing execution sandbox after its default cache path was unwritable.
- Focused existing tests: **50 executed, 49 passed, 1 failed**. Covered Photos import, coordinator
  boundaries, model dependencies, local adjustment controls, Look inspector, sliders, analysis
  panel, and the new semantic ROI regression test.
- `LocalMaskRenderingTests.testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail` failed
  with `processingFailed` at `RenderEngine.swift:879`, during PNG representation, rather than a
  pixel-difference assertion. An additional existing control,
  `RenderEngineTests.testPreviewAndExportAreTheSamePixels`, also failed, this time constructing its
  fixture CGImage. Rendering is therefore **not validated in this execution environment**; these
  failures do not isolate an ROI regression. R4 requires rerunning on a functioning graphics host.
- Two temporary characterization tests: **2 passed**, reproducing R1 and R3. They asserted the
  problematic current behavior; they are not regression tests asserting the desired fix.
- No full fast/serial lane, release build, packaged-app interaction, RAW benchmark, or Instruments
  capture was completed in this review. No product latency claims follow from these tests.

The focused baseline test selection was:

```sh
swift test --no-parallel --filter \
  'PhotosImportTests|ModelDependencyTests|LocalAdjustmentControlTests|CoordinatorBoundaryTests|LookInspectorViewTests|NeutralOriginSliderTests|AnalysisDebugPanelTests|LocalMaskRenderingTests/testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail'
```

This ran in the exported baseline with the cache/sandbox adjustments described above. Temporary
probes used the existing `TempDirectoryTestCase`, `makeAppViewModel`, `makeTestCollection`, and
`Fixtures.writeJPEG` helpers; the exact failure recipes and assertions are described in R1/R3.

Useful entry points: [AppViewModel](../Sources/KromoraKit/ViewModels/AppViewModel.swift),
[PhotosImportCoordinator](../Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift),
[ImageCollection](../Sources/KromoraKit/Models/ImageCollection.swift),
[RenderEngine](../Sources/KromoraKit/Models/RenderEngine.swift),
[LocalMaskRenderer](../Sources/KromoraKit/Models/LocalMaskRenderer.swift),
[engineering guide](ENGINEERING_GUIDE.md), [testing guide](TESTING.md), and
[portable-library plan](LIBRARY_PACKAGE_PLAN.md). These links open the current checkout;
the symbol locations and observations in this review are anchored to the baseline above.

## Why AppViewModel is still approximately 5,000 lines

At the committed baseline, `AppViewModel.swift` is **4,943 lines**, with approximately **180 methods**,
**39 `@Published` declarations** including nested state, and **20 task-valued fields**. Its six
extensions add **2,238 lines**, for **7,181 lines belonging to the same object**. Of the main file,
796 lines are comment-only and 407 are blank; deleting documentation would leave the ownership
problem intact. The ten-commit range reduced the main file by only 26 lines: the Photos extraction
moved the provider loop from `ContentView`, while import progress and insertion orchestration stayed
in the application model.

| Responsibility still in the main file | Baseline location | Proposed destination |
| --- | --- | --- |
| Auto invocation and application | `runAutoAdjustment`, roughly 1128–1405 | Auto workflow coordinator with value results |
| Source load, stored-edit reconciliation, first frame, prefetch, idle cache building | `load`, `prepareAndInstall`, roughly 1406–2103 | Source session owner plus background preview worker |
| Photos, removable media, navigation, deletion | roughly 2128–2759 | Import/library workflow owners and platform adapters |
| Edited thumbnails | `requestEditedThumbnail`, roughly 2760–2925 | Edited-thumbnail coordinator |
| Clipboard, history, document mutations | `pasteEdits`, `updateDocument`, `applyHistoryDocument` | Existing pending editor coordinator plus one application commit path |
| Preview planning, disk-cache lookup, comparison, presentation, histogram | roughly 3397–3764 and 4090–4588 | Preview presentation owner using the existing render scheduler |
| Native dialogs, export assembly, persistence façade, shutdown | roughly 4600–4943 | Platform adapters and focused collaborators, composed at the root |

`AppViewModel+Masking.swift` alone is 1,309 lines. Extensions share the root's state and lifecycle;
that file is a feature boundary candidate, not evidence that masking has already been extracted.

Keep the root responsible for composition, command routing, cross-feature sequencing, and the one
published active document during this transition. Keep Core Image/Metal resources in their existing
render owners. Do not introduce a second renderer or a second writable active-document store.

## Prioritized work packages

P1 means correctness or a significant stability/performance exposure worth addressing next.
P2 means planned architecture, efficiency, or verification improvement. Sizes are relative:
S = focused change, M = several coordinated files, L = staged work requiring multiple PRs.

### R1 — Report success only after a durable import succeeds

**Priority P1 · M · Reproduced · Existing behavior exposed by Photos extraction**

Evidence: `ImageCollection.durableDataURL` (`ImageCollection.swift:1184–1211`) catches write failures,
adds a scan warning, and still returns the intended URL. `appendDataImport` publishes an asset for
that URL; `AppViewModel.appendPhotosImport` (`AppViewModel.swift:2171–2196`) increments `imported`
unconditionally and opens the URL. Metadata processing can later remove the unreadable item, but
that does not repair the import success accounting.

Reproduction used a regular file as the parent of the requested library directory. After importing
a valid generated JPEG, progress was `imported == 1`, `failed == 0`, and the published asset URL did
not exist. The collection did contain a warning. This can give a user a false impression that an
original has been safely copied.

Implementation:

1. Introduce a throwing import writer boundary returning a verified stored-original value, including
   URL and observed fingerprint. Keep identity semantics unchanged in this fix.
2. Publish an asset and increment successful-import progress only after storage succeeds. Return
   explicit inserted/already-present/failure outcomes so deduplication is counted intentionally.
3. Preserve item-local failure details and continue with remaining selections. Validate reused
   destinations sufficiently to avoid treating an unreadable existing path as a successful copy.
4. Evolve the pending `PhotosImportDestination.insertPhotosImport` API to return an outcome instead
   of `Void`; otherwise the extracted coordinator still cannot know whether insertion succeeded.

Acceptance: injected permission/write/rename failures create no successful asset, do not open a
nonexistent URL, increment the correct failure count, and leave earlier successful imports intact.
Test restart/retry and existing-destination cases. Use injected failures rather than depending on
the test machine actually running out of disk space. Reopening a successful import must work from
its URL without the transferred `Data`.

### R2 — Make import and panel cancellation complete lifecycle boundaries

**Priority P1 · M · Static evidence; pending work partly addresses it**

At baseline, `ContentView` owns the Photos coordinator (`ContentView.swift:11–30`), while
`AppViewModel.shutdown` does not cancel or await it. Its operation UUID changes on a new import,
but not on a source-folder change or root shutdown. `ImageCollection.loadFromFolder` clears the
items and import reservations (`ImageCollection.swift:586–606`), while `appendDataImport` later
inserts at `dataImportStartIndex + relativeIndex`. A suspended transfer resuming after a collection
replacement can therefore operate on the wrong collection and potentially an invalid insertion
index. This sequence needs a deterministic regression test; a UI crash was not reproduced here.

The pending root-owned coordinator and `shutdown()` improve ownership, but its nil-data and generic
error branches call `recordFailure` without checking operation identity/cancellation. The old
committed private `recordFailure` checked cancellation; the pending public method no longer does.
If import A ignores cancellation and returns nil or throws after B starts, A can alter B's failure
count and reservation state. Also inspect `AnalysisDebugPanelModel.load`'s generic error branch:
an obsolete task can still clear loading state or publish an error after cancellation/reload.

Implementation: retain root ownership, inject a narrow destination, and fence **every** post-await
mutation, including errors and completion, with operation identity and lifecycle state. Associate
the import with a collection generation. Define whether changing the library cancels the import
or completes into its original destination; do not let it silently adopt a new collection. Retire
superseded operations immediately for publication purposes and track any still-running cleanup.
Avoid shutdown waiting forever on a provider that never acknowledges cancellation.

Acceptance: controlled providers resume A after B with success, nil, ordinary error, and cancellation;
none changes B. Exercise folder replacement, empty selections, cancellation during hashing/storage,
and shutdown during transfer. Verify no post-shutdown insert or publication and exactly one terminal
outcome per operation. Test panel cancel/reload with late ordinary errors, not only CancellationError.

### R3 — Bound import memory and move storage work off the main actor

**Priority P1 · M · Retention/digest behavior reproduced; latency impact unmeasured**

`appendDataImport` stores the entire original in `PhotoAssetSource.data` even after writing a durable
URL (`ImageCollection.swift:1135–1138`). `finishDataImport` does not release it. Thumbnail, metadata,
and editing paths prefer the URL, so the retained bytes often have no continuing purpose.
The picker permits 50 items per selection; 50 × 40 MB originals imply roughly 2 GB of retained
payloads before decoded/GPU caches. This is an arithmetic exposure, not a measured peak. Repeated
imports can accumulate more while the collection remains open.

The main-actor `durableDataURL` also enumerates the entire library directory for every item and
performs atomic writes synchronously. Importing M files into N existing files entails roughly
O(MN + M²) directory-entry inspection. Filename/identity/fingerprint work can read the file again.
Moving just SHA-256 into `Task.detached` leaves the large storage operation on the UI actor.

There is also a misleading digest contract: `PhotoImportItem.contentDigest` is a full SHA-256,
whereas `Item.dataFingerprint` returns `PhotoSourceFingerprint.file(...).sampleDigest`, which hashes
only the first/last 64 KiB for large files. The existing digest propagation tests use tiny JPEGs,
for which these happen to agree. A JPEG padded beyond 200 KB reproduced unequal digests and full
payload retention after import completion. This does not by itself prove a visible cache collision;
it proves that the advertised shared-full-digest invariant is not being tested or maintained.

Implementation: build on R1's storage service, perform bounded asynchronous storage/index lookup,
and return URL-backed assets without permanent payload retention. If a first-frame cache is needed,
give it an explicit byte budget and eviction owner. Keep full content identity and bounded file
signatures distinctly named; do not substitute one for the other in data-cache keys. Preserve
existing file identity until the portable-identity work deliberately changes it.

Acceptance: generated large originals remain exportable after payload eviction and relaunch; tests
distinguish full and sampled digests above 128 KiB. Instrument directory enumerations, retained
payload bytes, and main-actor storage calls. Benchmark 1/10/50 large imports into increasing library
sizes, recording peak RSS and UI responsiveness. No per-item whole-library enumeration; retained
transfer memory should be bounded by active work/cache budget rather than total imported bytes.

### R4 — Preserve ROI correctness without full-frame brush work on every preview

**Priority P1 · M/L · Static allocation/work evidence; graphics validation pending**

`9b043c1` correctly passes `fullFrameExtent` to mask resolution and clips only after establishing
source-space coverage (`RenderEngine.swift:1406–1413, 1658–1742`). Preserve that coordinate contract
and the cache-version bump. However, nonsemantic masks receive full-frame target dimensions, and
`LocalMaskRenderer.brushImage` allocates a full-frame Float buffer. On a cache miss,
`cachedStrokeRaster` loops over every pixel and resampled stroke sample (`LocalMaskRenderer.swift:243–330`).

At an evaluated frame of 6000 × 4000 pixels, one Float buffer is **96,000,000 bytes**, exceeding the
64 MiB default stroke-cache budget. Such a stroke is computed but not cached, and the composed
buffer is additional memory. The ROI change expands this exposure for zoomed previews: a small
visible region does not bound the CPU rasterization extent. The actual extent depends on the
resolution plan; do not assume every preview reaches native resolution.

Implementation: establish separate full-source geometry and evaluated raster/tile bounds. Rasterize
brush influence only in the requested region with the required feather/filter halo, or introduce
a bounded tile cache. Key it by source, recipe, transform, scale, region, and renderer version.
Check cancellation inside CPU work, and preserve preview/export semantics. Do not fix performance
by normalizing masks to the ROI or silently lowering export quality.

Acceptance: extend the current 16 × 8 semantic test to brush, linear, radial, inversion, and ordered
add/subtract/intersect composition. Cover crop, rotation/orientation, nonzero ROI origins, preview
scaling, ROI movement, and cache reuse. Compare ROI pixels with the corresponding full-frame crop
and verify full-resolution export parity. Measure cold/warm brush ROI render time, peak allocation,
and cancellation latency on a graphics-capable host. Work should scale with touched tiles/samples
rather than total source pixels for a small ROI. Record the baseline before selecting budgets.

### R5 — Finish decomposing AppViewModel by ownership

**Priority P2 · L, staged · Static architecture evidence**

Use the pending `EditorDocumentCoordinator` and `ComparisonFramePolicy` as the first increment.
Review the editor coordinator's inputs carefully: `apply` defaults a missing session to an empty
document, so cold destinations with persisted edits need an explicit load/restore policy before
undo history is recorded. Characterize cold multi-paste, undo, and stored-edit races before moving
more code. Per-photo history is bounded, but the session dictionary has no global eviction budget;
include session-count/byte accounting before large-library work.

Suggested PR sequence, each with its own behavior tests:

1. **Land and verify pending editor/import boundaries.** One progress owner, one session/history
   owner, and one document commit path. Preserve the existing façade.
2. **Extract source-session orchestration.** Own preparation, stored-document reconciliation,
   metadata/capability tasks, and first-frame lifetime. Supply explicit source/document tokens
   and immutable results to the root. Keep only one active source preparation plus the newest
   pending selection, as today.
3. **Extract edited-thumbnail and background preview work.** Own per-asset generations, debounce,
   prefetch/idle admission, and cache writes. Reuse existing scheduler policy and cancellation IDs.
4. **Extract preview presentation/comparison/histogram orchestration.** Keep renderer admission in
   `PreviewCoordinator`; move request planning and display lifecycle as a coherent owner rather
   than scattering revision counters across collaborators. Preserve the distinction between
   accepted pixels and an actually presented frame.
5. **Extract Auto/masking and library/media workflows.** Auto returns a value result applied via
   the same document commit path. Mask gestures own drafts; committed recipes go through that
   path. Removable-media services own platform observers and scoped-resource lifetimes. Coordinate
   dialogs with KRMA-380 and package storage with KRMA-391/392.

Every extracted owner must state: state it owns, admitted commands, values it publishes, revision
checks, task handles, shutdown behavior, and resource limits. Prefer narrow protocols/value callbacks
over a reference to all of `AppViewModel`. Do not introduce a generic event bus or a second store.

Acceptance: new workflow tests construct the collaborator with fakes, without AppViewModel, real
preferences, NSWorkspace, or GPU setup. Retain application integration tests for navigation during
load/render/Auto, undo grouping, cold/warm edits, comparison, persistence failure, and shutdown.
Review the root's remaining responsibility inventory after each PR. Line count is a trend metric,
not a pass/fail target; moving the same mutable state into extensions does not satisfy this task.

### R6 — Reduce broad SwiftUI invalidation and repeated Look projection work

**Priority P2 · M · Static repeated-work evidence; user-visible cost to measure**

`AppViewModel.init` forwards settings, library, collection, export, derive, and save publishers through
root `objectWillChange`, creating a main-actor Task for each notification (`AppViewModel.swift:923–939`).
Views that observe the root can be invalidated by unrelated progress or library changes.
The new `starterLooks`/`myLooks` projections filter and sort `allLUTs` on every access
(`LUTLibrary.swift:59–69, 358–372`); `LookInspectorView` requests them from computed presentation
properties and also rebuilds category-search sets. The list is lazy, but these full-list projections
still run outside individual visible rows.

Implementation: observe feature state directly in the smallest relevant subtree, removing root
forwarding only after consumers are migrated. Materialize stable sorted Look collections once per
library revision; derive search results from collection revision and query. Keep deterministic tie
ordering. Treat transient document changes separately from changes that affect candidate Look pixels
so thumbnail request identities do not invalidate needlessly.

Acceptance: instrument projection counts and view/body updates on generated 100/1,000-Look libraries.
Repeated status/progress updates should not re-sort collections; unchanged queries and library
revisions reuse their projection. Verify selection, missing Look IDs, rescans/replaced files, category
searches, and lazy thumbnail cancellation. Compare interaction and navigation p95 before/after on
the same host; do not infer a speedup solely from fewer lines or fewer publishers.

### R7 — Make architecture and verification claims match executable evidence

**Priority P2 · M · Static evidence and observed compiler diagnostics**

`ModelDependencyTests` checks forbidden import strings and expected marker/type names. This catches
some accidental layering drift, but aliases such as `ImageCollectionPresentationModel` do not prove
that filesystem access, observation, and domain mutation are separated. New source files can also
fall outside the six-file durable-value list. The committed `PhotosImportTests` still constructs
the whole application model even though its provider is fake.

Documentation is ahead of code in places: committed architecture guidance names the then-untracked
editor/comparison coordinators as current owners. `ENGINEERING_GUIDE.md` says only slider bar drawing
is overridden, while `cf6ca17` also overrides knob drawing. The zero-diagnostic guidance also does
not match this build: it emits Core Image kernel deprecation warnings, and the test build emits
unused-result and actor-isolation warnings, including crop geometry tests.

Implementation: publish ownership documentation in the same PR as its implementation. Expand
boundary checks around actual allowed dependencies and independent construction, rather than adding
more marker-name assertions. Consider a small domain SwiftPM target only after dependencies are
clean enough for a compile-time boundary; do not make a sweeping target split a prerequisite for
the correctness fixes. Assert persistence flush results in tests instead of dropping them.

The test lane auditor also assigns every unrecognized suite to fast, so its total-count check
cannot detect a newly added GPU/AppKit suite in the wrong lane. Require an explicit lane declaration
or equivalent audited classification for new suites, and report unavailable graphics smoke tests
as deferred evidence rather than a completed interaction check.

Acceptance: new collaborators have genuine fake-only tests; new suites require a reviewed lane;
architecture docs link to existing symbols at the landing commit. Record exact SHA, commands,
counts, skips, warnings, and environment limitations in handoffs. Establish a diagnostic baseline,
then prevent new warnings; resolve actor-isolation warnings rather than silencing concurrency checks.
Preserve macOS 14 deployment, Xcode 26+ SDK support, Swift 6 mode, and Apple-only dependencies.

### R8 — Add interaction coverage for crop and custom slider changes

**Priority P2 · S/M · Coverage gap, not a confirmed new UI defect**

Crop handle geometry tests in the immediately preceding commit establish positions and sizes;
they cannot prove that the gesture reaches the intended SwiftUI view over a Metal preview.
`1bdb550` changes the interior move gesture's actual hit surface. The slider change overrides custom
thumb drawing, but circle geometry and raster existence do not establish focus, tracking, keyboard,
or VoiceOver behavior.

Implementation: extend the packaged-app UI smoke path with real drag/keyboard interactions where
automation is reliable. Keep pure geometry tests, and document repeatable manual checks for cases
requiring a logged-in display. Use the actual control/canvas hierarchy, not only a helper method.

Acceptance: drag all crop corners/edges and the interior, including small crops with overlapping
targets, zoomed/panned images, boundary clamping, Apply, Escape, and undo. Exercise slider endpoints,
neutral reset, keyboard increments, focus visibility, disabled state, VoiceOver value/actions, and
light/dark appearance. Run representative global and local controls and verify that gestures form
one undo group. Attach environment and visual/input evidence to the PR.

## Execution order and agent coordination

| Stage | Work | Dependencies and shared-file constraints |
| --- | --- | --- |
| 0 | Reconcile pending coordinator changes and freeze a reviewed base SHA | Inspect current diff and KRMA-380/382; preserve concurrent work |
| 1 | R1 durability and R2 lifecycle fixes | Serialize changes to PhotosImportCoordinator, destination API, and ImageCollection |
| 2 | R3 storage/memory work; R4 ROI mask work | R3 builds on R1/R2. R4 can be independently assigned if parallel work is authorized |
| 3 | R5 incremental ownership extractions; R6 observation/projection work | Land one extraction at a time; R6 consumer migration follows the relevant ownership seam |
| Ongoing | R7 evidence/lane/documentation discipline; R8 UI coverage | R8 follows the final control implementations; avoid duplicating KRMA-380 |

Keep portable-library baseline work in KRMA-389 aligned with R3/R4/R6 measurements. Avoid building
a second long-term catalog or import transaction architecture ahead of KRMA-390–392. Correct the
current success/error contract now; larger identity and migration changes retain their separate
decision and rollout gates.

For each assigned package, an implementing agent should:

1. Read `CLAUDE.md`, current engineering guides, the linked issue, and the current diff. Confirm
   which pending changes landed. Claim a bounded scope and list shared files before editing.
2. Reproduce the named condition, then add a test for the desired contract. Use isolated preferences,
   temporary libraries, injected providers/storage, and explicit lifecycle teardown.
3. Deliver a small reviewed PR with behavior, ownership changes, validation results, and remaining
   limitations. Keep refactors separate from renderer or persisted-format changes where possible.
4. Run `swift build`, the relevant focused tests and fast/serial lane, and `git diff --check`.
   Use release/RAW/graphics/packaged-app checks when the package makes those claims. Run
   `dg validate` if issue metadata is changed. Record the tested commit, not just a green summary.

Completion means the failure modes are covered, resource costs are bounded or measured against an
explicit baseline, and extracted features can be tested independently. A shorter AppViewModel is
expected as a consequence of that work.
