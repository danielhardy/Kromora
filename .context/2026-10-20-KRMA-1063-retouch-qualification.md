# Retouch qualification execution — 2026-10-20

Historical execution record for KRMA-1063. Codex prepared and ran camera-scale comparisons at the
user's request. **Human visual acceptance remains Not run.** This record does not close KRMA-1016's
retouch release gate.

## Candidate and environment

- Product source: `116f14fddaa4fc780418957aee4932e8717057c1`; packaged revision `116f14fddaa4`.
- App: `.build/xcode/Build/Products/Release/Kromora.app`, ad hoc signed. `scripts/app-store-build.sh`
  passed packaging, signature, sandbox-entitlement and resource checks.
- macOS 27.2 (26B118), Mac mini Apple M4 Pro, 48 GB. Target remains macOS 26 / Apple Silicon.
- Execution: Codex, 2026-10-20. Human pixel reviewer: pending.
- Local licensed sources: copies of `realworldtest/IMG_0371.DNG`, `IMG_0878.DNG`, and `IMG_1370.DNG`.
  Each neutral develop is 8064 × 6048. SHA-256 hashes of the copies match the originals; hashes and
  dimensions are in the local `fixtures.json`.

## Method and scope

All photo evidence is ignored under `.build/krma1063-evidence/`; no photos are committed or uploaded.
Open the local viewer at `http://127.0.0.1:8765/review.html` while its loopback-only server is running,
or open `.build/krma1063-evidence/review.html` in a browser. To restart the viewer:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory .build/krma1063-evidence
```

The harness (`run.swift` and `retouch-evidence` in that directory) links the existing KromoraKit build
from the same frozen source. It uses production RenderEngine, source selection/refinement, retouch,
portable-package import, EditDocumentStore and encoded export APIs. This window-independent harness
is separate from the signed app's UI; it is not a claim that every repair was drawn or exported through
that UI.

Copies of the camera DNGs were neutrally developed at full resolution. Controlled soft dust, hard
specks and continuous fibres were then added to those developed PNGs without resizing. This supplies
known defects over real photographic texture, rather than evidence of naturally occurring dust or
RAW-native retouch. Manual Heal and Clone use a known clean horizontal source offset of 220 source
pixels; automatic-source Heal stores no manual offset and exercises the production picker/refinement.
Masks and offsets are source-normalized. Opacity, feather and other settings use model defaults.

The final set contains nine cases × three modes = **27 comparisons**. All before/after/reference crops
are 600 × 400 source pixels displayed at their intrinsic size. Keep browser zoom at 100%; narrow
viewports scroll rather than shrink these crops. Full-frame PNG outputs are also available locally.

Initial hair fixtures were discovered to be dotted curves during evidence inspection. Cases 03, 05,
07 and 09 were excluded from the final set and superseded by continuous-fibre cases 10–13. Their
calibration files remain local for traceability. `results-final.json` contains only the 27 valid results;
`results.json` also contains the 12 superseded calibration results. No quality pass was assigned to
those discarded fixtures.

Two disposable packages hold the recipes:

- `Retouch Review Library`: original nine calibration cases × three modes (27 assets), including the
  five retained non-fibre cases. Initially named `Retouch Review.kromoralibrary`; renamed while all
  writers were closed because Settings' folder picker disabled package bundles. KRMA-1075 tracks this.
- `Continuous Fibre Review Library`: four corrected fibre cases × three modes (12 assets).

The second package was generated independently while the first was open in the app. No writer lease
was bypassed and no managed original was replaced.

## Case matrix

All three mode columns below are **human verdicts**. Mechanical success does not imply visual acceptance.

| Row | Background / defect | Local case IDs | Manual Heal | Auto source Heal | Clone |
|---|---|---|---|---|---|
| 1 | Sky / soft dust | 01-sky-dust | Not run | Not run | Not run |
| 2 | Cloud texture and cloud edge / hard speck | 02-cloud-speck, 08-cloud-edge-speck | Not run | Not run | Not run |
| 3 | Cloud texture and cloud edge / continuous fibre | 10-cloud-fibre, 13-cloud-edge-fibre | Not run | Not run | Not run |
| 4 | Foliage / soft dust and continuous fibre | 04-foliage-dust, 11-foliage-fibre | Not run | Not run | Not run |
| 5 | Water / hard speck and continuous fibre | 06-water-speck, 12-water-fibre | Not run | Not run | Not run |
| 6 | Skin-like detail / dust or speck | None: no representative licensed crop available | Not run | Not run | Not run |

For each mode, inspect remaining defect, halo/seam, blur/texture loss, duplicated structure and
source-patch contamination. The viewer has a clean-reference toggle, individual Pass/Fail/Not run
buttons, notes, and a JSON download. Decisions remain local to the browser until saved; they do not
advance DispatchGraph automatically. Row 6 needs a suitable approved fixture or an explicit reviewer
omission disposition. Brick was not separately exercised; water supplies the row-5 background.

## Mechanical checks

| Check | Result | Evidence / limit |
|---|---|---|
| Packaged candidate build | Pass | `app-store-build.log`; ad hoc, not Apple distribution signing |
| Native output dimensions | Pass, 27/27 | Every full-frame PNG is 8064 × 6048 |
| Repair changes the damaged crop | Pass, 27/27 | Confirms execution only, not quality |
| Native-size settled preview/export crop equality | Pass, 27/27 | Exact 600 × 400 RGBA comparison through the harness; UI downscaled preview is not asserted identical |
| Fresh store reload preserves full recipe | Pass, 27/27 | Document equality includes mask samples, source offsets, modes and defaults |
| Close package lease, reopen, fresh renderer, full-frame export equality | Pass, 6/6 final representatives | All modes of 01-sky-dust and 13-cloud-edge-fibre; full-frame decoded RGBA equality |
| Signed app opens test package and saved recipe | Pass | App showed 27 assets; selected 01-sky-dust-auto-heal had one saved repair |
| Signed app File export and relaunch persistence | Not run to completion | Focused export commands were disabled while app was background; after user foregrounded it, automation reported macOS locked |
| Restore original default library | Pending | Awaiting screen unlock to use Settings > Use Default Library > Relaunch; personal package has not been retouched |

`package-reopen.json` also contains three excluded case-09 calibration checks; those are not counted
in the six final representatives above. Rendering in a fresh engine/package is recorded separately
from launching the signed app. No display-bound performance capture was run.

## Live-session boundary and remaining work

The app originally used the default personal package (`~/Pictures/Kromora Library.kromoralibrary`).
Its photos were not modified. Settings temporarily selects the disposable `Retouch Review Library`.
The first normal Settings relaunch safely released the personal writer lease and opened the test
package. UI access later required foregrounding; the user confirmed foregrounding, but the next
accessibility call reported the Mac locked. A screen-unlock request is pending. Do not describe the
personal-library restoration or the remaining signed-app export/relaunch check as complete.

After unlock, finish a representative signed-app full-resolution export, quit/reopen to confirm the
saved repair, then restore Default Library and verify the original 56-photo library opens. The human
can review the prepared 27 comparisons without repeating their setup or drawing the repairs. Retain
human review until the actual pixels and missing skin row have been assessed.
