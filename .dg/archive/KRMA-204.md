---
id: KRMA-204
title: Fixture photo corpus + golden semantic expectations
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 95ea9dc
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T17:27:24.612Z
  session: 01MTN80C2607DNJZZN
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:57.584Z
updated: 2026-09-10T12:53:46.916Z
depends_on:
  - KRMA-200
order: dtnwjkyo
board: product
commits:
  - 95ea9dc
---

**Type:** Task
**Component:** new `Tests/LumoKitTests/Fixtures/` additions + `Tests/LumoKitTests/PhotoIntelligenceCorpusTests.swift`
**Depends on:** KRMA-200
**Epic:** KRMA-181 — see `docs/ENGINEERING_GUIDE.md, original proposal §37–39

## 1. Problem

`AutoLightEngine` (KRMA-200) needs a permanent benchmark of representative photographs to guard
against regressions as it's tuned (KRMA-207). Per CLAUDE.md, fixtures are **generated, never
committed** — this ticket works within that constraint.

## 2. Requirement (acceptance criteria)

1. Extend `Tests/LumoKitTests/Fixtures.swift` (or a sibling file) with **synthetic, generated**
   fixture builders covering: normal daylight, backlit, high-key, low-key, flat/low-contrast,
   clipped highlights, clipped shadows — built procedurally (Core Image/Core Graphics drawing),
   matching the existing `.cube`/orientation-tagged-JPEG generator pattern.
2. A licensed-camera-file path for categories needing real photographic content (real faces, real
   scenes) follows the existing opt-in slow-lane convention: `LUMO_RAW_FIXTURE_DIR`, outside the
   checkout, skipped by default — mirror the existing RAW/hardware lane gating exactly.
3. `SemanticExpectation`-style predicates per fixture (not exact values): `"subject detected"`,
   `"face detected"`, `"subject darker than background"`, `"highlight clipping < 3%"`,
   `"backlightingLikelihood > .7"` — expressed as testable predicates over `PhotoAnalysis`.
4. `PhotoIntelligenceCorpusTests.swift` runs the full pipeline (mask providers → assembly →
   `PhotoAnalysis`) against every synthetic fixture and asserts expectations hold.
5. Realistic scope: dozens of synthetic fixtures, not hundreds — broader real-photo coverage
   depends on `LUMO_RAW_FIXTURE_DIR` availability and is out of scope to source here.
6. Swift 6 clean; test-only code, but no escape hatches.

## 3. Implementation notes

- Reuse `Fixtures.swift`'s `.cube` generation and orientation-tagged-JPEG helpers as building
  blocks (e.g. compositing a bright synthetic "sky" region behind a dark synthetic "subject" shape
  for the backlit case).
- Keep fixture generation fast — this runs in the deterministic CI lane, not the slow RAW lane,
  unless a fixture genuinely needs `LUMO_RAW_FIXTURE_DIR`.

## 4. Where to look

- `Tests/LumoKitTests/Fixtures.swift`.
- CLAUDE.md's Layout section — fixture-generation and `LUMO_RAW_FIXTURE_DIR` conventions.
- `docs/ENGINEERING_GUIDE.md

## 5. Testing

- This ticket *is* test infrastructure. Run `swift test --filter PhotoIntelligenceCorpusTests`
  and confirm every synthetic fixture's expectations pass; full `swift test` green.

## Agent log

- 2026-09-04T17:27:24.613Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 95ea9dc
Actor: codex
Resolved model: unknown
Pickup session: 01MTN80C2607DNJZZN
Summary: Added a generated 21-fixture photo-intelligence corpus covering daylight, backlight, high-key, low-key, flat contrast, and clipping scenarios with luminance variants; fixtures exercise coordinator, semantic mask provider, MaskStore, masked/global analyzers, PhotoAnalysis assembly, and scene inference.
