# RAW pipeline inspection

Inspection of repository `b3be8d83`, 4 November 2026. This is a code and installed-SDK inspection, not a controlled image-quality comparison. No production code was changed. “Decoder stage” below means inside `CIRAWFilter` before its `outputImage` is consumed; Apple does not document the internal order of most operations or guarantee they run on the sensor mosaic.

## Executive summary

1. **Hiding Develop did not move its rendering code.** Commit `f6fa89b6` (27 September 2026) set `showsDevelopTab = false` to fit the tab bar. The view, document settings, capability probing, and decoder application remain. Existing explicit RAW settings continue to be applied. This was a UI availability change, not a decoder-to-RGB migration.
2. **User access to many RAW controls was lost**, not the underlying capability. Global RAW white balance remains accessible in Color and still routes to the decoder. The current Light exposure is a separate RGB operation; it did not replace the stored RAW exposure setting at the time of hiding.
3. **Yes, the unified Light exposure and tonal controls run on developed RGB**, after the Look. RAW exposure and decoder tone controls still exist in the model but their Develop UI is hidden. Local white balance and all local adjustments also run on RGB.
4. **Some information has necessarily been transformed before those controls:** demosaicing, decoder tone curve (default boost 1), default gamut mapping, and potentially other camera-specific processing. The SDK says EDR defaults to 0, so extended output is not requested by a neutral edit. The source does not establish exactly what is clipped or recoverable for any given image. Extended-linear floating-point evaluation is not proof of untouched scene-linear sensor data.
5. **Selection is implicit.** The installed `CIRAWFilter.h` explicitly says a freshly initialized filter defaults to the newest decoder available for the image type; Kromora never sets `decoderVersion`. Thus it uses Apple's declared default, not a verified particular version for every file or OS. Version 9/9DNG is declared macOS 27+, and cannot be assumed on the macOS 26 deployment floor. Probe the actual image and runtime.
6. **Sony lens correction is unknown.** Kromora leaves the per-image default alone unless a saved override exists; the SDK says support and default vary by image. The specified `DSC01104.ARW` was not found in the workspace when this was written; it has since been measured (KRMA-1181 below), and Apple's correction does change its geometry.
7. **A hybrid can help, but is already partly present.** Decoder white balance and persistent RAW settings coexist with the shared RGB graph. Exposure/highlight and detail prototypes are plausible, not established improvements. Any remapping needs a processing version to preserve old edits and a latency budget.
8. **Three best experiments:** (1) inspect the exact Sony file and compare decoder lens correction on/off, (2) compare default base rendering and controlled boost/EDR/highlight/exposure variants using float measurements, (3) compare decoder and RGB noise/sharpening on high-ISO files and measure interactive cost. These isolate geometry, tonal headroom, and detail respectively.

## History and architecture

| Date / commit | Actual change |
| --- | --- |
| 5 August 2026 `9ceceb16`, `68df8149` | Added the optional `RAWDevelopSettings` document model and pipeline that configures a `CIRAWFilter` before reading output. |
| 6 August `77adcedb` | Introduced the RAW Develop inspector; `a97acd3f` provided bindings and `2de43215` seeded displayed values from the decoder. |
| 31 August `1da2a517` | Unified white balance: RAW uses decoder temperature/tint, standard images use RGB `CITemperatureAndTint`; RAW post-render WB nodes were excluded. This was a real routing change predating hiding the tab. |
| 27 September `f6fa89b6` | Withheld the Develop tab with `showsDevelopTab = false`; its diff leaves the model and render path intact. The stated reason was tab-bar width. No removal commit for the view was found on the inspected history. |

Originally: source → configured `CIRAWFilter` → RGB adjustments → output. Today: source → configured `CIRAWFilter` → Look → global RGB adjustments → local RGB layers → output. The Look order is a later real change (`9f3ae63d`), not caused by hiding Develop. Historically the panel exposed exposure, baseline exposure, shadow bias, boost and shadow boost, temperature/tint, sharpness, local contrast, detail, moiré, local tone map, luminance/color noise reduction, lens correction, gamut mapping, EDR, and highlight recovery. `DevelopControl` and `DevelopInspectorView` still enumerate them. These are Apple filter properties, not custom pre-demosaic algorithms. Settings are optional Codable fields in `EditDocument.rawDevelop`; nil means leave the file-specific decoder default, and `RAWDevelopSettings.apply(to:)` writes supported explicit settings. The internal mosaic/demosaic ordering is undocumented; configuring a RAW filter does not prove a particular property operates before demosaicing.

The current `InfoInspectorView` still contains the view, but `AppViewModel.InspectorTab.availableTabs` explicitly excludes it. The visible Color white-balance binding in `AppViewModel+Color.swift` routes RAW to `rawDevelop.neutralTemperature`/`neutralTint`, standard sources to an RGB adjustment node. Old RAW RGB WB nodes are suppressed during rendering; assess old-edit compatibility separately before altering this policy. Exposure in `LightAdjustments` is independent of `rawDevelop.exposure`; existing explicit settings can stack.

## Current execution and representation

```text
Package import retains original + metadata + non-destructive edit revision
  → ImageSource (URL/data, RAW classification; previews may initially use embedded thumbnail)
  → RenderEngine / RenderPipeline.developedSource
      RAW: CIRAWFilter(imageURL: or imageData:) → apply rawDevelop,
           orientation and preview scaleFactor → outputImage
      standard: oriented CIImage / ImageIO reduced preview
  → retouch → rotation / perspective geometry
  → Look (cube in its declared authoring space)
  → Light (exposure, tone curves, whites/blacks)
  → Color (vibrance, saturation, mixer, grading)
  → spatial effects / detail → legacy adjustment nodes
  → ordered local masks: adjusted RGB variant blended with layer input
  → crop → vignette / grain → preview or full export, optional output sharpening
```

