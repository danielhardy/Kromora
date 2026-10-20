# Kromora release readiness and code quality review — 2026-10-19

Reviewed `main` at `bb01e0c374fb`, including the pre-existing working-tree changes to
`ExportWorkflowCoordinator.swift` and its tests. This is a review, not a product implementation
or a DispatchGraph handoff. Product source, tests, issue records, and existing local changes were
left untouched. This report is the only repository file added by the review.

## Assessment

The progress since the October 14 review is substantive. Several failures that previously affected
ordinary exporting, culling, selection, and resource ownership now have explicit fixes and focused
regression coverage. The application has a sound foundation for a dependable local photo editor.

I would hold public App Store release for the findings below. Two disposable-fixture reproductions
demonstrated data-integrity defects in transaction recovery. Production packaging also fails its
current verification command, and the UI smoke script has fallen behind the export workflow.
These are focused corrective tasks; this review does not recommend a broad architectural rewrite.

Passing model and renderer tests is valuable evidence. A public release still needs the exact
Apple-signed candidate exercised on macOS 26 through import, editing, export, quit, and relaunch,
including real Photos authorization and external file grants. That qualification is already tracked
in [KRMA-1016](../.dg/issues/KRMA-1016.md); the reported Photos-import issue also retains a live
confirmation requirement in [KRMA-1040](../.dg/issues/KRMA-1040.md).

## Findings

### 1. P1 — Retrying an interrupted rollback can delete the file it restored

**Reproduced against the compiled production transaction implementation using disposable files.**

[`PortablePackageTransaction.rollback`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L1251)
moves a backup over its target. It does not durably record that this file has been rolled back.
If recovery stops after that move, or the journal survives cleanup, the next attempt sees a
`.published` file whose backup is absent and deletes the target at lines 1259–1260.

The absent backup is ambiguous: it can mean that the previous recovery already restored it.
Deleting the target in that state destroys the restored original. The transaction layer handles
canonical membership shards and asset records, so this can make a library unreadable or lose
canonical state after an interrupted recovery.

Reproduction:

1. Create a disposable package and an existing `State/value.txt` containing an old value.
2. Stage a replacement and fail commit at the existing `.publish` fault-injection boundary.
3. Simulate recovery stopping immediately after restoring its backup: remove the new target and
   move the journal's backup to the target, leaving the journal in place. These are the actual
   filesystem operations performed by rollback, not a fabricated journal state.
4. Invoke `PortablePackageTransaction.recover(at:)` again.

Observed: `Restored file exists before recovery retry: true`, then
`Restored file survives recovery retry: false`.

Required outcome: rollback must be safe to resume after every mutation and durability boundary.
Add recovery-interruption/retry tests, including a recovery that has restored some files before
failing. Existing tests cover interrupted publication and ownership contention well, but do not
establish that rollback itself can be interrupted safely.

### 2. P1 — Recovery accepts unchecked paths from the journal before deleting files

**Reproduced through the production package opener and expired-writer recovery path.**

[`recover(at:)`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L1214) removes
`packageRoot.appendingPathComponent(journal.stagingDirectory)` without validating that the path is
the expected transaction staging directory. The decoder accepts an arbitrary string. Rollback also
uses journal `backupPath` values as absolute filesystem paths at lines 1252 and 1272.

The ordinary package-path helper checks lexical and symlink containment, but these paths bypass it.
A malformed or tampered package journal can therefore direct destructive recovery operations at
unrelated data that the process has permission to access. This is an application boundary failure;
it is not a claim of bypassing the macOS sandbox.

The disposable probe created a valid package, an expendable sibling directory with a sentinel,
and a committed recovery journal whose staging path pointed at that sibling. It installed an
expired lease, then used `PortablePackageOpener.openBlocking` with confirmed takeover. The opener
completed and the sibling directory was gone:
`Unrelated sibling survives journal cleanup: false`.

