# Retouch qualification execution — 2026-10-20

Historical execution record for KRMA-1063. Codex prepared and ran camera-scale comparisons at the
user's request. **Human review is recorded: 23 Pass, 4 Fail; skin detail Not run.** The foliage Manual Heal finding keeps
KRMA-1016's retouch release gate open; skin coverage is explicitly omitted.

## Candidate and environment

- Product source: `116f14fddaa4fc780418957aee4932e8717057c1`; packaged revision `116f14fddaa4`.
- App: `.build/xcode/Build/Products/Release/Kromora.app`, ad hoc signed. `scripts/app-store-build.sh`
  passed packaging, signature, sandbox-entitlement and resource checks.
- macOS 27.2 (26B118), Mac mini Apple M4 Pro, 48 GB. Target remains macOS 26 / Apple Silicon.
- Execution: Codex, 2026-10-20. Human pixel reviewer: the user; supplied review export records
  27 decisions from 2026-10-20, 21:57–22:00 America/Boise (timestamps stored in UTC).
- Local licensed sources: copies of `realworldtest/IMG_0371.DNG`, `IMG_0878.DNG`, and `IMG_1370.DNG`.
  Each neutral develop is 8064 × 6048. SHA-256 hashes of the copies match the originals; hashes and
  dimensions are in the local `fixtures.json`.

## Method and scope

Original photo evidence is ignored under `.build/krma1063-evidence/`; a durable copy of the reviewed
crops, final full-resolution outputs, metadata, helpers and supplied verdicts is saved under ignored
`artifacts/retouch-review-2026-10-20/`. No photos are committed or uploaded.

Open `artifacts/retouch-review-2026-10-20/Kromora Retouch Review.html` in a regular browser for the saved
viewer. Its 46 review images and supplied decisions are embedded in the HTML, so the review itself
needs no server or build cache. Keep the adjacent `exports/` and `ui-exports/` folders for the optional
full-resolution links. `human-review.json`, `reviewed-results.json`, and `archive-manifest.json` preserve
the supplied verdicts and provenance. The raw, photo-free review export is also committed as
[human-review.json](../.dg/assets/KRMA-1063/human-review.json).
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
| 1 | Sky / soft dust | 01-sky-dust | Pass | Pass | Pass |
| 2 | Cloud texture and cloud edge / hard speck | 02-cloud-speck, 08-cloud-edge-speck | Pass 2/2 | Pass 2/2 | Pass 2/2 |
| 3 | Cloud texture and cloud edge / continuous fibre | 10-cloud-fibre, 13-cloud-edge-fibre | Pass 2/2 | Pass 2/2 | 1 Pass, 1 Fail (10; reviewer considers minor) |
| 4 | Foliage / soft dust and continuous fibre | 04-foliage-dust, 11-foliage-fibre | 1 Pass, 1 Fail (04; dark branch) | Pass 2/2 | Pass 2/2 |
| 5 | Water / hard speck and continuous fibre | 06-water-speck, 12-water-fibre | Pass 2/2 | Pass 2/2 | Fail 2/2 (reviewer considers minor/close) |
| 6 | Skin-like detail / dust or speck | None: no representative licensed crop available | Not run | Not run | Not run |

For each mode, inspect remaining defect, halo/seam, blur/texture loss, duplicated structure and
source-patch contamination. The viewer has a clean-reference toggle, individual Pass/Fail/Not run
buttons, notes, and a JSON download. Decisions remain local to the browser until saved; they do not
advance DispatchGraph automatically. Row 6 remains Not run because no representative licensed crop is available,
as recorded in the supplied export; no skin-quality claim is made. Brick was not separately exercised; water supplies the row-5 background.

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
| Signed app File export | Pass: full resolution, readable PNG | `ui-exports/01-sky-dust-auto-heal.png.png`, 8064 × 6048; app displayed Export complete |
| Signed app repair after normal quit/reopen | Pass: saved recipe present | Reopened the same photo; Heal inspector showed 1 spot. This checks saved recipe presence, not a second export after relaunch |
| Signed app export versus harness full-frame pixels | Not exact | 2,023 of 48,771,072 pixels differ, confined to the repair at inclusive bounds x=4646–4707, y=756–815; maximum RGB channel difference 2/255. All other pixels match. No visual acceptance inferred. KRMA-1085 found no differences among twelve in-process SwiftPM replay variants; this does not isolate the signed app because its export was not rerun with those variants. Cause remains unknown (see "KRMA-1076 reconciliation" below). |
| Restore original default library | Pass | Settings > Use Default Library > Relaunch; default path shown and Use Default disabled; replacement app showed 56 of 56 photos |