`PackageSourceImportCoordinator`, `PortablePackageImport`, `ImageSource`, `ImageDecoder`, `RenderPipeline`, `RenderEngine`, `LocalMaskRenderer`, `RenderStageFacade`, and `ExportRasterizer` are the principal boundaries. The initial embedded preview/thumbnail is not evidence of final rendering. `ImageDecoder.developedImage` handles RAW orientation; the filter's `nativeSize` remains sensor-oriented. RAW preview requests set `scaleFactor` before output; full export requests use full scale. The interactive engine can reuse a mutable filter session and restores prior settings; developed-source keys include source, RAW settings and effective scale, while a separate processing-prefix cache can retain the Look and global result. See `RenderEngine.developedSourceForBuild`, `InteractiveRAWFilterSession`, `RenderCacheKey`, and `RenderPipeline.buildGradedImage`.

Apple owns RAW format decoding, demosaicing, camera interpretation, and undocumented internal ordering. Kromora does not select a camera profile or implement a separate camera matrix/demosaicer; the header does not identify which embedded or built-in profile Apple chooses. Default as-shot neutral, baseline exposure, recovery, tone, correction, sharpening and noise behavior come from the filter unless an explicit setting overrides them. The header describes boost as a global tone curve, so default developed output is not demonstrably scene-linear even though subsequent evaluation is linear-light.

`RenderEngineResources` constructs its main `CIContext` with extended-linear Display P3 working space (`WorkingSpace.current`); Core Image performs color management into that space when evaluating the graph. The graph is lazy: its internal buffers and the RAW filter's exact pixel format, profile, transfer function, and precision are not specified by Kromora or the SDK header. Do not infer a uniform 16- or 32-bit intermediate. Some **preview-only** materialized processing prefixes explicitly use RGBA half-float, tagged with encoded Display P3 (`space.cgColorSpace`), and are converted back by Core Image when reused. Half-float preserves extended numeric range in principle; actual transform/filter clipping still needs measurement. The project comments identify `CIToneCurve` as gamut-clamping; curves and LUT domain can change or discard values. Full export stays on the fused graph rather than that preview prefix.

Completed interactive preview textures are RGBA8 unorm; settled textures are RGBA16Float, both rendered with the requested output color space, and `PreviewSurface` presents to BGRA8. These are presentation boundaries, not the source of subsequent edits. Histogram analysis uses bounded RGBA8; the gamut sampler uses RGBAf in extended-linear P3. Export uses the same document/source graph at full scale, then `RenderEngine`/`ExportRasterizer` render RGBA8 or RGBA16 integer in the chosen encoded sRGB or Display P3 space, followed by format encoding and metadata. Output gamut and integer representation limit final delivery. Preview scale, materialization, and presentation differ from export, so pixel identity is not assumed.

## Apple capabilities and defaults

Source of API claims: installed `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreImage.framework/Headers/CIRAWFilter.h` and `CIRAWFilter_Deprecated.h`. The installed header includes macOS 27 declarations; `isHighlightRecoverySupported` and `isHighlightRecoveryEnabled` are declared available from macOS 26. All other listed current properties are on the macOS 26 baseline. Header comments contain apparent copy errors for lens correction and local tone map: they do not establish detailed lens coverage or full internal algorithm. Camera dependence below means documented per-image support/default, not a claim about a particular camera. For all rows, internal placement relative to demosaicing is **undocumented**.

| Capability | API semantics and neutral Kromora behavior | Possible relevance |
| --- | --- | --- |
| Exposure / baseline | `exposure` defaults 0; `baselineExposure` varies per image. Nil leaves both; explicit saved values apply. | Decoder exposure could preserve or reconstruct information differently than RGB EV; measure. |
| WB | `neutralTemperature` 2000–50000 K and `neutralTint` −150–150; decoder seeds as-shot values. Visible RAW WB writes them. | Sensor-aware behavior may differ from RGB chromatic adaptation; no claim about internal algorithm. |
| Shadow bias / boost / boost shadows | Bias image-dependent; boost default 1, 0 specifies linear global response; shadow boost default 1, ineffective at boost 0. Nil leaves defaults. | Default tone is an important base-render difference; changing it also changes rendering and slider response. |
| Recovery / EDR | Recovery default true, support per image; saved value gated on support. EDR amount 0–2, default 0; nil leaves it. | Recovery is already requested by default where supported; EDR and RAW exposure can be tested for usable headroom. |
| Local contrast, detail, sharpness, moiré, local tone | Separate support flags and per-image defaults; saved settings are gated. RAW contrast means **edge local contrast**, not the global Light contrast. | Possible capture-specific detail/tone benefit; proprietary and not interchangeable with RGB sliders. |
| Luminance / chroma NR | Separate support flags and per-image defaults, 0–1. Saved settings gated. | Potential advantage over the shared RGB denoiser, but compare texture, color, artifacts and cost. |
| Gamut mapping | Enabled by default per header; nil leaves it, explicit setting applies. | Can change out-of-gamut colors before editing; algorithm and reversibility unspecified. |
| Lens correction | Support flag and image-dependent default; nil leaves it, saved override gated. Header's lens comment erroneously repeats gamut wording. | Geometry may change; exact geometric, CA, and illumination scope is not documented by that comment. |
| Despeckle / linear-space filter | Header exposes `despeckleAmount` and `linearSpaceFilter`; Kromora does not configure them. | Possible targeted experiments, not evidence of a defect; defaults and internal placement require inspection. |
| Decoder version | `supportedDecoderVersions` sorted oldest to newest; new filter defaults to newest available for image type; unsupported requested version produces nil output. | Kromora does not pin it. OS upgrades may alter existing edit appearance. Version 9 and 9DNG require macOS 27; availability does not prove image support or installed resources. |

The header also provides `neutralChromaticity` and `neutralLocation`, and macOS 27 APIs for per-version camera lists and on-demand resources. Kromora uses typed `CIRAWFilter` constructors, not legacy `CIFilter.rawFilter` options in its render path. `ImageSource` identity strings such as `imageio-arw-v1` are application fingerprints, **not** Apple decoder selection. Saved settings and decoder-dependent defaults can therefore produce different output across OS upgrades.

