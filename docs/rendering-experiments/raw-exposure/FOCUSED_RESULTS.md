# Focused Sony RAW comparison

4 November 2026, macOS 27.2. Follow-up to [the initial experiment](RESULTS.md). These are real, full-resolution crops from two local Sony RAWs, not 800-pixel decodes. The experiment leaves production behavior and documents untouched.

## Exposure and highlights

Compare decoder exposure −2 EV against RGB exposure −2 EV (with and without EDR 1). For each photo, one global linear gain brings the RGB variant's **800-pixel whole-image median** to the RAW variant's median: 0.628 for `DSC01153`, 0.621 for `DSC00324`. Full-size fixed crops then receive that same gain. The displayed PNGs get a shared +2 EV afterwards for readability. The gain and common display adjustment are not separate exposure slider settings or locally optimized highlight matches; the linear measurements are taken before the common display +2 EV. No Look or other creative adjustment is active.

- [Flag comparison](renders/DSC01153/focused/white_flag_comparison.jpg) — RAW exposure, RGB exposure, RGB exposure with EDR 1, left to right. [Full-resolution RAW crop](renders/DSC01153/focused/white_flag_raw.png), [RGB crop](renders/DSC01153/focused/white_flag_rgb.png), [EDR crop](renders/DSC01153/focused/white_flag_rgb_edr1.png).
- [Bird comparison](renders/DSC00324/focused/bird_detail_comparison.jpg), same order.

In the flag crop the RAW variant has visibly stronger bright/dark differentiation in the fabric and a brighter sky. Its crop-wide linear luminance standard deviation is 0.0620 versus 0.0244 for RGB and 0.0264 for RGB+EDR; mean adjacent-pixel difference is 0.00171 versus 0.00096 and 0.00104 respectively. The crop includes sky, dark, and colored fabric, so neither statistic isolates white-fabric texture. The mean crop luminance is also different (0.0325 vs 0.0247 and 0.0253), despite global median matching. Thus the result confirms a visually and numerically meaningful **tone response**, but not necessarily recovery of detail unavailable to RGB. The RGB+EDR result was closer to RGB than RAW by full-crop RGB RMS (0.0393 vs 0.0419, each measured against RAW); that number cannot tell us if RGB can be made equivalent with a more suitable tone curve or whether the difference is desirable.

The ISO 2000 bird crop also shows different tone. Its crop RGB RMS versus RAW is 0.00590 for RGB and 0.00588 for RGB+EDR, while the RAW and RGB crop mean luminances are 0.0490 and 0.0441. The grass shadow and bright background measurements are in the JSON. These are not calibrated color-error or independent noise measurements. A controlled local tone match and bracketed or other ground truth are still needed to prove actual highlight reconstruction. The flag crop has clear detail, but no verified sensor-clipped reference; a photo with truly clipped channels is a better recovery test.

## Noise and sharpening

`DSC00324.ARW` is a Sony ILCE-7M2 ISO 2000 image. Apple reports both controls supported and defaults to luminance NR **0.712** and sharpness **0.890**. We rendered the same 1140 × 1140 bird crop at default, RAW NR 0/1, RAW sharpness 0/1, plus one RGB noise-reduction and one RGB sharpening setting. Apple defaults remain on for the RGB variants, so those are intentionally *additional* operations. This is a sensitivity check, not a quality-matched shootout.

| Variant | Mean adjacent luminance difference | RGB RMS vs default |
| --- | ---: | ---: |
| Decoder default | 0.00858 | — |
| RAW NR 0 | 0.01276 | 0.00604 |
| RAW NR 1 | 0.00512 | 0.00531 |
| RGB NR, illustrative | 0.00382 | 0.01070 |
| RAW sharpness 0 | 0.00619 | 0.00595 |
| RAW sharpness 1 | 0.00888 | 0.00074 |
| RGB sharpening, illustrative | 0.01127 | 0.00493 |

These settings produce measurable differences. Neighbor difference combines fine subject texture, edges and noise; it is not a quality score. RAW NR and sharpening change the existing decoder settings, while RGB operations stack on top. A fair choice requires matching the amount of noise suppression or edge enhancement, then comparing fine feathers, halos and flat-background noise across more images. The near-maximum default sharpness leaves little headroom in Apple's RAW sharpness control on this file. See the [default crop](renders/DSC00324/focused/detail_default.png), [RAW NR 0](renders/DSC00324/focused/detail_raw_nr0.png), [RAW NR 1](renders/DSC00324/focused/detail_raw_nr1.png), and [RGB NR](renders/DSC00324/focused/detail_rgb_nr.png).

## Decision

RAW exposure is now a strong candidate for a versioned prototype: on these two ARWs it produces a meaningful, visible tonal change, and on the flag it changes bright-region contrast substantially even after overall brightness alignment. We have **not** established that it recovers more original highlight information or that it would outperform a tailored RGB tone curve. EDR 1 alone did not reproduce the RAW exposure response in these crops. RAW NR/sharpening are also worth investigating, but this test does not justify replacing the existing controls: the amounts and noise/detail tradeoffs were not matched.

Retain the current path for existing edits, and test an opt-in RAW exposure implementation for new-version edits with representative blown highlights, Looks on/off, calibrated slider response, and actual `RenderEngine` interactive latency. The prior standalone performance proxy remains in [RESULTS.md](RESULTS.md); this follow-up does not measure app interaction.

## Reproduce

Compile `focused.swift` and `detail.swift` using the `swiftc` command shown in [README.md](README.md), changing the source and executable names. `focused` takes RAW path, experiment output directory, and the matching initial `metrics/<name>.json` (its recorded median is used for the brightness match). `detail` takes the DSC00324 RAW path and output directory. The ROI fractions are documented in `focused.swift`; the detail tool is specialized to the ISO 2000 bird. GPU access may require running outside a restricted sandbox. Machine-readable measurements: [flag](metrics/DSC01153-focused.json), [bird](metrics/DSC00324-focused.json), and [detail](metrics/DSC00324-detail.json).
