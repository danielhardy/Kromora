---
id: KRMA-878
title: Guard AppViewModel.swift against regrowth with a line-count test
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:44.500Z
updated: 2026-10-11T13:33:50.341Z
depends_on:
  - KRMA-874
  - KRMA-875
  - KRMA-876
  - KRMA-877
blockers: []
order: zzzzy
board: product
---

After the extraction children land, add a test (similar in spirit to XcodeProjectInvariantTests/PackageSettingsTests) that fails when AppViewModel.swift exceeds a documented ceiling (suggest ~5,000 lines at that time), with a message pointing at docs/APP_ARCHITECTURE.md. Line count is a trend guard, not the goal. Do this last; set the ceiling from the measured size after the other children.