## Adjustment comparison

All RGB rows run after RAW output; no row implies equivalence with Lightroom. Performance estimates are qualitative and require measurement. RAW properties are global; local layers cannot directly apply them to only part of the mosaic.

| Control | Current implementation / stage | RAW alternative and mathematical or information distinction | Benefit, cost, recommendation |
| --- | --- | --- | --- |
| Exposure | `applyLight`: `CIExposureAdjust` EV on developed RGB, after Look | `exposure` in filter; same EV label does not establish same curve or highlight behavior. Decoder tone/gamut processing precedes RGB EV. | Investigate with clipped-channel scenes; changes invalidate developed source and can be slower. Do not stack both unintentionally. |
| Temperature / tint | Global RAW: decoder neutral; standard and local: `CITemperatureAndTint` from D65 with axis conversion | Already RAW-aware globally. RGB adaptation acts on developed pixels, not original channel measurements. | Keep; test extreme mixed light and old documents. RAW slider costs redevelop. |
| Contrast | Five-point monotonic `CIToneCurve` with fixed endpoints | Decoder `contrastAmount` is edge local contrast, not equivalent; boost changes global tone. | Keep shared intent; investigate base curve first. RGB curve can constrain range; low redevelop cost. |
| Highlights / shadows | Same five-point curve, weighted upper/lower interior points | Recovery boolean, `boostShadowAmount`, `localToneMapAmount` are not equivalent to signed sliders. RGB cannot reconstruct unavailable channel data. | High-value headroom/recovery experiment; decoder redevelop cost. |
| Whites / blacks | Separate endpoint tone-curve stages | No direct equivalent; baseline exposure and shadow bias have different semantics. | Keep; test clipping and shoulder, low redevelop cost. |
| Saturation / vibrance | `CIColorControls` saturation and `CIVibrance` | No matching RAW property; gamut mapping affects colors differently. | Keep; compare color transforms and gamut before inventing RAW routing. |
| Texture | Small-radius `CISharpenLuminance` or blur blended on RGB | `detailAmount` enhances edges, not same signed spatial control. | Keep; compare halos/details; RAW version costs redevelop. |
| Clarity | Larger-radius sharpen/blur with midtone mask | RAW local contrast/local tone map have undocumented shapes and cannot match mask. | Keep; investigate only after controlled comparison. |
| Sharpening | RGB `CIUnsharpMask`, optional edge mask, after decoder default sharpening | RAW sharpness/detail amounts with camera-specific defaults; risk of double sharpening. | Compare at 100% and matched noise; decoder changes cost more. |
| Luminance / color NR | Two separately controlled passes of the same `CINoiseReduction`, with different parameters/blends; the color path is not a dedicated chroma-only implementation | Distinct RAW luminance/chroma NR support and defaults; algorithms unknown. | High-value experiment on color speckle and fine texture; RAW cost and stacking must be measured. |

See `RenderPipeline.applyLight`, `applyColor`, `applySpatialEffects`, `applyDetailControls`, and `applyLocalAdjustments`; kernels in `Resources/KromoraCIKernels.ci.metal` include mixer, grading, masks and tone-curve work. RGB on a wide-gamut extended-linear graph is a sound basis for creative operations and can preserve headroom; it cannot recover clipped or discarded sensor-channel information merely by using float storage. Neither a color transform nor a particular Core Image filter is assumed reversible.

## Sony lens investigation

At the initial KRMA-1177 inspection, `DSC01104.ARW` was not found in the workspace and the ILCE-7CR reference had not been measured. The later full-resolution registration in KRMA-1181 measured it and the other supported local Sony ARWs; those results and their limits are recorded below. No calibration target or dedicated straight-edge scene was available, so straight-line deformation was not separately quantified. Kromora passes the original URL/data to Apple; `PhotoAsset` extracts lens metadata for display/filtering, not an independent lens-profile engine. No custom automatic geometric lens, chromatic-aberration, or peripheral-illumination correction was found in the render path. User crop/perspective and creative vignette are different operations. Apple may use embedded metadata, its own database, both, or neither; the public header does not say. No independently exposed CA or peripheral-illumination switch is established by this API. Do not infer which corrections the single lens switch includes.

The initial investigation proposed recording `properties`, `supportedDecoderVersions`, `decoderVersion`, `nativeSize`, and the correction support/default before and after applying saved settings, then comparing full-resolution renders with only `isLensCorrectionEnabled` toggled. KRMA-1181 performed the render comparison with dense natural-scene patch registration and recorded its confidence limits below. Metadata can be inspected separately with ImageIO or an independent reader; a no-op difference alone would not prove metadata was ignored. The Adobe profile comparison was accepted as out of scope by the owner; no equivalence with Adobe is claimed.

## Findings, hypotheses and risks

**Confirmed:** the hidden Develop gate removes UI access; saved RAW edits still execute. RAW white balance is already routed behind the common Color control. Light exposure and tone are RGB and follow the Look. Decoder defaults include a global tone curve, gamut mapping, and EDR 0; recovery defaults true but is support-dependent. The unified color-noise slider uses the same RGB denoiser as luminance noise. No explicit decoder version is saved or selected.

**Ranked hypotheses, not measured conclusions:**

1. **Base tone and camera color rendering** — potentially high impact, strong code evidence of different underlying decoder/default curve but no evidence of Lightroom's exact choices. Compare matched neutral renders before sliders.
2. **Highlight behavior and processing order** — potentially high, strong evidence of decoder tone before RGB Light and Look before exposure; unknown recoverable data and Lightroom behavior. Examine channels and highlights.
3. **Lens geometry** — potentially high for architectural/wide-angle images; evidence limited to differing visual appearance reported in the brief, with no reference-file probe.
4. **Demosaic, capture sharpening and NR** — potentially high at 100%/high ISO, code confirms Apple defaults plus optional post sharpening; no side-by-side evidence of which is better.
5. **Global/local contrast, texture, color/gamut and clipping** — moderate to high scene-dependent impact; code establishes different algorithms and possible boundaries, not quality ranking. Float working space alone does not guarantee headroom through every filter.
6. **White balance routing** — likely less explanatory as a general regression because RAW global WB already uses the decoder; extreme WB and local RGB adaptation still merit a targeted comparison.