Required outcome: validate the complete journal before any mutation. Staging and backup paths
must belong to the expected `Recovery/Staging/<transaction-id>` tree, not merely point somewhere
inside the package. Resolve paths through the containment boundary, reject symlink escapes and
unexpected journal identities, and preserve evidence when validation fails. Add hostile and
malformed journal tests using only disposable fixtures.

### 3. P1 — The production build verification rejects the newly added Photos entitlement

**Reproduced by running `scripts/app-store-build.sh`.** Xcode reports `BUILD SUCCEEDED`; resource
and metadata checks pass; the enclosing script exits 1 because
[`verify-app-signature.sh`](../scripts/verify-app-signature.sh#L29) still expects five sandbox
entitlements. [`App/Kromora.entitlements`](../App/Kromora.entitlements) now declares six.

Exact failure:

```text
embedded App Sandbox entitlements do not match the expected set:
missing=[], unexpected=['com.apple.security.personal-information.photos-library'], incorrect={}
```

The Photos fix and the signature allowlist need to agree on the intended capability set. Reconcile
the allowlist and acceptance/submission documentation, keep the strict unexpected-entitlement
check, and rerun production verification. Do not remove the capability merely to make the checker
green. This is a release-pipeline regression, not evidence that Apple's signature validation
rejected the app. `codesign --verify --deep --strict` itself succeeded before the custom check.

### 4. P2 — The UI smoke script exercises the retired export interaction

**Confirmed by tracing the current command route; not run interactively.**

[`smoke-macos-app.sh`](../scripts/smoke-macos-app.sh#L169) presses Command-S, waits for a window
named `Export`, edits a `Save As:` field, and clicks `Save`. The current export workflow sends one
photo as well as multiple photos through
[`ExportCoordinator.batchExportDialog`](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift#L484):
an `Export 1 Photo` setup step followed by a folder chooser with `Export Here`. There is no matching
single-file Save panel in that path.

On an interactive runner, the script will not complete the current workflow as written. CI also
[treats an unavailable UI session as a successful deferred smoke job](../.github/workflows/ci.yml#L128),
so a green job can mean that the UI path never ran. That environment policy should remain explicit
in release evidence.

Required outcome: update the smoke flow for setup, folder selection, and the generated output
filename, and run it in an isolated profile/package on a usable UI session. Successful test doubles
for panel configuration do not replace this packaged end-to-end check. The acceptance checklist's
single-file export/collision instructions also need alignment with the new workflow.

### 5. P2 — The zero-warning gate succeeds while emitting isolation warnings

**Reproduced by running `scripts/ci-tests.sh warning-gate`.** The command exits 0, but reports two
warnings in
[`PhotosReviewTransferCacheTests.swift`](../Tests/KromoraKitTests/PhotosReviewTransferCacheTests.swift#L9):
the nonisolated XCTest setup mutates the main-actor `directory` property, and teardown reads it.
The lane invokes `swift build --build-tests -Xswiftc -warnings-as-errors`, yet these diagnostics
remain warnings on the current Xcode-backed SwiftPM build.

This is test code, not a reproduced production race. It does mean the named zero-warning gate
does not establish the documented zero-diagnostic property. Correct the fixture's isolation and
verify that the actual compiler invocations/build configuration enforce the intended warning
policy. Do not treat an exit-0 build as a clean-diagnostics result without checking its output.

## What is good

- **Canonical ownership is clear.** Originals, membership, immutable edit revisions, and embedded
  Looks belong to the portable package. Local indexes and pixel/analysis caches can be rebuilt.
- **The rendering boundary is coherent.** Preview and export submit documents through the same
  rendering pipeline. There is real pixel, geometry, orientation, color, and metadata coverage,
  alongside fake-engine orchestration tests.
- **Concurrency is taken seriously.** Swift 6 language mode is enforced without the documented
  unsafe isolation escape hatches. Generation fences, bounded scheduler queues, explicit task
  ownership, and shutdown barriers address real stale-result and lifetime hazards.
- **Export handling has improved materially.** Per-asset documents win over the active photo's
  fallback; unreadable durable edits and missing Looks fail an item. Encoded output streams to a
  file, batches stay serial, and destination collision and partial-file cleanup behavior is tested.
- **Persistence distinguishes failure from success.** Failed edit snapshots and culling writes
  remain dirty, and termination can offer retry. The culling code also merges current queued and
  in-flight field intent rather than relying on an older index summary.
- **Resource retention has improved.** Offscreen decoded thumbnails release their pixels;
  diagnostics retain bounded records. Export/Share/bundle work is registered so shutdown can
  cancel and await it.
- **Dependency and platform scope is disciplined.** Apple frameworks only, a thin production
  launcher, and an arm64 executable with a macOS 26 deployment floor.

These are visible implementation improvements over the
[October 14 assessment](2026-10-14-release-readiness-review.md), not just closed ticket labels.

## Remaining quality risks

**Retouch acceptance remains permissive.** The shipping floor for automatic Heal on hair/fibre is
zero successful rows out of six; manual Heal and Clone each require two. The fixtures are 96×72.
This protects a measured baseline but cannot establish convincing repair quality on camera-sized
images. The [retouch guide](../docs/RETOUCH.md) is candid about the limits, and camera-scale inspection
remains in KRMA-1016. Review supported dust/speck and hair repairs at 100% before making strong
quality claims. Do not interpret these synthetic results as a measured real-photo failure rate.

**Total editor-session retention is not bounded.**
[`EditorDocumentCoordinator`](../Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift#L18)
retains a session for every opened or edited photo. Each history is capped at 100 entries, but the
number of sessions has no eviction budget. Value types and copy-on-write help; they do not provide
a whole-process memory ceiling. This is a risk to measure in a long editing session with substantial
mask/retouch recipes, not a claim of a reproduced memory crash.

**The composition root is still complex.** There are 278 Swift source files and approximately
93,007 source lines. `AppViewModel.swift` is 5,051 lines; rendering, package-session, and presentation
files also remain large. The coordinator extractions improve local reasoning, but cross-feature
ordering still depends on many root-owned state transitions. Line-count tests are useful trend
guards, not proofs of simplicity. Keep adding behavior tests across source changes, cancellation,
save failure, and shutdown. Refactor only where a concrete ownership problem justifies it while
preparing the release.

**Release evidence remains incomplete.** The package build is ad hoc signed with no TeamIdentifier.
This host runs macOS 27.2 with Xcode 27 beta/Swift 6.4. It does not establish macOS 26 behavior,
Apple distribution signing, TestFlight installation/update, actual Photos/iCloud import,
external-volume recovery, sandboxed external Look saves, VoiceOver, or visual transition quality.
Current manual acceptance documentation contains a template, not a completed pass for this build.

## Verification

- `scripts/ci-tests.sh fast`: **pass**, all 1,889 required deterministic tests; exit 0.
- Lane discovery: 2,683 total tests, 1,889 fast, 734 serial, 60 optional.
- `scripts/ci-tests.sh serial`: **pass**, 734 tests, one opt-in memory measurement skipped,
  zero failures; 333.6 seconds of test time; exit 0.
- `scripts/ci-tests.sh warning-gate`: **exit 0 with two test-isolation warnings**, 28.6 seconds
  of build time after waiting for the serial lane. This is not a clean zero-warning pass.
- `scripts/app-store-build.sh`: **fail**, exit 1 at the custom entitlement allowlist; Xcode Release
  compilation and the earlier metadata/resource checks succeeded.
- `scripts/verify-app-icon.sh`: **pass**. The production executable reports `arm64` only.
- Two disposable transaction probes: **both confirmed the reported defects**; they are failing
  product invariants, not passing acceptance tests. The unchecked-path probe also exercised
  production opening with confirmed expired-writer recovery.
- No interactive app smoke, user-library modifications, Apple-signed archive, TestFlight upload,
  optional RAW lane, or display-bound performance captures were performed.

Temporary evidence files: `/tmp/kromora-review-{fast,serial,warning-gate,package}.log`,
`/tmp/kromora-review-probe-results.log`, and `/tmp/kromora-release-review-probe.swift`.
The standalone probe was compiled against the debug `KromoraKit` library; all mutations stayed
inside its generated temporary fixture root. A brief test-process sample confirmed the long serial
test was actively working through its 1,000-asset fixture rather than stalled.

## Release recommendation

1. Fix the two recovery invariants with deterministic interruption and path-validation coverage.
2. Restore packaging verification, the current UI smoke flow, and the zero-warning check.
3. Freeze a candidate and complete the already-scoped signed-app qualification in KRMA-1016,
   including real Photos import confirmation from KRMA-1040 and camera-scale retouch review.
4. Use a small TestFlight cohort with real photography workloads and lower-memory Apple Silicon
   hardware before public availability. Record which exact build and workflows were exercised.

The most valuable next evidence is now successful recovery under repeated interruption and complete
workflows in the shipped sandboxed app.

## Follow-up ticket map

Created after the review at the user's request. Parent tracker:
[KRMA-1051](../.dg/issues/KRMA-1051.md). Each child contains its own reproduction/context,
acceptance criteria, implementation boundaries, verification commands, and machine-readable context.
Dependencies sequence overlapping fixes and keep hands-on evidence separate from implementation.

| Ticket | Scope |
| --- | --- |
| [KRMA-1052](../.dg/issues/KRMA-1052.md) | Validate recovery journal paths before any package mutation |
| [KRMA-1053](../.dg/issues/KRMA-1053.md) | Make transaction rollback safe after interruption and retry |
| [KRMA-1054](../.dg/issues/KRMA-1054.md) | Reconcile the Photos entitlement with strict production verification |
| [KRMA-1055](../.dg/issues/KRMA-1055.md) | Update packaged-app smoke coverage for export setup and folder selection |
| [KRMA-1056](../.dg/issues/KRMA-1056.md) | Remove XCTest isolation warnings from Photos review cache fixtures |
| [KRMA-1057](../.dg/issues/KRMA-1057.md) | Make the zero-warning gate reject emitted Swift diagnostics |
| [KRMA-1058](../.dg/issues/KRMA-1058.md) | Align sandbox acceptance and submission instructions with current export and Photos flows |
| [KRMA-1059](../.dg/issues/KRMA-1059.md) | Measure editor-session retention and define a finite working-set policy |
| [KRMA-1060](../.dg/issues/KRMA-1060.md) | Bound clean editor-session retention without evicting unsaved work |
| [KRMA-1061](../.dg/issues/KRMA-1061.md) | Isolate automatic hair-repair failures with deterministic camera-sized crops |
| [KRMA-1062](../.dg/issues/KRMA-1062.md) | Improve automatic Heal for supported hair repairs and raise its zero-success floor |
| [KRMA-1063](../.dg/issues/KRMA-1063.md) | Record camera-scale acceptance of supported retouch repairs |
| [KRMA-1064](../.dg/issues/KRMA-1064.md) | Qualify long editing sessions on 16 GB Apple Silicon hardware |
| [KRMA-1065](../.dg/issues/KRMA-1065.md) | Map and verify cross-feature source-switch and shutdown sequencing |
| [KRMA-1066](../.dg/issues/KRMA-1066.md) | Run a small TestFlight pilot against the frozen release candidate |

Existing [KRMA-1016](../.dg/issues/KRMA-1016.md) remains the signed-app qualification owner;
[KRMA-1040](../.dg/issues/KRMA-1040.md) retains the real Photos confirmation and Human blocker;
[KRMA-059](../.dg/issues/KRMA-059.md) consumes their evidence as the broad MVP gate. These were
updated in place rather than duplicated. No completed prior fix was reopened.
