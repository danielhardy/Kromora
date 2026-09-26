# Content-aware Auto policy

Content-aware Auto is a renderer-backed, non-destructive candidate selection workflow. The policy
proposes an editable document, then `ContentAwareAutoEngine` and its
`AutoEnhancementCoordinator` render the unchanged,
native, Apple-reference, and reduced-strength candidates through the same `RenderEngine` seam
used by preview and export. The selected document, including any measured regional correction
layers, is applied as one normal Auto history operation. Auto is shipped in the current editor;
this document records its behavior, not a future proposal.

## Availability and degraded mode

After a preview is ready, the shipping `RenderEngine` and imported photo identity select
`ContentAwareAutoEngine`; optional subject or semantic evidence may be missing without changing
that path. `ProductionAutoWorkflow` retains the versioned global histogram analyzer only for
alternate renderers that lack the sampling seam or requests without a photo identity. That mode
is explicitly degraded: its completion message names the histogram fallback and its reason. It
keeps the conservative global Light/Color behavior for renderer integrations and test doubles.

## Neutral target

The default neutral target is a perceptual luminance median of `0.48` in the renderer's sRGB
working space. The target is not an exposure offset: the proposed EV is
`log2(targetMedian / max(sourceP50, 0.03))`, then bounded by the photographic correction caps.

The target uses robust tone-distribution evidence from the current developed/rendered image:

- `p50` measures mid-tone placement and drives the EV estimate.
- `p10` and `p05` describe shadow structure and help detect a broad, recoverable scene rather
  than a flat dark field.
- `p95` measures retained upper-tone structure and available display headroom.
- `p95 - p05` measures usable spread; it prevents a uniformly dark fog-like field from being
  treated as a normal exposure defect.
- Shadow and highlight clipping fractions are guardrails. RAW decoder headroom is honored when
  available, but display pixels are never assumed to contain unrecoverable RAW detail.

High-key, low-key, and night likelihoods pull the neutral target toward the measured median. That
brake is disabled when the robust distribution contradicts the scene key: a
low median plus retained upper structure and meaningful spread indicates material underexposure.
Sunset, snow, fog, and backlit evidence do not create a blanket global lift; their existing color,
dehaze, and regional policies remain independent. Backlit subjects can therefore receive a local
subject correction without lifting a bright background indiscriminately. Backlight inference uses
the person/face matte when available instead of a broad saliency box, because the latter can
include the bright sky around a subject. A likelihood of `0.30` or higher also prevents Auto from
lowering global exposure to place a median dominated by that background; shadow lift then carries
the subject correction. The coordinator composes the background as the foreground complement, and
fractional resampled-mask histograms are accepted within a scale-aware floating-point tolerance.

## Bounds and guardrails

Ordinary corrections remain within `±1.25 EV`. Structurally underexposed frames may use up to
`+1.75 EV` (plus a small RAW-recovery allowance) when the evidence earns it. The coordinator's
candidate score uses the same neutral target and selects only a rendered candidate that improves
global/important-region placement enough to clear the improvement threshold.

Candidates are rejected for new highlight clipping, saturation above the absolute 0.97 guardrail,
unsupported neutral color error, mask-edge artifacts, or unmeasurable pixels. For reliably
measured muted color, the frozen score target closes 75% of the gap to colorfulness 0.46 (capped
at 0.46); otherwise it equals the measured baseline. Color confidence must be at least 0.60,
colorfulness below 0.35, and saturation p95 no higher than 0.85. Mixed lighting, monochrome
(likelihood above 0.50), and sunset warmth (above 0.60) disable the boost. Night likelihood
(above 0.60) disables it unless median luma is below 0.20 and measured chroma is clear (median
saturation at least 0.50 and colorfulness at least 0.10). The policy raises vibrance toward that
target with a bounded 0–24 slider response: 60 points per unit of colorfulness shortfall, with
an 18-point minimum when measured colorfulness is below 0.28. For dark chromatic evidence,
vibrance also gets a saturation increase up to 10 points, limited by measured p95 headroom.
Candidate
selection weights the rendered colorfulness shortfall at 1.75 alongside tone and saturation
guardrails, so a safe color improvement can win alongside a tonal improvement. Relative contrast/noise
costs are measured against the unchanged render. This protects shadow readability without
accepting crushed blacks, clipped whites, or a washed-out result. Existing manual controls,
curves, Looks, LUTs, and user-owned local layers remain unchanged; Auto provenance version 5
invalidates older run fingerprints so the calibrated policy is evaluated once.

## Quality rubric

`AutoQualityRegressionTests` defines a representative routing matrix and checks rendered before/
after results for supported Light, Color, and white-balance corrections. Expected visible changes:

| Photo evidence | Expected Auto result |
| --- | --- |
| Underexposed with recoverable spread | Lift midtones toward the neutral target; open residual shadows when supported, without new highlight clipping. |
| Muted color with reliable color evidence | Raise vibrance enough to measurably improve colorfulness; preserve the hue palette and clipping limits. |
| Both tonal and muted-color evidence | Improve rendered luminance placement and colorfulness in the same proposal. |
| Measured color cast with neutral evidence | Reduce the rendered cast; skip correction when estimators disagree or scene intent vetoes it. |
| Balanced | Keep Light and Color close to the input. |
| High-key / low-key | Preserve the scene's tonal key unless robust distribution evidence contradicts it. |
| Sunset / night | Preserve warm or dark intent; do not force Color or white balance. |
| Monochrome | Preserve grayscale character; do not add saturation. |
| Backlit | Lift a supported subject region without indiscriminately lifting the bright background. |

The underexposed test measures the actual Auto proposal's rendered luminance change and clipping.
The muted-color fixture measures before/after renderer colorfulness and pixel difference. Balanced
and intentional-scene fixtures assert restraint. The policy suite also exercises a RAW source-kind
equivalent; a licensed local ARW/DNG is picked up automatically by the existing optional RAW test
lane when `KROMORA_RAW_FIXTURE_DIR` is configured.

Run the focused report with:

```sh
scripts/auto-quality-report.sh
```

With `KROMORA_AUTO_QUALITY_ARTIFACT_DIR` set, the report writes the unchanged/proposed/diff
renders and scalar report beside each fixture, including `auto-quality-underexposed`.
