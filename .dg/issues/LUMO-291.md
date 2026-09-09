---
id: LUMO-291
title: Defer first settled preview until stored edits resolve
type: feature
status: done
priority: urgent
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
labels:
  - performance
  - preview
  - open-path
created: 2026-09-08T23:48:28.413Z
updated: 2026-09-09T00:23:31.751Z
order: w
board: product
commits:
  - f97a29e
  - ef9af97
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Opening an edited photo submits one settled preview with the stored document.
      result: pass
      notes: PreviewCutoverTests.testOpeningStoredEditsSubmitsOnePreviewWithTheStoredDocument persists a non-identity document, opens it through the collection path, verifies the request carries that document, and asserts exactly one raster preview request.
    - criterion: Opening an unedited photo remains single-submit and navigation does not duplicate admission.
      result: pass
      notes: PreviewCutoverTests.testTheDocumentReachesTheEngine asserts one preview for an unedited open; FilmstripNavigationTests.testEachFilmstripOpenSubmitsOneSettledPreview asserts one request for each of two navigated photos, including a stored edit.
    - criterion: Stale navigation and load-failure behavior remain fenced.
      result: pass
      notes: Existing rapid-navigation and failed-source lifecycle coverage remains green in the fast lane; sourceRevision and assetID guards are unchanged.
  checks_run:
    - swift test --filter PreviewCutoverTests|FilmstripNavigationTests (16 tests, 1 expected RAW skip, 0 failures)
    - scripts/ci-tests.sh fast (643 required tests, exit 0)
    - git diff --check
    - dg validate (OK; only pre-existing model/context warnings)
  findings: []
  fixes: []
  verification_commits:
    - ef9af97
    - f97a29e
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T00:23:31.748Z
  session: 01MTTCNI6PJXD8R5NT
---

## Objective

Single-view open of an edited photo submits exactly one settled preview instead of two.

## Context

Parent: LUMO-289. Today prepareAndInstall -> install() calls schedulePreview() with a pristine EditDocument, then adoptStoredEdits re-schedules with the disk document when it differs (Sources/LumoKit/ViewModels/AppViewModel.swift). The first render (RAW develop + mask Vision + GPU texture on the shared RenderEngine actor) is pure waste and blocks the real render behind it on the actor.

## Plan

- In install(), publish source chrome immediately (sourceImage marker, metadata, capabilities probe) but defer schedulePreview() until the stored edit load resolves and adoptStoredEdits has run.
- Keep the unedited path latency-neutral: the stored load already overlaps prepareSource, so waiting for it should add ~disk-read time, not felt latency. If the store read is slow, consider a timeout that previews the pristine document and supersedes on arrival — but measure first; prefer the simple await.
- Guard rapid navigation: the existing sourceRevision/assetID fences must still discard stale results.

## Acceptance

- Opening an edited photo submits one settled preview; opening an unedited photo is no slower than today.
- FilmstripNavigationTests / PreviewCutoverTests updated: assert single submission per open.
- No behavior change for load failure, missing stored edits, or mid-load navigation.

## Agent log

- 2026-09-09T00:23:31.750Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Opening an edited photo submits one settled preview with the stored document. (pass) — PreviewCutoverTests.testOpeningStoredEditsSubmitsOnePreviewWithTheStoredDocument persists a non-identity document, opens it through the collection path, verifies the request carries that document, and asserts exactly one raster preview request.
- [x] Opening an unedited photo remains single-submit and navigation does not duplicate admission. (pass) — PreviewCutoverTests.testTheDocumentReachesTheEngine asserts one preview for an unedited open; FilmstripNavigationTests.testEachFilmstripOpenSubmitsOneSettledPreview asserts one request for each of two navigated photos, including a stored edit.
- [x] Stale navigation and load-failure behavior remain fenced. (pass) — Existing rapid-navigation and failed-source lifecycle coverage remains green in the fast lane; sourceRevision and assetID guards are unchanged.
Checks run:
- swift test --filter PreviewCutoverTests|FilmstripNavigationTests (16 tests, 1 expected RAW skip, 0 failures)
- scripts/ci-tests.sh fast (643 required tests, exit 0)
- git diff --check
- dg validate (OK; only pre-existing model/context warnings)
Findings:
- None
Fixes:
- None
Verification commits:
- ef9af97
- f97a29e
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTTCNI6PJXD8R5NT
Summary: Deferred first preview admission is covered by stored-edit and filmstrip-navigation regressions; production gating is present in ef9af97 and test coverage is committed in f97a29e.
