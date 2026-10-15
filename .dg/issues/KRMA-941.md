---
id: KRMA-941
title: Verify the sRGB preview and export path for Instagram sharing
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Trace the sRGB render path through PreviewSurface and export encoding, including the display-profile transform and output profile.
      result: pass
      notes: Preview renders the shared graph in WorkingSpace.current (.sRGB), materializes the completed frame tagged sRGB, renders the presentation texture to sRGB, and sets MTKView.colorspace to sRGB. Apple documents that Core Animation performs the necessary color transformation when compositing an MTKView with its colorspace set. ExportOptions defaults to .current; RenderEngine uses the selected outputSpace for the same graph and passes its CGColorSpace to createCGImage before Image I/O encoding. See PreviewSurface.swift:1008-1039, 1180; RenderEngine.swift:1091-1111, 1248-1262; ExportOptions.swift:197-214; Apple MTKView.colorspace documentation.
    - criterion: Establish whether the default sRGB export and color-managed preview produce the same appearance; document the evidence and any limits of deterministic verification.
      result: pass
      notes: "The default path uses the same render graph, LUT interpolation space, and sRGB output encoding on preview and export. Existing RenderEngine tests cover preview raster parity and encoded profile tags. This establishes structural color agreement, not physical display accuracy: no calibrated display or colorimeter comparison was performed. JPEG/HEIF compression, sizing, and optional output sharpening can change image detail independently of color management."
    - criterion: Assess whether the optional Display P3 export is accurately represented in the preview. If not, recommend deferring it until that preview path exists.
      result: pass
      notes: The export model accepts Display P3, but no UI exposes that selection and the share workflow uses WorkingSpace.current. The canvas colorspace is fixed to WorkingSpace.current (.sRGB); a P3 export would therefore not be represented by the current preview. Keep P3 export unexposed until the editor has a matching P3 preview and the related Look/derive space handling is addressed.
    - criterion: Create focused child issues only for concrete gaps found. If the existing sRGB path already meets the goal, record that and create no implementation tickets.
      result: pass
      notes: No concrete implementation gap was found in the default sRGB path. No child issue was created. The unmeasured hardware color-accuracy limit is recorded here; docs/TESTING.md contains display-bound presentation/performance evidence, not colorimeter evidence.
    - criterion: Treat a matching color-space enum in a unit test as insufficient evidence of end-to-end display accuracy.
      result: pass
      notes: The conclusion is based on the full source path and Apple API behavior, with existing pixel/profile tests treated as supporting evidence only. Those tests do not exercise the physical display transform.
    - criterion: No production code changes in this planning issue.
      result: pass
      notes: Verification made no source or test edits; existing working-tree changes were left untouched.
  checks_run:
    - Static source trace of PreviewSurface, WorkingSpace, RenderEngine, ExportOptions, and export/share option construction; no source files changed.
    - Reviewed existing RenderEngine preview-raster parity and export-profile test definitions; tests were not run.
    - Reviewed Apple Developer Documentation for MTKView.colorspace and CIContext color-space behavior.
    - Issue context declares no automated checks (context.commands is empty); no command-based test suite was prescribed or run.
  findings:
    - No concrete gap found for the default sRGB preview/export color path. Actual connected-display color accuracy remains unmeasured; current docs/TESTING.md display captures measure presentation/performance and should not be described as colorimeter evidence.
    - Display P3 is supported by the export model but is not exposed in the UI; the current sRGB canvas cannot accurately represent a P3 export, so keep that option deferred.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T06:19:11.615Z
  session: 01MV95BYYGVY4D203H
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - color
created: 2026-10-13T14:47:51.052Z
updated: 2026-10-15T06:19:11.618Z
parent: KRMA-922
depends_on:
  - KRMA-923
blockers: []
order: a0
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
  commands: []
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T06:12:25.721Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Verify that Kromora's default sRGB canvas preview and sRGB export preserve the same SDR appearance for Instagram-oriented sharing. Record any concrete gap and create focused follow-up issues only when needed.

## Product direction