A new routing rule changes existing recipes: old `light.exposure`, raw exposure, WB nodes, Look ordering, masks, caches, snapshots, undo and export must retain their meaning. Decoder updates can change neutral defaults even without a document migration. Version an opt-in processing policy and preserve old behavior on reopen; do not silently reinterpret saved values. Decoder versions may be removed or unavailable for a future file/runtime, so collect support and define a deliberate compatibility policy rather than assuming a pin always works.

## Recommended isolated experiments

All prototypes should be temporary, feature-gated, and preserve the unified UI, default path, original files, and existing document interpretation. Use a representative set of camera models, contrast scenes, saturated highlights, color charts, high-ISO textures and the Sony reference. Compare full-resolution, same output profile, white point, exposure and composition. Use blind paired viewing at fit and 100%, channel clipping/headroom counts and localized crops; record OS, decoder version and settings. Lightroom is a perceptual reference, not a ground-truth algorithm.

1. **Lens profile diagnostic.** Paths: `RenderPipeline.rawFilter`, `RAWDevelopSettings.apply`, `RenderEngine+RAWCapabilities`; add a temporary external diagnostic using calls above. Toggle only supported lens correction on the exact Sony file. Keep all other RAW settings, crop and output fixed. Expect possible edge displacement/straight-line changes; compare edge registration, CA and illumination independently, plus matched preview/export. Measure full/preview render time and extents. Success: a repeatable geometry change attributable to the toggle and matching or explaining the reference; reject the missing-correction hypothesis if unsupported or no meaningful effect, without inferring Lightroom's profile.
2. **RAW headroom and exposure.** Paths: `RAWDevelopSettings`, `RenderPipeline.developedSource` and `applyLight`, `RenderEngine` caches. Render a factorial, one variable at a time: default versus boost/EDR/recovery, and matched RAW exposure versus RGB EV. Preserve WB, lens settings, Look state (first off, then fixed), framing and output transform. Inspect pre-Light extended-linear RGBAf values, per-channel highlights, chroma, recovered detail and final matched brightness; test non-clipped controls too. Measure interactive p50/p95 to first and settled frame, full export and cache misses. Success: repeatable visible detail/color improvement without unacceptable artifacts or latency; reject automatic routing if equivalent or destructive. Boost 0 and EDR change the base rendering, so do not attribute their effects solely to exposure.
3. **Capture detail.** Paths: `RAWDevelopSettings.apply`, `RenderPipeline.applyDetailControls`, `RenderEngine` source/prefix cache. Compare decoder NR/sharpness variants with matched RGB slider variants; explicitly account for existing decoder defaults and prevent double application. Keep geometry, WB, tone, scale, export and viewing fixed. Inspect chroma speckle, luminance noise, fine texture, halos and color patches, at multiple ISOs; measure local noise variance and edge/texture retention alongside blind crops. Benchmark slider latency, memory and export. Success: meaningful improvement across images at acceptable interaction cost; reject substitution where it smears, changes intent or only shifts sharpness/noise tradeoff.

## Recommended sequence

1. Obtain and probe the exact Sony original and baseline the current decoder/defaults; do not change correction based on an unverified visual difference.
2. Establish controlled base-render and highlight measurements, then run the exposure/headroom prototype. Separately evaluate NR/sharpening on high-ISO fixtures.
3. Only if results justify it, design a versioned, format-aware mapping behind the existing controls. Decide whether RAW exposure replaces RGB exposure for **new-version** global edits or is a calibrated split; never blindly apply both. Keep masks in the shared RGB graph, preserve current saved settings and neutral behavior, and test preview/export parity and latency. Favor caching, scaled interactive development, coalescing and settled refinement using existing engine mechanisms, but expect RAW changes to invalidate developed-source and downstream prefixes.
4. Define decoder-version and camera-dependent defaults policy, migration and regression fixtures before shipping. Validate slider intent across RAW and rendered formats perceptually rather than promising identical numerical output. No separate Develop panel or broad rewrite is required by these findings.

## Follow-up: global exposure routed to the decoder (KRMA-1174)

