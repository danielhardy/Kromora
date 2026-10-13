---
id: KRMA-987
title: "Guard the Observation convention: CLAUDE.md rule and ObservableObject allowlist test"
type: task
status: backlog
priority: medium
agent: claude
human_review_required: false
model: sonnet
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - observation
  - swiftui
  - maintainability
created: 2026-10-13T22:11:31.143Z
updated: 2026-10-13T22:11:31.143Z
blockers: []
order: zzzzzzq
board: product
---

## Objective

Make new UI-facing state use Observation by default, enforced by a test rather than by prose alone: add a rule to `CLAUDE.md` and a source-scan test that fails when a new `ObservableObject` is declared outside a shrinking allowlist of the types still awaiting conversion.

## Context

See `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md`. KRMA-521 already moved the high-frequency children to `@Observable`, and the migration (KRMA-907 to KRMA-909 in Phase 1, KRMA-972 to KRMA-981 in optional Phase 2) will convert the rest only if the go/no-go gate says so. Whatever happens there, new code should not add to the problem, and agents default to Combine-era patterns (`ObservableObject`, `@Published`, `@ObservedObject`) unless told otherwise. This ticket has no dependencies and should land early.

Do not edit `.dg/AGENTS.md`; DispatchGraph generates it. `CLAUDE.md` is the canonical shared guidance (root `AGENTS.md` points to it).

The 15 classes that declare `ObservableObject` today (verified 2026-10-13 with `grep -rn "ObservableObject" Sources`): `AppViewModel`, `AppViewModel.InspectorState`, `KromoraSettings`, `LUTLibrary`, `LibraryMediaWorkflowCoordinator`, `EditorDocumentCoordinator`, `EditClipboardCoordinator`, `DeriveCoordinator`, `LookSaveCoordinator`, `MaskInteractionState`, `RetouchInteractionState`, `MaskDiscoveryState`, `PreviewSurface` (in `Views/`), `MaskingPanelModel`, `AnalysisDebugPanelModel`. Regenerate the list before writing the allowlist.

Existing scan style to copy: `Tests/KromoraKitTests/ObservationInvalidationTests.swift` (source-scan tests) and `PackageSettingsTests` (file-reading structural tests such as `testAppViewModelDoesNotRegrow`).

## Approach

1. **CLAUDE.md.** Add a short "Observation" subsection under the Swift 6 section, roughly:
   - New UI-facing state is `@MainActor @Observable final class`. Do not add new `ObservableObject` or `@Published` types.
   - Hold it in views with a plain `let`/`var`, `@Bindable` when the view needs `$x.prop`, or `@State` for view-owned state. Never wrap an `@Observable` type in `@StateObject`/`@ObservedObject`.
   - Mark storage that views never read (tasks, closures, caches, injected collaborators) `@ObservationIgnored`. `@Observable` rejects `lazy` stored properties, so use `@ObservationIgnored` there too.
   - A view updates only for properties its `body` reads during that evaluation. Reads inside `.task`, gesture or `onChange` closures are not tracked.
   - Do not add entries to the `AppViewModel` child-forwarding loop. New child state is observed directly by the views that show it.
   - Prefer one small state object per surface over adding properties to `AppViewModel` (which has a line ceiling in `PackageSettingsTests`).
   Keep it to about ten lines and link the plan doc.
2. **Test.** Add `testObservableObjectDeclarationsMatchAllowlist` to `ObservationInvalidationTests` (fast lane; it only reads source files). Scan every `*.swift` under `Sources/KromoraKit` for type declarations conforming to `ObservableObject` (including nested types such as `AppViewModel.InspectorState`; match the declaration line, ignore comments and strings) and assert the set equals a hard-coded allowlist of the 15 names. Fail with a message that says: new UI state should be `@Observable`; if you are converting a type, remove it from the allowlist in the same change. Also assert that a type on the allowlist that no longer declares `ObservableObject` fails the test, so the list must shrink as steps land.
3. A second assertion in the same test: no file under `Sources/KromoraKit` declares `@StateObject` or `@ObservedObject` for a type that is `@Observable` (generalises the existing `testObservableTypesAreNotWrappedInStateObject`, which only documents the contract). Derive the `@Observable` type names from the scan.

## Acceptance criteria

- [ ] `CLAUDE.md` has the Observation rule described above (about ten lines, links `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md`), and `.dg/AGENTS.md` is unchanged.
- [ ] A fast-lane test fails if a new `ObservableObject` type is added anywhere in `Sources/KromoraKit`, and fails if an allowlisted type has been converted but left on the list. Demonstrate both by temporarily adding and removing a declaration locally (do not commit that).
- [ ] A test fails if an `@Observable` type is held with `@StateObject`/`@ObservedObject`.
- [ ] The allowlist contains exactly the 15 current types, each with a one-line comment naming the migration ticket that removes it (KRMA-907/908/909 or the Phase 2 step).
- [ ] Zero changes to production code under `Sources/`; `swift build` and `scripts/ci-tests.sh fast` pass; the new test is not added to `serial_filter`.

## Verification

```
swift build
scripts/ci-tests.sh fast
```

## Notes for the migration tickets

When KRMA-907, 908, 909 and each Phase 2 step convert a type, they must remove it from this allowlist in the same commit. Add that sentence to the "Common rules" in the plan doc as part of this ticket.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
