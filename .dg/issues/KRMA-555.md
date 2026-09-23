---
id: KRMA-555
title: "Verification hygiene: untracked helpers, format skew, dirty tree"
type: task
status: backlog
priority: high
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T15:00:55.501Z
updated: 2026-09-23T15:00:55.501Z
order: zq
board: product
parent: KRMA-548
---

## Objective

Reconcile the non-blocking verification findings from KRMA-548: untracked source files that
clean checkouts need, the local swift-format skew, and the dirty working tree — without
absorbing other tickets' work by accident.

## Context

Parent: KRMA-548 (counterpoint verification, 2026-09-23). None of these block the KRMA-548
test outcomes (the working tree builds and runs), but they affect CI and review.

## Acceptance criteria

- [ ] `Sources/KromoraKit/Models/PackageJSONCoder.swift` is committed. It is referenced by
  committed code (`PortablePackageImporter.encode`, introduced by `cbd9e5b`, KRMA-551
  verification) but was never `git add`ed, so any clean checkout at/after `cbd9e5b` —
  including KRMA-548's `b8d0842` — fails to compile (`cannot find 'PackageJSONCoder' in
  scope`; verified in a scratch worktree). Attribute it to the owning ticket, not to a
  drive-by commit.
- [ ] Decide the fate of the other untracked files from the same Sep-22 session:
  `Sources/KromoraKit/Models/PackagePath.swift`,
  `Sources/KromoraKit/Models/NumericClamping.swift`,
  `Tests/KromoraKitTests/PackagePathTests.swift`, plus the uncommitted tracked
  modifications that consume them (`PortableLibraryPackage.swift`,
  `PortablePackageTransaction.swift`, `CanvasNavigation.swift`, color/crop/light/local-mask
  models, `RenderPipeline.swift`, `RenderBoundarySourceResolver.swift`,
  `PackageSettingsTests.swift`, `docs/TESTING.md`). They compile in-tree and may belong to
  an in-flight hardening effort — confirm the owner before committing any of it.
- [ ] Re-check the Swift-format gate on CI (`macos-26`), not with the local Xcode-beta
  (Swift 6.4) toolchain: locally, `scripts/check-swift-format.sh` flags even pristine
  committed files (e.g. `OrderedImports`/`DoNotUseSemicolons` in `ImageCollection.swift`),
  so the local results cannot adjudicate the implementer's "lint passed" claim. Do NOT
  bulk-reformat with the beta toolchain.
- [ ] Reconcile the working tree per the project Git mode: ~55 dirty entries (`.dg`
  bookkeeping, the files above) plus a deep stash pile (`git stash list`). Verify with
  `git status --porcelain` after the agent runs that land here.
- [ ] Review item (no ticket split needed unless it grows): `b8d0842` added a
  `presentImportOutcome` early-return that suppresses import summaries (including
  partial-failure summaries) whenever a `Loading ...` status is showing, and
  `EmbeddedFirstFrameTests` dropped its `Loading first.ARW...` status assertion in the
  same commit. Confirm the status precedence is the intended UX, not test-serving.

## Implementation notes

Keep each fix with its owning ticket. Verification commits must stay limited to the
verified change; do not sweep unrelated WIP into a KRMA-548 commit.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
