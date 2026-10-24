---
id: KRMA-994
title: "Release readiness 2026-10-14: tracking epic"
type: task
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - release-readiness
  - readiness-2026-10-14
  - epic
created: 2026-10-14T16:08:51.303Z
updated: 2026-10-24T14:25:58.231Z
blockers: []
order: ayfnh7tq
board: product
context:
  files:
    - .context/2026-10-14-release-readiness-review.md
  docs:
    - CLAUDE.md
    - docs/PRODUCT_SCOPE.md
    - docs/TESTING.md
  issues:
    - KRMA-922
    - KRMA-941
    - KRMA-942
    - KRMA-952
    - KRMA-954
    - KRMA-963
  commands:
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh warning-gate
---

## Objective

Track every finding from `.context/2026-10-14-release-readiness-review.md` (reviewed `main` at `312f0537`) until each is fixed, explicitly decided, or consciously declined.

## Context

This is the successor to KRMA-922, which tracks the 2026-10-13 review. Do not close KRMA-922's remaining children because this epic exists. Several of those children were updated in place for the new evidence and stay parented to KRMA-922:

- KRMA-941 — Display P3 preview plan (finding 13). KRMA-923 already fixed the canvas color tag.
- KRMA-942 — stream export encoding to a file (finding 9).
- KRMA-952 — human decision on the warm-navigation budgets (finding 7). It now depends on KRMA-1002.
- KRMA-953 — shared hex encoder (finding 11, the small slice).
- KRMA-954 — structural render-identity plan (finding 11).
- KRMA-959 — checked thumbnail lock (architecture note on `uncheckedState`).
- KRMA-960 — v1 language decision before a String Catalog.
- KRMA-963 — texture pooling. Moved back to `backlog` because the new review says pooling before GPU-completion ownership can corrupt pixels.

KRMA-967 (ready) is the remaining `Task.yield()` wait cleanup. KRMA-1013 is the separate `StoredEditAdoptionTests` hang.

## Child tickets

Must fix before a public v1 claim:

- KRMA-995 — batch export fallback document
- KRMA-996 — culling dirty/retry/quit
- KRMA-997 — recovery ownership fence
- KRMA-998 — directory fsync failures
- KRMA-999 — decoded thumbnail retention
- KRMA-1000 — export/share/bundle job ownership
- KRMA-1001 — authoritative Select All

Needed for the requested quality bar, not silent data loss:

- KRMA-1002 — warm-navigation profile, no new capture
- KRMA-1003 — retouch acceptance gate
- KRMA-1004 — dust/speck repair, after the gate
- KRMA-1005 — lease renewal off the main actor
- KRMA-1006 — settings validation and shutdown index I/O
- KRMA-1007 — bounded diagnostic logs
- KRMA-1008 — batch output sharpening
- KRMA-1009 — Export Originals naming
- KRMA-1010 — Reduce Motion policy
- KRMA-1011 — relaunch sequencing
- KRMA-1012 — page-order cache
- KRMA-1013 — adoption-test timeouts
- KRMA-1014 — Core Image lane classification
- KRMA-1015 — current-behavior docs
- KRMA-1016 — signed-app qualification evidence

## Consciously not given a new implementation ticket

- Fine-grained Observation projections of `document`. File a child from KRMA-1002 only if a profile shows that invalidation on the warm path.
- HDR/EDR preview. Post-MVP. KRMA-941 must leave it out of the P3 plan.
- A general operation framework beyond the culling contract and the export/share/bundle jobs.
- Re-running the display-bound capture harness, or quietly lowering the 50/100 ms budgets. KRMA-952 is the decision.
- Implementing a String Catalog before the KRMA-960 language decision.

## Acceptance criteria

- [ ] Every child of this epic is `done`, or has a recorded decision explaining why it was declined.
- [ ] No child labelled `must-fix` remains open.
- [ ] `scripts/ci-tests.sh fast`, `serial`, and `warning-gate` exit 0 on the candidate that claims this epic is complete.

## Implementation notes

Do not implement product code under this ticket.


### Comment — codex @ 2026-10-19T17:03:31.170Z

Successor October 19 review tracker: KRMA-1051, with focused recovery, packaging, smoke, warnings, session-memory, retouch, lifecycle, and pilot children. Completed children of this epic remain closed. KRMA-1016 was updated in place as the shared signed-app qualification owner; no duplicate general acceptance issue was created.
