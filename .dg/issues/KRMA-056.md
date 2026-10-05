---
id: KRMA-056
title: Create the curated image-quality validation matrix and rubric
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:36.467Z
updated: 2026-10-05T14:36:58.165Z
blockers: []
estimate: 5
order: 3sf5omqi
board: product
---

## Objective

Create a small, repeatable image-quality check for representative inputs and the core edit workflow.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. Use the current README and render/storage contracts as product context. `.context/initial_concept.md` is historical provenance, not a current feature checklist. Preserve existing image behavior unless a reproducible defect is found.

## Scope

- Select a modest set of representative RAW and standard-image examples, including difficult exposure and color cases relevant to shipped controls.
- Define a concise qualitative review rubric for correct adjustment behavior and preview/export consistency.
- Keep local/licensed samples out of the repository unless their redistribution is explicitly approved.
- Record only reproducible correctness failures as follow-up issues.

## Acceptance criteria

- [ ] The chosen sample set and its licensing/storage rules are documented.
- [ ] A reviewer can repeat the checks and record a clear pass, failure, or subjective observation.
- [ ] The core edit path and preview/export parity receive a baseline review.
- [ ] Any reported defect includes a reproducible image/workflow and expected behavior.

## Verification

- Complete one baseline review pass and record summarized results without committing unlicensed source photos.

## Out of scope

- Exhaustive coverage of every control and scene combination.
- Pixel matching against Lightroom, Apple Photos, or camera JPEGs.
- Automated aesthetic scoring.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