`package-reopen.json` also contains three excluded case-09 calibration checks; those are not counted
in the six final representatives above. Rendering in a fresh engine/package is recorded separately
from launching the signed app. No display-bound performance capture was run.

## Live-session completion and remaining human review

The app originally used the default personal package (`~/Pictures/Kromora Library.kromoralibrary`).
Its photos were not modified. The first normal Settings relaunch safely released that writer lease
and opened the disposable package. Screen locking interrupted the initial session; the user later
unlocked the Mac and explicitly confirmed Kromora was frontmost.

On continuation (2026-10-20, America/Boise), File > Export was enabled. Codex selected PNG, kept
metadata/GPS/sharpening/naming options unchanged, and chose the local `ui-exports` directory. The
app displayed **Export complete** and **Exported 1 image to ui-exports**. The file decodes at native
8064 × 6048. Full-frame comparison in a common sRGB RGBA CGContext found the small, localized
numeric difference recorded above; `ui-export-check.json` and `ui-export-difference.json` retain the
measurements, and `compare-ui.swift` is the local comparison helper. Debug-linked harness versus
Release packaged app and automatic-source/encoding paths have not been isolated as causes. This is
not an exact-match pass or an established visible defect.

Codex used Quit Kromora, confirmed the packaged process exited, reopened the same executable, and
opened `01-sky-dust-auto-heal.png`. The Heal inspector showed the persisted one-spot recipe. Codex
then used Settings > Use Default Library > Relaunch. Settings displayed the original default path
with Use Default Library disabled, and the replacement app opened the **56 of 56** personal library.
The disposable writer lease was released normally. Export format/quality are session-only settings
and reset to the original JPEG/95% defaults on relaunch; the configured export-folder default was
unchanged (`Pictures/Kromora Exports`). The app is left open in the normal Library view.

The user has now reviewed all 27 prepared comparisons; those operations need no repetition. The viewer also links the actual signed-app PNG and its native repair crop.
Human review is recorded for all available controlled cases. KRMA-1016 depends on KRMA-1077 for
disposition of the failed foliage Manual Heal case. KRMA-1077 owns the foliage investigation. KRMA-1076 owns reconciliation of the bounded numeric discrepancy; KRMA-1075 owns the library picker issue. No product
source was changed under this qualification ticket.

## Review setup audit

The reviewer reported that most repaired crops looked almost indistinguishable from the clean
reference and questioned the setup. Codex audited the evidence rather than treating this observation
as approval:

- All 27 managed package originals byte-match the corresponding damaged input PNG, and none matches
  its full-frame clean reference. The renderer receives that damaged original and the repair recipe;
  the clean reference is used only for comparison.
- All 27 clean/damaged/repaired crop triples have three distinct decoded sRGB RGBA pixel hashes.
  Every repaired crop differs from both the damaged input and the reference. Each of the nine cases
  also has three distinct repair-mode pixel hashes.
- The browser loads distinct input and repair URLs at native 600 × 400 dimensions. In a live toggle
  check, Show clean reference changed only the left image from damaged to clean; the right repair URL
  stayed fixed. The initial toggle state was restored; no reviewer verdict or note was changed.
- Repaired-versus-clean differences occupy 320–3,958 pixels of each 240,000-pixel crop (0.13–1.65%).
  Sky dust/cloud speck cases differ by at most 2–4 RGB levels out of 255, while textured foliage has
  larger local changes (up to 104/255 for the Clone case). Similar appearance is therefore compatible
  with distinct, actually repaired pixels. These figures establish image identity and difference;
  they are not a quality score or human verdict.

Local details: `viewer-audit.json`, `viewer-routing-audit.json`, `input-provenance-audit.json`, and
`audit-viewer.swift` under `.build/krma1063-evidence/`.