The inspection's “Light exposure runs on developed RGB after the Look” finding no longer holds for
RAW sources: the global Exposure slider is applied through `CIRAWFilter.exposure`, before the Look,
with a calibrated slider-to-decoder ratio. See
[`ENGINEERING_GUIDE.md`](ENGINEERING_GUIDE.md#raw-exposure-routing). The statements above describe
repository `b3be8d83`.

## Follow-up: lens correction verified, no change (KRMA-1177)

`RAWLensCorrectionTests` (optional lane) probes every RAW in `realworldtest/` through the render
path. `DSC01104.ARW` is still not in the workspace, so the ILCE-7CR reference remains unmeasured.
Measured on the four local Sony ARWs, all on decoder version 8 with the neutral document:

| File | Frame | `isLensCorrectionSupported` | Initial → effective `isLensCorrectionEnabled` |
| --- | --- | --- | --- |
| `DSC00324.ARW` | 6000×4000 | true | true → true |
| `DSC01019.ARW` | 9504×6336 | true | true → true |
| `DSC01153.ARW` | 9504×6336 | true | true → true |
| `DSC04513.ARW` | 7952×5304 | false | false → false |

- **Apple's per-image default is already correct.** Where the decoder supports correction it is on
  by default, and a neutral document leaves it on (`nil` renders identically to writing the default
  explicitly). Where it is unsupported, the control is absent and a saved override is inert. No
  default, capability gate or profile database was added.
- **What the switch changes.** Toggling it on the three supported files leaves the full and preview
  extents unchanged and shifts pixels (mean |Δ| of roughly 0.005–0.03 on a 0–1 scale), raises the
  corner-to-centre luminance ratio (for example 0.929 → 0.937, 1.166 → 1.192) and moves the outer-ring
  colour balance. Those preview-scale statistics alone do not show geometry; the full-resolution
  registration below (KRMA-1181) supersedes the earlier "undetermined" reading.
- **Preview/export parity.** Both go through `RAWDevelopSettings.apply(to:)` and
  `CIRAWFilter.scaleFactor`; the scale is derived from the sensor `nativeSize`. For default, on and
  off, the preview extent equals the full extent times the scale factor (within a pixel), and the
  interactive session restores the decoder default when an override is cleared.
- **Not compared in KRMA-1177.** Registered straight-line distortion and Lightroom's profile choice;
  see KRMA-1181 below.

## Follow-up: full-resolution registration and Adobe profiles (KRMA-1181)

**Method.** `RAWLensCorrectionTests/testFullResolutionRegistrationOfEnabledAgainstDisabled`
(optional lane, about 6.5 minutes in a debug build) renders each supported ARW at full resolution
with only `isLensCorrectionEnabled` toggled (decoder v8, neutral document otherwise) and registers
the two renders on an 11×7 grid of patches spanning 96 % of each half-extent. Patches are matched by
normalised cross-correlation on a 4× downsample with parabolic sub-pixel refinement (search ±96 px at
full resolution); matches with NCC ≤ 0.9 or pinned at the search limit are discarded. Registering the
same scene content patch by patch measures the displacement directly, so no calibration target or line
fit is needed; a full-resolution refinement was tried and dropped because a distortion correction's
local magnification (a few percent) deforms the match window. R and B are also registered against G
inside each render to separate lateral chromatic aberration from geometry. No dedicated
straight-edge or chart image was available; the four local files are ordinary scenes.

| File | Lens, focal length | Patches registered | Median outward displacement of the corrected render, by radius band (fraction of half-diagonal) |
| --- | --- | --- | --- |
| `DSC00324.ARW` (ILCE-7M2) | Sony E 150-500mm, 500 mm | 74/77 | 0.2–0.4: −2 px; 0.4–0.6: +11 px (+0.5 %); 0.6–0.8: +19 px (+0.7 %); 0.8–1.0: 0 px |
| `DSC01019.ARW` (ILCE-7CR) | FE 24-105mm F4, 105 mm | 38/77 | 0.6–0.8: −43 px (−1.0 %); 0.8–1.0: −44 px (−0.9 %); inner bands unreliable |
| `DSC01153.ARW` (ILCE-7CR) | FE 24-105mm F4, 24 mm | 43/77 | 0.2–0.4: +7 px; 0.4–0.6: −3 px; 0.6–0.8: −9 px (n=5); 0.8–1.0: none registered |
| `DSC01104.ARW` (ILCE-7CR) | FE 24-105mm F4, 49 mm | 39/77 | 0.2–0.4: −4 px (−0.3 %); 0.4–0.6: +29 px (+0.8 %); 0.6–0.8: +53 px (+1.3 %); 0.8–1.0: +40 px (+0.8 %) |
| `DSC04513.ARW` (ILCE-7RM3A) | FE 24mm F1.4, 24 mm | not supported | not applicable |

(Positive = the corrected render pushes scene content away from the optical centre.)

- **Geometry is part of the switch.** Corrected and uncorrected renders share an identical extent but
  the same scene points sit tens of full-resolution pixels apart (up to roughly 1 % of the radius), so
  unchanged extents do not rule out geometric remapping, and the earlier "geometric component not
  established" reading is withdrawn. `DSC00324` gives a clean signature: about zero near the centre,
  growing smoothly with radius, tangential component near zero (a radial distortion correction). The
  other two files do not give a clean radial profile: texture-poor or repetitive regions, patches
  pinned at the search limit, and a few non-zero centre shifts that a distortion correction cannot
  produce show that part of the per-band numbers are registration noise. Their per-patch traces (printed by the test) show
  large, smooth, high-NCC displacement fields, so the conclusion that geometry changes holds, but the
  profile magnitude per lens is not established here and should not be quoted.
- **`DSC01104.ARW` (the ILCE-7CR reference) is now measured** (run alone, 130 s in a debug build,
  full 9504×6336 extent identical enabled and disabled). It gives the cleanest per-patch field of the
  four: the centre patch is stationary (+0.15, +0.85 px, NCC 0.94), the shift grows smoothly with
  radius in the same direction on every side of the frame (the corrected render pushes content
  outward), and the high-NCC patches along the horizontal and vertical axes are purely radial. That
  is a radial distortion-correction signature. Two caveats: many mid-radius patches (about 0.5–0.8 of
  the half-extent) are pinned at the ±96 px search limit and discarded, so the true displacement
  there exceeds the banded medians above and the peak magnitude is under-measured, and the
  −50 px tangential median in the 0.4–0.6 band comes from n=6 surviving patches and is registration
  noise, not a real tangential component. The sign (outward at 49 mm) differs from `DSC01019` at
  105 mm (inward), so the per-focal-length profile is not constant across this lens. Lateral CA is
  again not distinguishable: R−G and B−G shifts stay below 0.8 px and do not differ consistently
  between enabled and disabled.
- **Chromatic aberration is not separately evidenced.** Radial R−G and B−G shifts inside each render
  are mostly below about 0.5 px (one 24 mm band reaches −0.74 px, n=5), with no consistent difference
  between enabled and disabled, so these scenes show no reliable lateral-CA change.
- **No Kromora policy defect.** The default is Apple's per-image setting and it is enabled wherever the
  decoder supports it, so geometric correction is already applied to the renders Kromora produces. A
  neutral document therefore matches what the decoder does on its own; nothing here is attributable to
  Kromora policy, and no product change was made.
- **Adobe: what could be recorded locally.** Camera Raw defaults on this machine
  (`~/Library/Application Support/Adobe/CameraRaw/Defaults`) are stock (`RawDefaults = Adobe`, no
  custom lens-profile default; `LensProfileDefaults` is empty). Adobe's installed profile library
  (`/Library/Application Support/Adobe/CameraRaw/LensProfiles/1.0/Sony`) contains
  `SONY (Sony FE 24-105mm F4 G OSS) - RAW.lcp` (distortion parameters at 24, 35, 50, 70 and 105 mm) and
  `SONY (Sony FE 24mm F1.4 GM) - RAW.lcp`, but no Sony E 150-500mm profile. Adobe's profiles are
  therefore available for `DSC01019`, `DSC01153` and `DSC04513`, not `DSC00324`. The parameter
  normalisation was not verified, so no numeric comparison with Apple's displacement is claimed.
- **Adobe: not done.** Lightroom or Camera Raw was not run on these files: Photoshop 2026 was still at
  first-run setup (per the KRMA-1177 verification), Lightroom is cloud-based, and no scripted local workflow was available. Whether
  Lightroom applies its profile, Sony's embedded distortion data, both, or neither for these ARWs, and
  whether its result matches Apple's, remains unmeasured, including for `DSC01104.ARW` (now
  available; Adobe has a local LCP for its 24-105 F4 G lens). **Owner decision (2026-11-05): the
  Adobe comparison is accepted as out of scope.** It is not
  measured, and nothing above claims agreement or disagreement with Adobe's profile choice, metadata
  interpretation or numeric correction. The Kromora conclusion does not depend on it: Apple's decoder
  default is applied as-is and no policy defect was found.

