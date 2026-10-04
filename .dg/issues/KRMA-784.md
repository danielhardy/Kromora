---
id: KRMA-784
title: "App Sandbox audit 2/3: export, Photos, storage, caches, and temp files"
type: task
status: ready
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - audit
  - sandbox
created: 2026-10-03T19:24:11.530Z
updated: 2026-10-03T19:25:42.613Z
depends_on:
  - KRMA-783
blockers: []
order: t
board: product
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
