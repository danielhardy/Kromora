# Film-simulation-inspired Looks: research and design

Status: research for the "Film simulation" Look family. Not a shipped contract; see
[`LOOKS.md`](LOOKS.md) for the current Look format and asset policy.

Scope is **color profiles only**: the in-camera Fujifilm film simulations, not the surrounding
"recipes" (Dynamic Range, white balance shifts, grain, Clarity, Highlight/Shadow sliders). Those
are separate controls that Kromora already exposes as ordinary sliders.

## What a film simulation is

A Fujifilm film simulation is a fixed in-camera transform from developed RAW to an sRGB JPEG. (Kromora's Looks are not sRGB: they are authored in Display P3, the editor's working space, so this describes the source behavior, not the target encoding.) It is
the combination of:

1. a **tone curve** (toe, midtone slope, shoulder);
2. **per-hue saturation and hue shifts**, which carry most of each simulation's identity;
3. **luminance-dependent color behavior** (deep, saturated colors lose lightness);
4. a **shadow/highlight tint** (split tone) in some simulations.

All four are static functions of one RGB triple, so a single 3D LUT can carry them. That fits
Kromora's Look pipeline (`CIColorCubeWithColorSpace`, base look before sliders). Spatial effects
(grain, Clarity) are out of scope for a cube.

## Sources and confidence

No source publishes measured values; Fujifilm does not release the transforms. Everything below
is qualitative and was cross-checked between sources. Treat numbers in the parameter table as
**best-guess starting values to tune by eye**, not as measurements.