## Follow-up: highlight headroom and tone controls evaluated, RGB retained (KRMA-1176)

`RAWHighlightHeadroomBenchmark` (optional lane) develops the same 800-pixel frame of every RAW in
`realworldtest/` under each decoder control and the RGB Light controls, and reads back float
extended-linear values. The fixed region is the brightest 0.5% of pixels (by max channel) of the
neutral decode; the same indices are compared for every variant. "Clip" is the fraction of region
channels at or above 1 and is an output reference, not proof of sensor clipping. `relSpread` is the
region's 5–95% luminance spread over its median, so a pure rescale scores the same as neutral. The
"midtone-matched" column applies one global gain that returns the whole-frame median to the neutral
median, separating tone appearance from channel content. macOS 27.2, decoder version 8, Apple
Silicon, debug build.

**Corpus.** Four Sony ARWs plus three non-Sony DNGs added from the author's own library: an iPhone 14
Pro ProRAW (`IMG_0206.DNG`), an iPhone 17 Pro ProRAW (`IMG_0695.DNG`) and a Samsung SM-N960U1 DNG
(`20181011_181213.dng`). There is **no bracketed or otherwise clipped-channel ground truth** for any of
them. Among the Sony files only `DSC01153` has a meaningfully clipped region (0.8% of region channels
at or above 1), `DSC04513` has six clipped region pixels, and `DSC00324`/`DSC01019` have none. The
Sony tables below are the primary evidence; the non-Sony results are in their own subsection.
Conclusions about recovery are limited to what these seven files show; bracketed references are still
needed before claiming anything stronger.

**Support and defaults (all four ARWs, identical).** Boost 1, boost shadow 0.9, EDR 0, gamut mapping
on, highlight recovery supported and **on**, local tone map **not supported** (the gate is closed, so
the control writes nothing), baseline exposure 0.3–0.4.

| Control (DSC01153 region) | Clip | p99 | relSpread | Reading |
| --- | ---: | ---: | ---: | --- |
| Neutral | 0.008 | 1.008 | 0.330 | |
| Highlight recovery off / on | 0.008 | 1.008 | 0.329 / 0.330 | **No measurable effect** on any of the four files, including the one with clipped pixels |
| Local tone map 0 / 1 | — | — | — | Unsupported on these decoders; identical output |
| Boost shadow 0.5 / 1.5 | 0.008 | 1.008 | 0.330 | Region identical; it moves only shadows (midtone-matched clip differs only because the median moves) |
| EDR 1 / 2 | 0.235 / 0.582 | 1.37 / 1.67 | 0.475 / 0.608 | Values above 1 appear where neutral had a shoulder; midtones unchanged |
| Boost 0.5 / 0 | 0.008 / 0.007 | 1.02 / 1.03 | 0.532 / 0.852 | Changes the whole base tone (median 0.084 → 0.068 / 0.053); highlights are expanded relative to it |
| RGB Highlights −50 / −100 | 0.005 | 1.000 | 0.437 / 0.564 | Region relSpread grows with the throw; midtones barely move (median 0.083 / 0.081) |
| RGB Whites −100 | 0.000 | 0.776 | 0.231 | Lowers the endpoint, compresses the region |
| RGB Shadows +100 / Blacks −100 | 0.005 | 1.000 | 0.329 / 0.326 | Leave the highlight region unchanged |

Reading the table honestly:

- **Decoder processing versus scene-linear output.** None of the decoder controls returns an
  unprocessed scene-linear image. Neutral already contains the boost-1 tone curve, gamut mapping and
  the baseline exposure; EDR and boost change that curve rather than reveal sensor data.
- **Tone appearance versus recovered detail.** EDR 1/2 and boost 0/0.5 increase region relSpread
  because they reshape the highlight shoulder, and EDR pushes values above 1 (p99 1.37 / 1.67, from
  1.008). That is more *extended-range* separation, not demonstrably more recovered channel detail:
  the clipped fraction rises, nothing is brought back below 1 without a further gain that also dims
  the midtones, and no bracket exists to say the extra spread is scene detail. Highlight recovery,
  the one control whose name promises recovery, did nothing measurable on any file.