The setup is deliberately favorable: defects are small and artificial, brush regions are generated
from the same known defect geometry, and manual sources are placed 220 source pixels away, outside
the added defect. The tests exercise real camera texture and the production renderer, but they do
not establish freehand placement tolerance, larger-object removal, or performance on naturally
occurring dust/hair. Strong results here should be described as controlled small-defect evidence.
A separate ordinary-editing check with naturally occurring defects and hand-painted masks remains
useful before making broader quality claims. Skin-detail coverage is still missing. The reviewer's
observation was recorded without turning any Not run human verdict into Pass.

## Supplied human review and preserved viewer

The user supplied `KRMA-1063-human-review.json` and asked to keep the HTML comparison tool. Its
candidate hash matches the frozen candidate, all 27 expected case/mode IDs are present exactly once,
and the original bytes are preserved. SHA-256:
`69ef12da3d1ffb8d430d3a5876254d671eae179f2c412d79e29360dd48a955be`.

| Mode | Pass | Fail |
|---|---:|---:|
| Manual Heal | 8 | 1 |
| Auto-source Heal | 9 | 0 |
| Clone | 6 | 3 |
| Total | 23 | 4 |

The four failures and exact reviewer notes are retained as supplied:

| Case / mode | Verdict | Reviewer note | Disposition |
|---|---|---|---|
| 10-cloud-fibre-clone | Fail | this is really minor and likely not worth worrying about | Recorded as a minor reviewer concern; not changed to Pass |
| 12-water-fibre-clone | Fail | Again not worth worrying about | Recorded as a minor reviewer concern; not changed to Pass |
| 06-water-speck-clone | Fail | Not worth worrying about as it is close | Recorded as a minor reviewer concern; not changed to Pass |
| 04-foliage-dust-manual-heal | Fail | Just got a dark branch | Focused investigation filed as KRMA-1077; same case's auto Heal and Clone passed |

The skin value remains exactly **Not run — no representative crop**. This records a coverage omission;
it does not claim skin quality or blanket release approval. The controlled-fixture scope established in the
setup audit still applies. The failure report does not assume that every Clone/reference difference
is a renderer defect; Clone deliberately copies another patch's texture.

The saved HTML is approximately 14 MB and embeds all 46 reviewed PNG crops, candidate metadata, and
human verdicts/notes. Its local-storage access has a fallback for browsers that restrict storage on
local files. It retains working case/mode selection, the clean reference toggle and review download.
Twenty-seven final full-frame PNGs and the representative signed-app PNG were copied beside it using
APFS clones; all 28 copies hash-match the original evidence. The foliage input and saved revision are
also preserved under `repro/04-foliage-dust/` for the focused follow-up.

Archive validation: all 46 embedded PNG payloads byte-match the originals and declare 600 × 400 dimensions;
all full-frame copy hashes match; embedded JavaScript passes `node --check`; the supplied review hash
matches. These checks are recorded in `archive-verification.json`. The in-app browser's security policy
rejected `file:` navigation, so an offline browser preview was not run. That restriction was respected;
the saved file can be opened by the user in a regular browser. No local-file preview success is claimed.

## KRMA-1076 reconciliation

`RetouchExportBoundaryTests` compares `RenderEngine.render` (in-memory, no asset identity) and
`RenderEngine.encode` (streamed to a file, with `PhotoAssetID` and `ExportOptions`) on fresh engines,
then decodes both PNGs in a common context. The test constructs a generated 1200 × 900 image and a new
Heal document; it does not load the persisted document from the disposable package. It requires a
maximum byte delta of 1/255 in each build.

KRMA-1085 separately replayed the package's saved 8064 × 6048 automatic Heal asset and revision-1
document. Six variants each in SwiftPM Debug and Release changed renderer warmth, portable source
identity, `assetID`, and in-memory versus streamed output. Every one of the twelve outputs decoded to
the same sRGB RGB pixels as the archived harness export. The archived signed-app PNG still differs by
2,023 pixels, inclusive bounds x=4646–4707, y=756–815, maximum channel delta 2/255. These results
establish that the tested variants do not change the in-process outputs; they do not isolate effects
specific to the signed Xcode app because that app export was not rerun with the variants. The saved
package remains at revision 1, but the app's export-time request was not captured. The cause remains
unknown. The general observation in `PixelAssertions.swift` that occasional bytes move by 1 does not
establish a 2/255 tolerance for this result. Do not call it numeric noise or publish a cross-build
tolerance; no human visual verdict is established by this pixel comparison.
