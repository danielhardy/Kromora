---
id: KRMA-783
title: "App Sandbox audit 1/3: import, open, drag-drop, and security-scoped access"
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: docs/APP_STORE_SANDBOX_AUDIT.md section 1 covers every bullet with file:line evidence
      result: pass
      notes: Spot-checked entitlements, MediaVolume 42-53/214-224, LibraryMediaWorkflowCoordinator 229-285, KromoraStorage 89-96, PreviewView 135-138; all accurate.
    - criterion: Every blocker/should-fix has linked backlog issue
      result: pass
      notes: KRMA-818 (backlog, appstore); other rows labelled note.
    - criterion: No source, test, or script files modified
      result: pass
      notes: Commit e130845a touches only the new doc.
    - criterion: Explicitly lists behaviors needing sandboxed run
      result: pass
      notes: Six sandboxed cases listed.
  checks_run:
    - "grep start/stopAccessingSecurityScopedResource: 8 start sites, all accounted for in the doc"
    - "git diff --check: clean"
    - "dg validate: OK (pre-existing model-name warnings)"
  findings: []
  fixes: []
  verification_commits:
    - e130845a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T16:18:00.693Z
  session: 01MUU0YBEAJKEKEALK
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - audit
  - sandbox
created: 2026-10-03T19:24:10.491Z
updated: 2026-10-04T16:18:00.700Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T16:17:28.656Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - e130845a
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


### Comment — codex @ 2026-10-04T16:17:24.211Z

Added docs/APP_STORE_SANDBOX_AUDIT.md with section 1 and file:line evidence for panel entitlements, drag-and-drop, bookmark resolution/staleness, scope pairing, relaunch, RAW sidecars, and removable media. Filed should-fix follow-up KRMA-818 (appstore) for file-access lifetimes. Static review only; the document lists the signed sandbox run cases still needed. Checks: dg validate (OK; existing model-name warnings) and git diff --check. Commit: e130845a.

## Agent log

- 2026-10-04T16:18:00.693Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] docs/APP_STORE_SANDBOX_AUDIT.md section 1 covers every bullet with file:line evidence (pass) — Spot-checked entitlements, MediaVolume 42-53/214-224, LibraryMediaWorkflowCoordinator 229-285, KromoraStorage 89-96, PreviewView 135-138; all accurate.
- [x] Every blocker/should-fix has linked backlog issue (pass) — KRMA-818 (backlog, appstore); other rows labelled note.
- [x] No source, test, or script files modified (pass) — Commit e130845a touches only the new doc.
- [x] Explicitly lists behaviors needing sandboxed run (pass) — Six sandboxed cases listed.
Checks run:
- grep start/stopAccessingSecurityScopedResource: 8 start sites, all accounted for in the doc
- git diff --check: clean
- dg validate: OK (pre-existing model-name warnings)
Findings:
- None
Fixes:
- None
Verification commits:
- e130845a
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU0YBEAJKEKEALK
Summary: Verified audit doc: citations spot-checked, 8 start sites confirmed, KRMA-818 filed for should-fix.