- **RGB already serves the intent.** RGB Highlights −100 raises the same region's relSpread to 0.564
  (from 0.330) with the median moved by 4%, and Whites −100 pulls the endpoint to 0.78. Their throw is
  predictable, monotonic and local to the highlight region, and its interactive cost is 3–4 ms per tick
  (app-level latency, see the KRMA-1182 follow-up below; the 4–7 ms first quoted here was a single-pass
  characterization timing); no decoder control moves
  highlights without also moving the base tone (boost, EDR+gain) or doing nothing (recovery, local
  tone map, shadow boost).
- **Cost.** Every decoder variant re-outputs the RAW (about 200–400 ms per develop plus float
  readback in this debug proxy). That figure and the "4–7 ms" for an RGB Light control are
  **single-pass characterization timings**, not interaction latency; the engine-level interactive
  numbers are in the KRMA-1182 follow-up below (RGB tick p50 2.9–4.1 ms, decoder-routed Exposure tick
  p50 4.5–6.3 ms through one reused filter).

### Non-Sony DNGs (Apple ProRAW and Samsung)

Same harness, macOS 27.2, decoder `8.dng`, 600×800 frame, fixed region = brightest 0.5% of the neutral
decode (2,400 pixels). Support and defaults differ from the Sony files:

| File | Recovery (default) | Local tone map (default) | Baseline exposure | Region clip, neutral |
| --- | --- | --- | ---: | ---: |
| `IMG_0206` (iPhone 14 Pro) | supported, on | **supported, 1** | −0.29 | 0.035 |
| `IMG_0695` (iPhone 17 Pro) | supported, on | **supported, 1** | 3.82 | 0.020 |
| `20181011_181213` (Samsung) | supported, on | unsupported | 0.0 | 0.333 (every region pixel has one channel at or above 1) |

Boost 1, boost shadow 0.9, EDR 0 and gamut mapping on for all three.

| Control | `IMG_0206` clip / relSpread | `IMG_0695` clip / relSpread | Samsung clip / relSpread |
| --- | --- | --- | --- |
| Neutral | 0.035 / 0.202 | 0.020 / 0.380 | 0.333 / 0.200 |
| Recovery off (on = neutral) | **0.052 / 0.191** | 0.020 / 0.380 | 0.333 / 0.200 |
| Local tone map 0 (1 = neutral) | 0.000 / 0.357, median 0.375 → 0.117 | 0.310 / 0.464, median 0.280 → 0.141 | unsupported, identical |
| Boost shadow 0.5 / 1.5 | identical | identical | identical |
| EDR 1 / 2 | 0.477 / 0.482, p99 1.69 / 1.97 | 0.655 / 0.945, p99 2.48 / 6.10 | 0.333, p99 1.67 / 2.05 |
| RGB Highlights −100 | 0.035 / 0.277 | 0.020 / 0.411 | 0.333 / 0.203 |
| RGB Whites −100 | 0.000 / 0.142 | 0.000 / 0.255 | 0.000 / 0.241 |

- **Highlight recovery has a measurable effect on one file.** On the iPhone 14 Pro, turning it off
  raises the region clip fraction from 0.035 to 0.052 and lowers relSpread from 0.202 to 0.191; the
  median does not move. It is on by default, so the neutral render already includes it. It remains a
  boolean, not a signed slider, and it did nothing on the iPhone 17 Pro, the Samsung or any Sony file.
- **Local tone map is a default-on global tone operator, not a highlight control.** Setting it to 0 on
  the ProRAW files cuts the median by 50–69% (and, on `IMG_0695`, raises region clip to 0.31). It
  has no defensible mapping to Highlights/Whites.
- **EDR gives real extended range on ProRAW** (p99 up to 6.1 on `IMG_0695`), but it also moves the
  median (−10 to −30%) there, so unlike the Sony result it is not a median-neutral candidate.
- **The Samsung region is saturated at the output reference.** All 2,400 region pixels have one channel
  at or above 1, so it is a poor recovery probe: no decoder control changes it, only RGB Whites does.
- **Cost.** 160–200 ms per decoder variant against 5–8 ms for cached RGB controls, as one-shot
  characterization timings. The 54–145 ms figures on a first RGB Highlights tick are the cold develop,
  not the slider; the warm `RenderEngine` ticks on these DNGs are in the KRMA-1182 follow-up below.

These results do not change the decision below; they add two documented behaviours (recovery matters
on some ProRAW, local tone map is supported and on by default on Apple DNGs) that the existing
defaults already respect.

**Decision: no new RAW routing.** Highlights, Shadows, Whites and Blacks (and Contrast) stay RGB for
RAW and standard sources alike. No semantics are defensible: recovery is a boolean (measurable on one
of seven files, and already on by default), local tone map is a global on/off tone operator where
supported (and unsupported on the Sony and Samsung files), shadow boost does not touch highlights, and
EDR/boost are base-tone changes, not signed highlight throws. Neutral rendering is unchanged by this ticket; the
EDR 0 / boost 1 / recovery-on defaults stay as the decoder reports them.
`RAWExposureRoutingTests.testToneSlidersStayRGBAndNeverRedevelopTheRAW` pins the decision so these
sliders neither reach the decoder nor invalidate the developed source mid-drag.

**Revisit when** a bracketed or sensor-clipped reference is available, or a larger camera corpus (more
makes, ProRAW and Bayer, high-contrast scenes) shows highlight recovery or another decoder control
changing output beyond what is recorded here. On the Sony files EDR with a compensating gain was the only
candidate that increased region spread without changing the median; on ProRAW it also moves the median.
It would need a defined headroom-to-display mapping (and clamping behavior
through `CIToneCurve` and Look LUT domains) and a user-facing semantics argument before shipping.

## Follow-up: app-level latency of the RGB highlight controls (KRMA-1182)

