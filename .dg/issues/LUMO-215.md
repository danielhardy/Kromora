---
id: LUMO-215
title: Restore Histogram and Auto after thumbnail photo switching
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: thumbnail switching restores the selected photo histogram without an inspector-tab change
      result: pass
    - criterion: Auto becomes available only after the newly selected photo preview is ready
      result: pass
    - criterion: rapid and back-and-forth changes cannot publish stale state
      result: pass
    - criterion: focused regression coverage exists
      result: pass
  checks_run:
    - swift test focused lifecycle suites
    - git diff --check
  findings:
    - Full swift test currently reports 12 unrelated pre-existing failures in develop/persistence tests; all issue-focused suites pass.
  fixes:
    - Propagated PhotoAssetID through preview tokens/publications and guarded every relevant async completion.
    - Kept explicit terminal histogram errors and last-valid preview behavior.
  verification_commits:
    - d8b0b91
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T21:36:24.901Z
  session: 01MTNGNRQVXVLFLIC3
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - regression
  - navigation
  - photo-loading
  - rendering
  - histogram
  - auto
created: 2026-09-04T20:31:53.304Z
updated: 2026-09-07T04:02:46.381Z
depends_on:
  - LUMO-143
  - LUMO-209
order: eornbt0u
board: product
commits:
  - d8b0b91
---

## Objective

Keep the Histogram and Auto controls usable after switching photos with a filmstrip or library
thumbnail.

## Context

After opening the editor and switching between images using a thumbnail, the selected photo can
render while the Inspect panel reports `Histogram unavailable`. At the same time, the Auto action
is no longer available. This appears to be a regression or an incomplete lifecycle handoff across
the completed thumbnail-switch stabilization work in LUMO-143 and the Auto availability work in
LUMO-209. The failure makes the editor look partially detached from the newly selected image and
may require another navigation or tab change to recover.

## Acceptance criteria

- [ ] Selecting another supported photo from the filmstrip or library thumbnail eventually shows
      that photo's histogram in Inspect, without requiring an inspector-tab change; genuine
      histogram calculation failures remain explicit and actionable.
- [ ] Auto remains discoverable and becomes enabled once the newly selected photo's preview is
      ready; its availability is not tied to a stale histogram result or the previously selected
      photo.
- [ ] Rapid, repeated, and back-and-forth thumbnail changes cannot publish a stale histogram or
      Auto state for an earlier photo.
- [ ] Add focused regression coverage for normal thumbnail switching with Inspect open, repeated
      selection, rapid switching, and recovery after a delayed or failed histogram/render result.

## Implementation notes

- Trace source, display, preview-presentation, histogram, and Auto generations across the thumbnail
  selection path. Every async completion must prove it still belongs to the active PhotoAssetID.
- Preserve the existing last-valid-frame and explicit terminal-error behavior; do not hide a real
  unsupported-source or histogram failure behind an enabled control.
- Related completed issues: LUMO-143 (thumbnail-switch lifecycle) and LUMO-209 (Auto availability).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T21:36:24.903Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] thumbnail switching restores the selected photo histogram without an inspector-tab change (pass)
- [x] Auto becomes available only after the newly selected photo preview is ready (pass)
- [x] rapid and back-and-forth changes cannot publish stale state (pass)
- [x] focused regression coverage exists (pass)
Checks run:
- swift test focused lifecycle suites
- git diff --check
Findings:
- Full swift test currently reports 12 unrelated pre-existing failures in develop/persistence tests; all issue-focused suites pass.
Fixes:
- Propagated PhotoAssetID through preview tokens/publications and guarded every relevant async completion.
- Kept explicit terminal histogram errors and last-valid preview behavior.
Verification commits:
- d8b0b91
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNGNRQVXVLFLIC3
Summary: Histogram and Auto now follow the active PhotoAssetID across thumbnail navigation; stale preview, presentation, histogram, Auto, source-preparation, metadata, capability, comparison, and prefetch completions are rejected. Added focused lifecycle and equal-source race coverage.
