---
id: KRMA-784
title: "App Sandbox audit 2/3: export, Photos, storage, caches, and temp files"
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Section 2 exists and covers every bullet with file:line evidence; section 1 unchanged
      result: pass
      notes: Section 2 covers exports, Photos, storage/caches, Look folders, and paths. Only the shared intro paragraph was extended to mention section 2; section 1 body is untouched.
    - criterion: Each blocker or should-fix has a linked backlog issue ID
      result: pass
      notes: KRMA-818 and KRMA-819 exist.
    - criterion: Clear yes/no on pictures.read-write and removable-media.read-only
      result: pass
      notes: Both YES with rationale; consistent with Kromora.entitlements and KromoraStorage Pictures paths.
    - criterion: No source, test, or script files modified
      result: pass
      notes: Commit 059cbb22 touches only docs and .dg files.
  checks_run:
    - "Spot-checked citations: ExportCoordinator.write staging (606-623), DeriveCoordinator.performSave (204-213), KromoraStorage picturesDirectory/default package (64-96), PhotosDelivery.deliver authorization (89-100), Kromora.entitlements, homeDirectoryForCurrentUser grep (only KromoraStorage:66)"
    - git show --stat HEAD for scope of changes
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T16:44:01.013Z
  session: 01MUU1VG50QBEV9C4Y
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - audit
  - sandbox
created: 2026-10-03T19:24:11.530Z
updated: 2026-10-04T16:44:01.017Z
depends_on:
  - KRMA-783
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T16:43:16.044Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Audit the write/output side of Kromora for sandbox safety and append it to the audit document started by the previous ticket.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 0). In a sandboxed app, `FileManager` locations like Application Support, Caches, and temporary directories resolve inside the app container, which changes where data lands compared with `swift run`. Files to review under `Sources/KromoraKit/`: `ViewModels/ExportCoordinator.swift`, `Models/ExportOptions.swift`, `Models/ExportFormat.swift`, `Models/PhotosDelivery.swift`, `Models/KromoraStorage.swift`, `Models/KromoraSettings.swift`, `Models/LUTLibrary.swift`, `ViewModels/LookSaveCoordinator.swift`, `ViewModels/DeriveCoordinator.swift`, `Presentation/AppKitSettingsFolderAdapter.swift`, `Models/LatestPreviewFrameStore.swift`, `Models/PortablePackageMaintenance.swift`. Read `docs/STORAGE_POLICY.md` and `docs/INTEROP_EXPORT.md`. Existing section 1 of `docs/APP_STORE_SANDBOX_AUDIT.md` was written by the previous ticket; do not edit it.

## Scope

Append section "2. Export, Photos, storage, caches" to `docs/APP_STORE_SANDBOX_AUDIT.md` covering, with file:line evidence:

- Export destinations: does every write target a user-selected URL (or its security-scoped parent) or a container path? Overwrite/collision behavior and atomic-write temp file location (a temp file beside the destination needs write access to that folder).
- Photos import and delivery: authorization states handled (denied, restricted, limited), and behavior when the user denies.
- Where the library index, caches, frame stores, and the edit database live in the sandbox container, and whether any absolute path is persisted in package or index data that would break when the container path changes.
- LUT/Look folders: bundled looks (read from the app bundle) versus user Look folders (needs bookmark access); the settings-folder picker.
- Any hard-coded path (`/Users/`, `NSHomeDirectory`, `homeDirectoryForCurrentUser`) and any use of `urls(for:in:)` locations.

Findings table and backlog-issue rules are the same as section 1 (blocker / should-fix / note; one issue per blocker or should-fix; no product code changes).

## Acceptance criteria

- [ ] Section 2 exists and covers every bullet above with file:line evidence; section 1 is unchanged.
- [ ] Each blocker or should-fix has a linked backlog issue ID.
- [ ] The document gives a clear yes/no conclusion on whether `com.apple.security.assets.pictures.read-write` is required by any code path today (PhotoKit does not need it; it grants ~/Pictures file access) and on whether `com.apple.security.files.removable-media.read-only` is exercised.
- [ ] No source, test, or script files are modified.

## Verification

- Reviewer spot-checks at least five cited references and the Pictures-entitlement conclusion.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T16:43:15.602Z

Appended section 2 to docs/APP_STORE_SANDBOX_AUDIT.md with file:line evidence for export destinations, staging and collisions; Photos import/delivery authorization; package, index, edit, frame, cache and temporary storage; Look folders/bookmarks; hard-coded and FileManager paths; and the Pictures/removable-media entitlement conclusions. Filed KRMA-819 (appstore) for derived-Look replacement data loss and linked existing KRMA-818 for selected-URL access lifetime risks. Static review only; no source, test, or script files changed. git diff --check passed; no signed sandbox run was performed. Section 1 content is unchanged. Commit 059cbb22.

## Agent log

- 2026-10-04T16:44:01.013Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Section 2 exists and covers every bullet with file:line evidence; section 1 unchanged (pass) — Section 2 covers exports, Photos, storage/caches, Look folders, and paths. Only the shared intro paragraph was extended to mention section 2; section 1 body is untouched.
- [x] Each blocker or should-fix has a linked backlog issue ID (pass) — KRMA-818 and KRMA-819 exist.
- [x] Clear yes/no on pictures.read-write and removable-media.read-only (pass) — Both YES with rationale; consistent with Kromora.entitlements and KromoraStorage Pictures paths.
- [x] No source, test, or script files modified (pass) — Commit 059cbb22 touches only docs and .dg files.
Checks run:
- Spot-checked citations: ExportCoordinator.write staging (606-623), DeriveCoordinator.performSave (204-213), KromoraStorage picturesDirectory/default package (64-96), PhotosDelivery.deliver authorization (89-100), Kromora.entitlements, homeDirectoryForCurrentUser grep (only KromoraStorage:66)
- git show --stat HEAD for scope of changes
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU1VG50QBEV9C4Y
