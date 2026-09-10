---
id: KRMA-023
title: Epic 4 — Photographic Light controls
type: feature
status: done
priority: urgent
labels:
  - mvp
  - epic
  - epic:light
  - phase:4
created: 2026-08-30T18:30:24.789Z
updated: 2026-09-10T12:53:35.726Z
depends_on:
  - KRMA-024
  - KRMA-025
  - KRMA-026
  - KRMA-027
  - KRMA-028
order: 1l0v3qrz
board: product
commits:
  - b7b4742
---

## Objective

Deliver predictable, real-time Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and Tone Curve controls on the shared pipeline.

## MVP outcome

- [x] Every Light control has photographer-facing units and a tested neutral.
- [x] Preview and export agree.
- [x] Highlight/shadow endpoint behavior is useful on representative photographs at interactive speed.

## Child tickets

- KRMA-024 — Define the Light adjustment model, ranges, order, and migration
- KRMA-025 — Refine Exposure, Contrast, Highlights, and Shadows behavior
- KRMA-026 — Implement Whites and Blacks endpoint controls
- KRMA-027 — Implement a versioned RGB tone curve model and renderer
- KRMA-028 — Ship the Light inspector with reset and interaction semantics

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

### Comment — codex @ 2026-08-31T20:13:16.206Z

Epic verification complete. Child tickets KRMA-024 through KRMA-028 are done and their shared Light implementation is present on main: photographer-facing Exposure (-5...+5 EV), Contrast/Highlights/Shadows/Whites/Blacks (-100...+100), and versioned master RGB tone curve; neutral Light is an exact identity; legacy documents retain their existing ordered nodes; Light runs in the shared GPU pipeline before legacy adjustments and LUTs; preview and full-resolution export use the same render path; and focused tests cover tonal behavior, endpoint rolloff, curve monotonicity, persistence, interaction, and preview/export parity. Verification: swift test passed (380 tests, 20 expected skips), swift build -c release passed, dg validate passed with only known warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T20:13:30.471Z: Verified Epic 4 Light controls across completed child tickets KRMA-024 through KRMA-028. All seven photographer-facing controls and the versioned master RGB curve are integrated in the shared GPU pipeline with exact neutral identity, legacy-document migration, useful tonal endpoint behavior, preview/export parity, and tested interaction semantics. swift test: 380 passed, 20 expected skips; swift build -c release passed; dg validate passed with known warnings.