`RAWHighlightHeadroomBenchmark` times one develop-plus-readback per control. That is a
characterization of the work, not of interaction: it includes a cold develop, a float CPU readback and
no warmed cache, and its RGB timings ranged from 4 ms to 302 ms between runs. KRMA-1182 measures what
the app does instead, through the production `RenderEngine` and no window
(`RAWHighlightInteractionBenchmark`, 1024 px box, debug build, macOS 27.2, Apple Silicon): one fresh
engine per file and control, a first `.interactive` frame, 4 discarded warm-up ticks, 40 measured
`.interactive` ticks (a distinct value each), then a `.preview` settled frame at a value no tick used
and a repeat of it. Counters are read from `workStatistics()` and `cacheStatistics()` and differenced
over the phase. Exposure, which is decoder-routed (KRMA-1174), is the reference row. Measurement only:
no routing or product code changed.

Per file, across Highlights, Shadows, Whites, Blacks and Contrast (five controls, one run each; a
second full run agreed within about 0.5 ms on every p50):

| RAW | first frame | RGB tick p50 | RGB tick p95 | settled (new value / repeat) | Exposure tick p50 / p95 (decoder) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `20181011_181213.dng` (Samsung) | 87–92 ms | 3.0–3.1 ms | 3.1–3.9 ms | 3–4 / 2–3 ms | 4.5 / 4.6 ms |
| `DSC00324.ARW` | 172–212 ms | 2.9–3.5 ms | 3.1–3.8 ms | 3 / 2 ms | 4.8 / 5.3 ms |
| `DSC01019.ARW` | 259–338 ms | 4.0–4.1 ms | 4.1–4.8 ms | 4 / 2 ms | 6.3 / 6.9 ms |
| `DSC01104.ARW` | 260–270 ms | 2.9–3.0 ms | 3.0–3.2 ms | 3 / 2 ms | 4.9 / 5.3 ms |
| `DSC01153.ARW` | 260–267 ms | 3.9–4.0 ms | 4.0–4.5 ms | 4 / 2 ms | 6.1 / 6.7 ms |
| `DSC04513.ARW` | 222–234 ms | 2.9–3.0 ms | 3.0–3.4 ms | 3–4 / 2 ms | 4.8 / 5.0 ms |
| `IMG_0206.DNG` (iPhone 14 Pro) | 163–187 ms | 3.0–3.1 ms | 3.2–3.3 ms | 3 / 2 ms | 4.8 / 5.6 ms |
| `IMG_0695.DNG` (iPhone 17 Pro) | 194–202 ms | 3.0–3.1 ms | 3.1–3.4 ms | 3 / 2 ms | 4.5 / 5.0 ms |

Counters (identical for all eight files and all five RGB controls):

| Phase | Decoder output requests | Filter constructions | Developed-source cache | Processing prefix |
| --- | ---: | ---: | --- | ---: |
| First interactive frame | 1 | 1 | 0 misses (the interactive session does not use the cache) | — |
| 40 RGB ticks | **0** | 0 | 0 hits / 0 misses | 39 materializations |
| Settled frame after RGB ticks | **0** | 0 | 0 misses | — |
| 40 Exposure (decoder) ticks | 40 | 0 | 0 hits / 0 misses | 0 |

Reading:

- **No RGB highlight control re-develops the RAW.** After the first frame the decoder is never asked
  for output during Highlights, Shadows, Whites, Blacks or Contrast ticks or on the settled frame; the
  one interactive `CIRAWFilter` is built once and the completed decoder output is reused. Every RGB tick
  instead rebuilds the processing prefix (39 materializations for 40 ticks) and still costs 3–4 ms.
  The earlier "cold develop" figures belong to the first frame, not the slider.
- **Warm RGB ticks are 2.9–4.1 ms (p50) and at most 4.8 ms (p95)**, a quarter of the 16.7 ms frame
  budget, and the five controls are indistinguishable on a file (spread ≤ 0.6 ms). The file, not the
  control, sets the level: `DSC01019` and `DSC01153` sit at about 4 ms and the others at about 3 ms
  (not explained by camera or resolution, since `DSC01104` shares a body with `DSC01153`).
- **A decoder-routed control costs more per tick, not less**: Exposure ticks are 4.5–6.3 ms (p50)
  because each one asks the retained filter for a new output (40 output requests for 40 ticks), about
  1.3–2.3 ms more than the RGB ticks on the same file. The decoder spelling is not slow but is
  not cheaper either, consistent with the KRMA-1174 table.
- **The standalone timings do not estimate warm interaction.** The one-shot RGB figures of 4–7 ms were
  coincidentally near the warm value, but the same harness also produced 54–302 ms for the first RGB
  Highlights call because that call pays for the develop. Quote the table above, not those figures,
  for interactive cost. The comparison of "RGB costs 4–7 ms versus 200–400 ms for decoder variants"
  therefore overstates the case for RGB: the like-for-like warm comparison is about 3–4 ms (RGB) versus
  4.5–6.3 ms (decoder-routed Exposure), a difference that is real but small.
- **Cold outliers.** The first row measured in a process (Highlights on the Samsung DNG, 265 ms
  against about 90 ms for the other controls on that file) and the Highlights row of several files
  carry process-level and shader first-use cost in their first frame; `DSC01019` Highlights reached
  338 ms in one run. They are first-frame numbers and are not repeated by later controls on the file.
- **Not measured.** Decoder-routed Highlights/Shadows/Whites/Blacks/Contrast do not exist (the
  decision above keeps them on RGB), so there is no decoder tick to compare for those controls; the
  Exposure row is the nearest proxy. The 1024 px interactive box is the only size measured, and this is
  a single debug-build run per file and control.

This does not change the KRMA-1176 decision, which rests on semantics (no decoder control has a signed,
highlight-local meaning). It removes latency as an argument in either direction, and any future
routing decision belongs in its own issue with semantic and visual evidence.

## Follow-up: Luminance noise reduction routed to the decoder (KRMA-1175)

The inspection's note that Detail controls run on developed RGB no longer holds for global Luminance
noise reduction on a RAW whose decoder supports it: it is applied through
`CIRAWFilter.luminanceNoiseReductionAmount`, above the decoder's per-image default. Colour noise
reduction and Sharpening stay RGB. See
[`ENGINEERING_GUIDE.md`](ENGINEERING_GUIDE.md#raw-noise-reduction-routing).