- [Imaging Resource: guide to Fuji's Film Simulations](https://www.imaging-resource.com/news/fujifilm-film-simulations-definitive-guide/)
  (best per-hue description; predates Nostalgic Neg and Reala Ace)
- [JM Peltier: Classic Chrome vs Classic Neg](https://www.jmpeltier.com/fujifilm-classic-chrome-vs-classic-neg/)
- [Fuji X Weekly: Classic Negative recipes](https://fujixweekly.com/2024/03/20/my-15-favorite-film-simulation-recipes-that-use-classic-negative/)
- [Fujifilm: Color Chrome and Film Grain Effects](https://www.fujifilm-x.com/en-us/stories/advanced-month-4-camera-features-13-color-chrome-and-film-grain-effects/)
- [pal2tech: Color Chrome Effect and FX Blue](https://pal2tech.com/guides/camera/fujifilm-color-chrome-effect-fx-blue-guide/)

Sources conflict on Reala Ace shadows (soft vs lifted) and on how Color Chrome FX Blue acts.
Nostalgic Neg and Reala Ace have the thinnest evidence; they need the most visual tuning.

## The simulations

| Simulation | Based on | Tone | Color character |
| --- | --- | --- | --- |
| Provia / Standard | Fujichrome Provia | Moderate contrast | Neutral baseline. Pure reds nudged up. Oranges drift toward yellow, light cyan toward blue. |
| Velvia / Vivid | Fujichrome Velvia | Somewhat high contrast | Very high saturation, most in dark greens, dark blues, pure reds. Blues skew toward magenta (royal-blue sky), yellow toward orange. Bright reds can clip detail. |
| Astia / Soft | Fujichrome Astia | Lower than Provia, shadows stay firm, shoulder flattened | Higher saturation than Provia, esp. dark greens and darker skin. Fair skin less rosy. Cyan/light blue drift toward blue. |
| Classic Chrome | No specific film (Kodachrome-like, documentary) | Firm shadows, soft highlights | Low saturation; yellows, yellow-greens, dark blues/purples pulled back most. Blues shift toward cyan, magenta removed from skies. Cool overall; mutes mixed-light casts. |
| PRO Neg. Std | NPS 160 negative | Very low contrast, flat | Muted, accurate color, minimal hue shift. Skin focus. |
| PRO Neg. Hi | NPS 160 negative | Steeper than Std | Slightly more saturation, darker shades richer. Same hues as Std. |
| Classic Neg. | Superia 100-style negative | Very high contrast, curve varies by color | Reds boosted; yellows, greens, purples, blues suppressed. Strong uneven hue shifts, slight red cast, warm overall, split-tone feel. Dark "Superia green". |
| Nostalgic Neg. | Warm, amber 70s print look | Soft, lifted shadows | Amber-brown highlights, cool (blue-green) shadows, rosy skin, yellow-leaning greens, slightly purple blues. Weakest evidence. |
| Reala Ace | Fujicolor Reala | Hard-ish tone with analog edge | Near-neutral, true to life, no cast. Luminance shifts in blues/greens/reds give depth. Weak evidence. |
| Eterna / Cinema | Eterna motion-picture stock | Very low contrast, wide range, soft shoulder and toe | Low saturation (greens, magentas, purples most), little hue shift. Grading base. |
| Eterna Bleach Bypass | Skipped-bleach reversal | Very high contrast, crushed shadows, washed highlights | Very low, uniform saturation, little hue shift. |
| Acros (+Y/R/G) | Neopan Acros B&W | Hard in lower mid to highlights, soft into shadows | Monochrome. Yellow darkens sky, Red darkens sky more and lightens foliage, Green softens foliage contrast. |
| Monochrome (+Y/R/G) | Provia, color removed | Flatter than Acros | Monochrome, same filters. |
| Sepia | Toned print | Like Monochrome | Warm toned monochrome. |

### Color Chrome Effect and FX Blue

These are not saturation controls. Color Chrome Effect pulls down luminance of **saturated warm
colors** (reds, then yellows, sometimes greens) so gradation inside them survives, in the manner of
Fortia slide film. Color Chrome FX Blue does the same only for **blue**, deepening skies like a
polarizer. Both are JPEG/HEIF-only in camera. Weak/Strong differ by strength only.

Takeaway for Kromora: model these as a **luminance-vs-saturation step** inside the cube, shared by
all simulations, with a per-simulation strength. Each simulation is calibrated with them on, since
they are on by default in the camera for most JPEG output.

## Parameterization

Each simulation is defined by the same small parameter set, so the family is data, not eight
bespoke functions:

- `toneCurve`: toe lift, midtone slope, shoulder rolloff (applied per channel or to luma, per sim).
- `globalSaturation`: scalar around a luma-preserving gray axis.
- `hueSectors`: per-hue (about 12 sectors, smoothly interpolated) saturation multiplier and hue
  rotation in degrees. This is where Classic Chrome vs Classic Neg are actually different.
- `chromeDepth`: luminance reduction proportional to saturation, with warm and blue strengths.
- `shadowTint`, `highlightTint`: split-tone color and amount.
- `skinGuard`: limit on hue/saturation change in the skin-hue range so portraits stay believable.

### Starting values (tune by eye)

Hue-sector entries are written as saturation multiplier and hue shift. "–" means leave neutral.

| Sim | Global sat | Tone | Notable hue work | Tint |
| --- | --- | --- | --- | --- |
| Provia | 1.00 | gentle S | red 1.05; orange to yellow 4 degrees; cyan to blue 6 degrees | none |
| Velvia | 1.35 | strong S, firm toe | dark green 1.4, dark blue 1.4, red 1.25; blue to magenta 8 degrees; yellow to orange 6 degrees; heavy chromeDepth | none |
| Astia | 1.10 | softer S, flat shoulder, firm shadows | dark green 1.2; skin 0.95, hue slightly away from red; cyan to blue 6 degrees | none |
| Classic Chrome | 0.78 | firm shadows, soft highlights | yellow 0.6, yellow-green 0.6, dark blue 0.7; blue to cyan 12 degrees; magenta reduced in sky range | slight cool shadow |
| Pro Neg Std | 0.85 | flat, low slope | near neutral; skin protected | none |
| Pro Neg Hi | 0.92 | Std with steeper slope | as Std, darker shades richer | none |
| Classic Neg | 0.90 | very high slope; per-hue curve variation | red 1.2; yellow 0.7, green 0.65 (dark), blue 0.7, purple 0.7; red lean 3 degrees | cool shadows, warm highlights |
| Nostalgic Neg | 0.95 | soft slope, lifted toe | green to yellow 8 degrees; blue to purple 5 degrees; skin rosy | blue-green shadows, amber highlights |
| Reala Ace | 1.00 | moderate slope, slight edge | luminance shifts only (blue darker, green and red slightly deeper) | none |
| Eterna | 0.65 | very low slope, soft toe and shoulder | green 0.5, magenta 0.5, purple 0.5 | none |
| Eterna Bleach Bypass | 0.35 uniform | very high slope, crushed shadows, bright highlights | none | none |
| Acros / Monochrome | n/a | Acros hard mid-to-high, soft shadows; Monochrome flatter | channel-mix weights for Y/R/G filter (luma from RGB) | none |

## Implementation constraints in Kromora today

- **Bundled starter cubes are 3x3x3.** Hue-selective work needs a real grid. Film-simulation
  cubes should ship at 33^3 (the size Save as Look writes; the parser allows up to 65). A 33^3
  text cube is about 36k rows, roughly 600 KB; confirm bundle size is acceptable.
- **Where they come from.** The existing procedural generator is not in the repo scripts. A new
  deterministic generator (script or test-target tool) that emits the cubes from the parameter
  table keeps them reproducible and reviewable.
- **Input color space.** Per ADR-KRMA-1115 the family is authored in Display P3 (`WorkingSpace.current`),
  stamped `KROMORA_AUTHORING_SPACE: displayP3`, and recorded in the manifest notes. Hue and saturation
  targets below are described qualitatively and are tuned in P3; do not relabel sRGB tables.
- **Base-look ordering.** Because the Look runs before Exposure/Color sliders, the Looks do not
  need to compensate for exposure; they should be exposure-neutral at middle gray.
- **Intensity.** The existing Look Intensity crossfade is the Weak/Strong control; no extra
  UI is needed.
- **Grain** is a separate existing stage; do not bake it into cubes.

## Naming, provenance, and legal

Fujifilm's simulation names and the underlying camera transforms are Fujifilm's. `LOOKS.md` already
commits that Kromora bundles **no official profiles or copied emulation data** and uses film and
manufacturer names as descriptive inspiration only. This family keeps that rule:

- The cubes are original, generated from the published qualitative descriptions above.
- **Do not derive them from Fuji JPEG/RAW pairs** with Derive Look: that would copy Fujifilm's
  processing and break the manifest policy. Users may derive their own, on their own files.
- **Decision: no trademarked names.** Neither Fujifilm's simulation names nor film-stock names
  (Provia, Velvia, Astia, Classic Chrome, Superia, Eterna, Acros, Kodachrome, and so on) appear in
  Look names, manifest entries, inspector text, store copy, or code identifiers. This document
  uses them only as research vocabulary. Looks get original descriptive names:

  | Research reference | Kromora Look |
  | --- | --- |
  | Provia | Clean Slide |
  | Velvia | Vivid Slide |
  | Astia | Soft Slide |
  | Classic Chrome | Field Report |
  | PRO Neg. Std | Portrait Soft |
  | PRO Neg. Hi | Portrait Crisp |
  | Classic Neg. | Street Negative |
  | Nostalgic Neg. | Amber Print |
  | Reala Ace | True Color |
  | Eterna | Cine Flat |
  | Eterna Bleach Bypass | Silver Bypass |
  | Acros (+Y/R/G) | Fine Mono (+ Yellow/Red/Green filter variants) |
  | Monochrome | Plain Mono |
  | Sepia | Warm Tone |

  The names are proposals; keep them descriptive and unlike any manufacturer's wording. Categories
  are "Slide", "Negative", "Cine", and the existing "Monochrome"; none says "Fujifilm" or "film
  simulation".

## Calibration baseline

There are no reference photographs or measurements to verify against, so the cubes are
**best-guess approximations** of the described characters. Nothing in this family claims
fidelity to any camera.

Author and eyeball the cubes against Kromora's **neutral RAW develop** of Sony ARW and Apple
DNG/ProRAW files (the gitignored `realworldtest/` folder already holds both; see its README),
because a Look is applied to the developed working-space image, not to a camera JPEG.
Apple and Sony JPEG/HEIC files already carry their own baked-in tone and color (Smart HDR,
Photographic Styles, Creative Looks), so a Look stacks on top of that; treat them as a
secondary check that nothing falls apart, not as the calibration target.

## Verification approach

Structural checks only, run on a synthetic chart (gray ramp, hue sweep, skin-hue patches):
cube parses at 33^3, tone curve is monotonic, neutral axis stays neutral where intended, no
clipping, and relative ordering between Looks (for example Vivid Slide more saturated than
Clean Slide). No tolerance against the parameter table and no photo-matching criterion.
Final taste adjustments are manual and not an acceptance gate.
