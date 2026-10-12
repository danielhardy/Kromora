---
id: KRMA-893
title: Give starter Looks a stable ID instead of an install path
type: bug
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - looks
  - persistence
created: 2026-10-12T12:47:35.152Z
updated: 2026-10-12T12:47:35.152Z
blockers: []
order: t
board: product
---

## Objective

Give starter Looks a stable ID instead of an install path

## Context

Observed with `log stream` (category `photo-switch`): a saved edit's Look is `LUTID(raw: "/Applications/Kromora.app/Contents/Resources/Kromora_KromoraKit.bundle/.../StarterLooks/infrared-mono.cube")`. `CubeLUT.id` is the full file path, so a starter Look applied in one build (installed app) cannot be matched to the same Look in another build (`swift run`, TestFlight update, moved app). The render then gets `lut == nil` and draws the photo ungraded, which shows as a Look that flashes on photo switch and disappears. Confirmed by the maintainer in both builds. Related: KRMA-894.

## Acceptance criteria

- [ ] Starter (bundled) Looks have an ID independent of the install location (for example a stable name or content hash); user-imported Looks keep their existing identity rules.
- [ ] An edit saved by one build resolves its starter Look in another build of the app.
- [ ] A test applies a starter Look, simulates a different bundle path, and asserts the render request still carries the Look.
- [ ] `swift build` and `scripts/ci-tests.sh fast` pass.

## Implementation notes

No migration is required: only the maintainer has an install and will start over. Check `LUTID`, `CubeLUT.id`, `LookSignature`, and wherever a document's `LUTSettings.lutID` is resolved to a loaded `CubeLUT` for the render request. Keep the zero-third-party and macOS 26 constraints.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
