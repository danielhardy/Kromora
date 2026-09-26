---
id: KRMA-625
title: Add external-editor handoff, sharing, and original-plus-settings export
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:47.802Z
updated: 2026-09-26T13:56:48.094Z
blockers: []
order: zzh
board: product
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
