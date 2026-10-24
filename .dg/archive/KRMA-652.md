---
id: KRMA-652
title: Remove tone curve file import/export while preserving copy/paste reuse
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove Import…/Export… from tone-curve editor, retain channel selector, curve editing, per-channel Reset
      result: pass
      notes: "LightInspectorView.swift ToneCurveEditor: buttons removed, Picker and Reset button retained."
    - criterion: Remove dedicated tone-curve preset file workflow end to end (file-panel actions, preset-only model, preset-only tests, documented external format)
      result: pass
      notes: ToneCurvePreset struct, importToneCurvePreset/exportToneCurvePreset, and testToneCurvePresetHasPortableVersionedJSONFormat removed. ENGINEERING_GUIDE.md preset format paragraph replaced with copy/paste description. grep across Sources/docs found no remaining references outside historical .dg bookkeeping files.
    - criterion: Preserve tone-curve persistence in EditDocument/LightAdjustments; existing saved documents decode/render unchanged
      result: pass
      notes: LightToneCurve/ParametricToneCurve Codable models and LightAdjustments untouched aside from preset struct removal; LightAdjustmentsTests legacy-decode coverage still passes.
    - criterion: Preserve edit copy/paste incl. selective Light category copy, transferring master/R/G/B/parametric curves
      result: pass
      notes: New EditClipboardTests.testSelectiveLightCopyPasteTransfersEveryToneCurve asserts all five curve fields transfer through JSON round-trip + selective .light category paste.
    - criterion: Leave general edit clipboard commands/behavior unchanged, no new tone-curve-only transfer mechanism
      result: pass
      notes: EditClipboardPayload/applying(to:) logic unmodified; only a new regression test added.
    - criterion: Update affected documentation; verify with build and tests
      result: pass
      notes: docs/ENGINEERING_GUIDE.md updated. swift build clean; scripts/ci-tests.sh fast (1276 tests) and serial (430 tests) both exit 0.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - git diff --check 55c52e0~1 55c52e0
    - grep -rIn ToneCurvePreset|importToneCurvePreset|exportToneCurvePreset|kromora-tone-curves across Sources/docs
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T16:57:27.298Z
  session: 01MUK20AYN2V2Y5DOY
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - cleanup
created: 2026-09-27T15:48:02.375Z
updated: 2026-09-28T14:41:33.509Z
blockers: []
order: jng6lsq1
board: product
---

## Objective

Remove tone-curve preset file import/export end to end. Users can already reuse curve adjustments through the edit copy/paste workflow, so keep that workflow intact and make sure copied Light adjustments continue to carry all tone curves.

## Context

Tone curve Import… and Export… controls expose a separate JSON file workflow that is redundant with copying and pasting edits. The existing preset format contains only the master and RGB curves, making it narrower than the broader edit transfer workflow. This is a product simplification; tone-curve editing itself remains part of the Light inspector.

Relevant implementation and documentation:

- `Sources/KromoraKit/Views/LightInspectorView.swift` — tone-curve editor UI and Import/Export buttons.
- `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift` — file panel import/export actions.
- `Sources/KromoraKit/Models/LightAdjustments.swift` — `ToneCurvePreset` file format model, alongside durable edit-document tone-curve models.
- `Sources/KromoraKit/Models/EditClipboard.swift` and `Sources/KromoraKit/ViewModels/AppViewModel.swift` — value-only edit transfer, including selective category copy/paste.
- `docs/ENGINEERING_GUIDE.md` — tone-curve persistence and preset format documentation.

## Acceptance criteria

- [ ] Remove Import… and Export… from the tone-curve editor while retaining the channel selector, curve editing, and per-channel Reset behavior.
- [ ] Remove the dedicated tone-curve preset file workflow end to end: file-panel actions, preset-only serialization/model code, and tests that exist only for preset file import/export. Remove the documented external preset format contract.
- [ ] Preserve tone-curve persistence in `EditDocument`/`LightAdjustments`; existing saved edit documents and curve Codable schemas must continue to decode and render as before.
- [ ] Preserve existing edit copy/paste, including selective copying of Light adjustments. Copying Light adjustments from one photo and pasting to another must transfer the master, red, green, blue, and parametric tone-curve values; add or update focused regression coverage if needed.
- [ ] Leave general edit clipboard commands and behavior unchanged, and do not replace them with a new tone-curve-only transfer mechanism.
- [ ] Update any affected documentation and verify with the relevant build and tests.

## Implementation notes

Inspect the current working tree before editing and preserve unrelated pre-existing changes. `ToneCurvePreset` appears to be the file-transfer boundary; distinguish it from `LightToneCurve`, `ParametricToneCurve`, and the Codable fields used by persisted edit documents. Search for all preset references before removal so no dead import/export paths or stale documentation remain. Keep macOS 14, Swift 6, and zero-dependency constraints.

### Comment — codex @ 2026-09-27T16:49:31.110Z

Removed tone-curve JSON import/export and its preset model/format docs while retaining curve editing and reset. Added selective Light clipboard regression coverage for master, RGB, and parametric curves; persisted edit schemas remain covered. Verified: swift build; swift test --filter EditClipboardTests (7 passed); swift test --filter LightAdjustmentsTests (17 passed); git diff --check. Commit: 55c52e0.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T16:57:27.298Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove Import…/Export… from tone-curve editor, retain channel selector, curve editing, per-channel Reset (pass) — LightInspectorView.swift ToneCurveEditor: buttons removed, Picker and Reset button retained.
- [x] Remove dedicated tone-curve preset file workflow end to end (file-panel actions, preset-only model, preset-only tests, documented external format) (pass) — ToneCurvePreset struct, importToneCurvePreset/exportToneCurvePreset, and testToneCurvePresetHasPortableVersionedJSONFormat removed. ENGINEERING_GUIDE.md preset format paragraph replaced with copy/paste description. grep across Sources/docs found no remaining references outside historical .dg bookkeeping files.
- [x] Preserve tone-curve persistence in EditDocument/LightAdjustments; existing saved documents decode/render unchanged (pass) — LightToneCurve/ParametricToneCurve Codable models and LightAdjustments untouched aside from preset struct removal; LightAdjustmentsTests legacy-decode coverage still passes.
- [x] Preserve edit copy/paste incl. selective Light category copy, transferring master/R/G/B/parametric curves (pass) — New EditClipboardTests.testSelectiveLightCopyPasteTransfersEveryToneCurve asserts all five curve fields transfer through JSON round-trip + selective .light category paste.
- [x] Leave general edit clipboard commands/behavior unchanged, no new tone-curve-only transfer mechanism (pass) — EditClipboardPayload/applying(to:) logic unmodified; only a new regression test added.
- [x] Update affected documentation; verify with build and tests (pass) — docs/ENGINEERING_GUIDE.md updated. swift build clean; scripts/ci-tests.sh fast (1276 tests) and serial (430 tests) both exit 0.
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- git diff --check 55c52e0~1 55c52e0
- grep -rIn ToneCurvePreset|importToneCurvePreset|exportToneCurvePreset|kromora-tone-curves across Sources/docs
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK20AYN2V2Y5DOY
Summary: Verified tone-curve preset file-transfer removal: preset model/API/tests/docs removed cleanly, no dead references remain, copy/paste still transfers all tone curves (new regression test), build and full fast+serial CI suites pass.