- Use sRGB as the default delivery target for the Instagram-first workflow.
- The color-managed preview should represent the exported sRGB appearance on the connected display.
- P3 working-space migration, printer-specific ICC soft-proofing, and HDR/EDR are out of scope.
- Assess the optional Display P3 export separately. If its result cannot be represented accurately in the preview, recommend deferring that option until the editor can preview it accurately.

## Context

- `WorkingSpace.current` and the default export color space currently resolve to sRGB.
- KRMA-923 added color-space tagging to the Metal view; that alone does not establish end-to-end preview-to-file appearance agreement.
- Keep this work focused on the sRGB path. Do not plan a P3 working-pipeline migration here.

## Prior P3 assessment (2026-10-14; deferred)

This ticket originally followed finding S2 in the 2026-10-13 release-readiness review and finding 13 in `.context/2026-10-14-release-readiness-review.md`. KRMA-923 is done: the Metal view sets its color space, but the canvas is still rendered with `WorkingSpace.current = .sRGB` and an 8-bit BGRA drawable. Derived LUTs are fitted in sRGB and would need migration or build-space tagging before a future P3 working-space change. Persistent frame signatures and cache identities would also need invalidation or versioning.

The former P3 plan called for checks of saturated P3 colors, gradients, canvas/thumbnail/export agreement, display changes, and derived-Look round trips. These remain useful context for a future P3 plan. The current Instagram-first decision defers that work. HDR/EDR remains post-MVP; accurate sRGB is a valid SDR product boundary.

## Acceptance criteria

- [ ] Trace the sRGB render path through `PreviewSurface` and export encoding, including the display-profile transform and output profile.
- [ ] Establish whether the default sRGB export and color-managed preview produce the same appearance; document the evidence and any limits of deterministic verification.
- [ ] Assess whether the optional Display P3 export is accurately represented in the preview. If not, recommend deferring it until that preview path exists.
- [ ] Create focused child issues only for concrete gaps found. If the existing sRGB path already meets the goal, record that and create no implementation tickets.
- [ ] Treat a matching color-space enum in a unit test as insufficient evidence of end-to-end display accuracy.
- [ ] No production code changes in this planning issue.

## Implementation notes

Keep `WorkingSpace.current = .sRGB` for this scope. Do not create child tickets for P3 working-space migration. Printer profiles, soft-proofing, and HDR/EDR remain outside this Instagram-first workflow.


### Comment — claude @ 2026-10-15T06:12:19.701Z

Verification result (no production changes, no child issues).

sRGB path trace (code reading):
- Preview: RenderEngine builds the graph with space = WorkingSpace.current (.sRGB); LUT interpolation uses that space (CubeLUT.makeFilter -> inputColorSpace). PreviewSurface.makePresentationTexture renders the CIImage into a bgra8Unorm texture with colorSpace sRGB, so texture bytes are sRGB-encoded. The MTKView is bgra8Unorm with view.colorspace = sRGB (KRMA-923, PreviewSurface.swift ~1180), so Core Animation/WindowServer converts sRGB -> connected-display profile. The CI fallback draw path also renders with frame.space (sRGB).
- Export: RenderEngine.encode uses outputSpace = exportOptions.colorSpace ?? request.space (sRGB by default; ExportWorkflowCoordinator uses .current). createCGImage(..., colorSpace: sRGB) -> CGImageDestination, so the file carries sRGB pixels and an sRGB profile.
- Same graph, same LUT interpolation space, same sRGB encoding on both sides. The only difference is the display transform, done by the system for the preview and by the viewer for the file. Conclusion: the default sRGB preview and export agree in design; no concrete gap found.

Limits of verification: the display transform happens in the compositor and cannot be asserted deterministically in unit tests (needs a real display/colorimeter). Existing tests (WorkingSpaceTests, ColorPipelineTests) cover the enum plumbing and LUT-space propagation only, which is not evidence of end-to-end display accuracy. Residual risk is covered by the release-time display evidence in docs/TESTING.md, not a new ticket.

