---
id: KRMA-783
title: "App Sandbox audit 1/3: import, open, drag-drop, and security-scoped access"
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
created: 2026-10-03T19:24:10.491Z
updated: 2026-10-03T19:25:42.014Z
blockers: []
order: n
board: product
---

## Objective

Find every place where Kromora's file access works under unrestricted `swift run` but could fail inside the App Sandbox, for the import/open side of the app, and record findings in a new audit document.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 0). `swift run` executes as an unrestricted developer process, so it is not proof the sandboxed app works. Current entitlements (`Sources/Kromora/Kromora.entitlements`): app-sandbox, user-selected read-write, removable-media read-only, app-scope bookmarks, pictures read-write, network client. Files to review (all under `Sources/KromoraKit/`): `Models/PhotoAsset.swift`, `Models/MediaVolume.swift`, `Models/PortableLibrarySession.swift`, `Models/ImageDecoder.swift`, `Models/ImageSource.swift`, `ViewModels/LibraryMediaWorkflowCoordinator.swift`, `ViewModels/AppViewModel.swift`, `Presentation/AppKitFileDialogAdapter.swift`. Use `grep -rn startAccessingSecurityScopedResource Sources` (8 call sites) and `grep -rn bookmarkData Sources` to find the rest. Read `docs/STORAGE_POLICY.md` for the intended ownership model.

## Scope

Create `docs/APP_STORE_SANDBOX_AUDIT.md` with a section "1. Import, open, and persistent file access" that, for each of these topics, states what the code does, whether it is sandbox-safe, and evidence (file:line):

- Open/save/import panels and the entitlement each relies on.
- Drag-and-drop of file URLs and folders onto the window: does the code obtain sandbox access for dropped URLs?
- Security-scoped bookmarks: where created, resolved, stale-bookmark handling, and whether every `startAccessing…` has a matching `stopAccessing…` on all paths (including errors and cancellation).
- Reopening the last library package after relaunch: does access survive a relaunch without a fresh panel?
- RAW and sidecar access next to a user-selected original (sandbox grants the selected file only, not siblings).
- Removable-volume access (`MediaVolume`) given the read-only entitlement.

For each defect or risk, add a row to a "Findings" table with severity (blocker / should-fix / note) and file a separate backlog issue (`dg issue create`, label `appstore`) for each blocker or should-fix. Do not change product code in this ticket.

## Acceptance criteria

- [ ] `docs/APP_STORE_SANDBOX_AUDIT.md` exists with section 1 covering every bullet above, each with file:line evidence.
- [ ] Every blocker or should-fix has a linked backlog issue ID in the Findings table; notes are labelled as notes.
- [ ] No source, test, or script files are modified.
- [ ] The document states explicitly which behaviors could not be proven by reading code and need a sandboxed run (these feed the acceptance checklist ticket).

## Verification

- Reviewer spot-checks at least five cited file:line references and the bookmark start/stop pairing claim.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
