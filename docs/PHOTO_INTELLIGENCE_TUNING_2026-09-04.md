# Photo-intelligence tuning report — 2026-09-04

LUMO-207 tuning was evaluated against the generated 21-fixture corpus from LUMO-204. The
pre-change report was generated with:

```sh
./scripts/photo-intelligence-report.sh
```

The HTML artifacts are intentionally non-committed. The representative base fixture cards below
record the before/after values shown in the baseline and tuned reports; the two luminance variants
per category were also reviewed in the same reports.

| Fixture | Parameter | Baseline | Tuned | Corpus reason |
| --- | --- | ---: | ---: | --- |
| normal-daylight | highlights / shadows | -23.937 / 24.727 | -12.889 / 9.891 | Avoid broad tonal-tail changes on a balanced image. |
| clear-backlit | highlights / shadows | -29.337 / 38.000 | -16.596 / 20.485 | Keep highlight protection and subject opening while removing the safety-bound clamp. |
| intentional-high-key | highlights / blacks | -26.000 / -18.000 | -7.760 / -9.617 | Preserve the high-key look instead of darkening both bright and black points. |
| intentional-low-key | exposure / shadows / whites | 0.423 / 18.700 / 16.120 | 0.252 / 7.025 / 11.606 | Reduce normalization of an intentionally dark scene. |
| flat-low-contrast | contrast / shadows | 23.920 / 1.373 | 26.680 / 0.549 | Increase the measured low-contrast correction while leaving shadows neutral. |
| clipped-highlights | highlights | -32.631 | -21.224 | Retain clipping protection without the prior broad-tail overcorrection. |
| clipped-shadows | shadows | 24.846 | 9.927 | Keep a positive recovery response without lifting the whole image excessively. |

## Changes justified by the comparison

- `AutoLightTuning.exposureIntentExponent` increased from 2.8 to 4.0. The low-key base exposure
  moved from +0.423 EV to +0.252 EV while high-key stayed near neutral.
- Highlight tail gain decreased from 26 to 14, while clipping gain increased from 22 to 24. The
  ordinary base card moved from -23.937 to -12.889, while the clipped-highlights card remained
  strongly protective at -21.224.
- Shadow lift gain decreased from 25 to 10 and the backlight-specific gain from 28 to 20. Normal
  daylight shadows moved from +24.727 to +9.891; clear-backlit shadows remained positive at
  +20.485 and no longer hit +38.
- High-key highlight and black-point brakes and a low-key white-point brake reduced changes that
  counteracted the scene intent. The high-key black point moved from -18.000 to -9.617, and the
  low-key white point from +16.120 to +11.606.
- The contrast target spread moved from 0.72 to 0.78. Balanced daylight moved from -4.762 to
  -2.002, while flat contrast increased from +23.920 to +26.680.

The semantic corpus remained green before and after, and no fixture category lost its expected
scene facts. These changes are policy-constant tuning only; no structural follow-up was exposed.
The algorithm version is now 2 because the output meaning changed.

Known limitation: this is a deliberately small generated corpus (seven base scenarios and two
variants each). It does not validate real faces, camera rendering, or photographic preference.
Broader real-photo validation remains opt-in through the existing `KROMORA_RAW_FIXTURE_DIR` lane.
