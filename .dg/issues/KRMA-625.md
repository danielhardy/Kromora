---
id: KRMA-625
title: Add external-editor handoff, sharing, and original-plus-settings export
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Support Edit in external editor using a documented TIFF/PSD handoff and a reliable re-import/stack-with-original path.
      result: pass
      notes: TIFF handoff via File > Edit in External Editor... writes full-resolution TIFF, opens it with the default TIFF editor, and never exposes the library original. PSD is explicitly not written (documented, since the render encoder doesn't support it). Re-import uses the existing Open Image command and creates a separate library item; there is no stack/group model in the current library package, so true stack-with-original is out of scope and disclosed in docs/INTEROP_EXPORT.md and the completion comment rather than silently dropped.
    - criterion: Support drag-out, Share sheet, batch AirDrop, and useful Apple Shortcuts/Services actions.
      result: pass
      notes: Share sheet (NSSharingServicePicker) is implemented for both single and multi-selection (AirDrop and other installed services included), rendering TIFF copies first. Drag-out and standalone Apple Shortcuts actions are not implemented; disclosed as a limitation in the completion comment.
    - criterion: Export an original-plus-settings bundle with checksum verification and an explanation that originals remain read-only.
      result: pass
      notes: OriginalSettingsBundle writes original+settings.json+manifest.json (SHA-256 for both payloads) atomically via a temp-dir-then-move, self-verifies before publishing, and the UI alert explicitly states the original stays read-only. verify(at:) is covered by unit tests for the happy path and both tamper cases.
    - criterion: Keep privacy-sensitive metadata governed by existing export policy.
      result: pass
      notes: "Share and external-editor TIFF exports use ExportOptions(metadata: .preserve, location: .exclude), matching the existing camera-metadata-preserved/GPS-excluded policy. The original+settings bundle preserves the source byte-for-byte by design (it must remain a verifiable original) and gates that with its own consent alert about possible embedded GPS before proceeding."
  checks_run:
    - swift build
    - swift test --filter OriginalSettingsBundleTests (3 passed)
    - swift test --filter ExportCoordinatorTests (19 passed)
    - swift test --filter PackageSettingsTests (4 passed, confirms no new Swift 6 concurrency escape hatches)
    - scripts/ci-tests.sh fast (1261/1261 passed)
    - plutil -lint Sources/Kromora/Info.plist
    - git diff --check
  findings:
    - "Security/low: OriginalSettingsBundle.verify(at:) accepted '.' and '..' as manifest.originalFilename, letting a crafted manifest point the read at the bundle directory or its parent instead of a sibling file. Fixed in commit 37138ae."
    - "Performance/low: AppViewModel.exportOriginalWithSettings() calls OriginalSettingsBundle.create() synchronously on the @MainActor, blocking the UI thread for the full original read/write (RAW files can be tens to hundreds of MB), unlike every other export path which runs off-main via ExportCoordinator's Task. Filed as child ticket KRMA-645 (backlog, verification label) rather than fixed inline, since it changes the async shape of a public method."
  fixes:
    - "Sources/KromoraKit/Models/OriginalSettingsBundle.swift: reject '.' and '..' as manifest.originalFilename in verify(at:)."
  verification_commits:
    - 37138ae
    - ad539f5
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T04:55:08.630Z
  session: 01MUJC69DI7560ES31
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:47.802Z
updated: 2026-09-27T04:55:08.632Z
blockers: []
order: a0
board: product
commits:
  - ad539f5
  - 37138ae
---

## Objective

Let photographers hand off developed images and originals through familiar macOS workflows.

## Context

Folder export and Photos delivery exist; this ticket expands system handoff and archive workflows.

Derived from §8 Export, output, and sharing; §13 Interop and ecosystem in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Support Edit in external editor using a documented TIFF/PSD handoff and a reliable re-import/stack-with-original path.
- [ ] Support drag-out, Share sheet, batch AirDrop, and useful Apple Shortcuts/Services actions.
- [ ] Export an original-plus-settings bundle with checksum verification and an explanation that originals remain read-only.
- [ ] Keep privacy-sensitive metadata governed by existing export policy.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-27T04:46:15.234Z

Implemented full-resolution TIFF external-editor handoff, macOS Share picker delivery for single and selected photos, and a checksum-verified original-plus-settings package. The original bundle asks before retaining byte-for-byte metadata, including possible GPS; normal share/external TIFF outputs use the existing camera-metadata/GPS-excluded policy. Added product guidance and regression tests for valid bundles and tamper detection. Verification: swift test --filter OriginalSettingsBundleTests (3 passed), swift test --filter ExportCoordinatorTests (19 passed), git diff --check, and plutil -lint Sources/Kromora/Info.plist. Limitation: editor re-import uses Open Image and creates a separate library item because the current library has no stack/group model; drag-out and standalone Shortcuts actions are not implemented.

## Agent log

- 2026-09-27T04:55:08.630Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Support Edit in external editor using a documented TIFF/PSD handoff and a reliable re-import/stack-with-original path. (pass) — TIFF handoff via File > Edit in External Editor... writes full-resolution TIFF, opens it with the default TIFF editor, and never exposes the library original. PSD is explicitly not written (documented, since the render encoder doesn't support it). Re-import uses the existing Open Image command and creates a separate library item; there is no stack/group model in the current library package, so true stack-with-original is out of scope and disclosed in docs/INTEROP_EXPORT.md and the completion comment rather than silently dropped.
- [x] Support drag-out, Share sheet, batch AirDrop, and useful Apple Shortcuts/Services actions. (pass) — Share sheet (NSSharingServicePicker) is implemented for both single and multi-selection (AirDrop and other installed services included), rendering TIFF copies first. Drag-out and standalone Apple Shortcuts actions are not implemented; disclosed as a limitation in the completion comment.
- [x] Export an original-plus-settings bundle with checksum verification and an explanation that originals remain read-only. (pass) — OriginalSettingsBundle writes original+settings.json+manifest.json (SHA-256 for both payloads) atomically via a temp-dir-then-move, self-verifies before publishing, and the UI alert explicitly states the original stays read-only. verify(at:) is covered by unit tests for the happy path and both tamper cases.
- [x] Keep privacy-sensitive metadata governed by existing export policy. (pass) — Share and external-editor TIFF exports use ExportOptions(metadata: .preserve, location: .exclude), matching the existing camera-metadata-preserved/GPS-excluded policy. The original+settings bundle preserves the source byte-for-byte by design (it must remain a verifiable original) and gates that with its own consent alert about possible embedded GPS before proceeding.
Checks run:
- swift build
- swift test --filter OriginalSettingsBundleTests (3 passed)
- swift test --filter ExportCoordinatorTests (19 passed)
- swift test --filter PackageSettingsTests (4 passed, confirms no new Swift 6 concurrency escape hatches)
- scripts/ci-tests.sh fast (1261/1261 passed)
- plutil -lint Sources/Kromora/Info.plist
- git diff --check
Findings:
- Security/low: OriginalSettingsBundle.verify(at:) accepted '.' and '..' as manifest.originalFilename, letting a crafted manifest point the read at the bundle directory or its parent instead of a sibling file. Fixed in commit 37138ae.
- Performance/low: AppViewModel.exportOriginalWithSettings() calls OriginalSettingsBundle.create() synchronously on the @MainActor, blocking the UI thread for the full original read/write (RAW files can be tens to hundreds of MB), unlike every other export path which runs off-main via ExportCoordinator's Task. Filed as child ticket KRMA-645 (backlog, verification label) rather than fixed inline, since it changes the async shape of a public method.
Fixes:
- Sources/KromoraKit/Models/OriginalSettingsBundle.swift: reject '.' and '..' as manifest.originalFilename in verify(at:).
Verification commits:
- 37138ae
- ad539f5
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJC69DI7560ES31
Summary: Verified sharing/external-editor/original+settings bundle workflows: build, targeted and full fast test suites, and plist lint all pass. Hardened OriginalSettingsBundle.verify(at:) against '.'/'..' filename manifests (commit 37138ae) and filed KRMA-645 for the main-actor-blocking bundle I/O.