Display P3 export: the model (ExportFormat capabilities, ExportOptions) accepts .displayP3 for JPEG/HEIF/PNG/TIFF, but no UI exposes it and nothing in the app sets it (options are built with .current). If enabled, the preview would NOT represent it: the canvas is always sRGB, and export would also interpolate LUTs in P3 (buildImage gets outputSpace) so Look results differ from the preview, and derived LUTs are fitted in sRGB. Recommendation: defer Display P3 export (keep it unexposed, ideally reject it at the model level only when a UI is proposed) until the editor can preview P3 accurately; that belongs to a future P3 working-space plan, which is out of scope here. HDR/EDR excluded.

Child issues created: none.

## Agent log

- 2026-10-15T06:19:11.615Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Trace the sRGB render path through PreviewSurface and export encoding, including the display-profile transform and output profile. (pass) — Preview renders the shared graph in WorkingSpace.current (.sRGB), materializes the completed frame tagged sRGB, renders the presentation texture to sRGB, and sets MTKView.colorspace to sRGB. Apple documents that Core Animation performs the necessary color transformation when compositing an MTKView with its colorspace set. ExportOptions defaults to .current; RenderEngine uses the selected outputSpace for the same graph and passes its CGColorSpace to createCGImage before Image I/O encoding. See PreviewSurface.swift:1008-1039, 1180; RenderEngine.swift:1091-1111, 1248-1262; ExportOptions.swift:197-214; Apple MTKView.colorspace documentation.
- [x] Establish whether the default sRGB export and color-managed preview produce the same appearance; document the evidence and any limits of deterministic verification. (pass) — The default path uses the same render graph, LUT interpolation space, and sRGB output encoding on preview and export. Existing RenderEngine tests cover preview raster parity and encoded profile tags. This establishes structural color agreement, not physical display accuracy: no calibrated display or colorimeter comparison was performed. JPEG/HEIF compression, sizing, and optional output sharpening can change image detail independently of color management.
- [x] Assess whether the optional Display P3 export is accurately represented in the preview. If not, recommend deferring it until that preview path exists. (pass) — The export model accepts Display P3, but no UI exposes that selection and the share workflow uses WorkingSpace.current. The canvas colorspace is fixed to WorkingSpace.current (.sRGB); a P3 export would therefore not be represented by the current preview. Keep P3 export unexposed until the editor has a matching P3 preview and the related Look/derive space handling is addressed.
- [x] Create focused child issues only for concrete gaps found. If the existing sRGB path already meets the goal, record that and create no implementation tickets. (pass) — No concrete implementation gap was found in the default sRGB path. No child issue was created. The unmeasured hardware color-accuracy limit is recorded here; docs/TESTING.md contains display-bound presentation/performance evidence, not colorimeter evidence.
- [x] Treat a matching color-space enum in a unit test as insufficient evidence of end-to-end display accuracy. (pass) — The conclusion is based on the full source path and Apple API behavior, with existing pixel/profile tests treated as supporting evidence only. Those tests do not exercise the physical display transform.
- [x] No production code changes in this planning issue. (pass) — Verification made no source or test edits; existing working-tree changes were left untouched.
Checks run:
- Static source trace of PreviewSurface, WorkingSpace, RenderEngine, ExportOptions, and export/share option construction; no source files changed.
- Reviewed existing RenderEngine preview-raster parity and export-profile test definitions; tests were not run.
- Reviewed Apple Developer Documentation for MTKView.colorspace and CIContext color-space behavior.
- Issue context declares no automated checks (context.commands is empty); no command-based test suite was prescribed or run.
Findings:
- No concrete gap found for the default sRGB preview/export color path. Actual connected-display color accuracy remains unmeasured; current docs/TESTING.md display captures measure presentation/performance and should not be described as colorimeter evidence.
- Display P3 is supported by the export model but is not exposed in the UI; the current sRGB canvas cannot accurately represent a P3 export, so keep that option deferred.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV95BYYGVY4D203H
Summary: Verified the default sRGB preview/export path by source trace; no production gap or child issue. Recorded that device colorimetry is unmeasured and Display P3 remains deferred.
