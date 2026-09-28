# Kromora Professional Polish Evaluation — 2026-09-22

**Scope:** what would it take for Kromora to play at the level of Lightroom (Classic / CC), Darkroom, and Darktable — judged only on **quality, performance, ease of use, and stability**. Effort is deliberately out of scope.

**Method:** cold read of `README.md`, `docs/ENGINEERING_GUIDE.md`, `docs/APP_ARCHITECTURE.md`, `docs/STORAGE_POLICY.md`, the `EditDocument` / `RenderPipeline` / `RenderEngine` boundary, all inspector views, `LocalMaskModels`, `ExportOptions`, `LibraryFilter` / `LibraryQueryController`, `Histogram`, `CropAdjustments`, `MenuCommands`, `KeyboardShortcuts`, and the Library/Edit surfaces on 2026-09-22. Anything listed as "missing" was not found in code or docs; anything listed as "present" is credited so this reads as a gap analysis, not a rewrite brief.

**One-line verdict:** the foundation is already pro-grade — one value document, one lazy Core Image graph, preview/export parity, Metal presentation, bounded caches, portable package library, and Vision-backed local masks. What separates Kromora from Lightroom-class today is not rendering architecture but **photographer workflow completeness**: retouch, range masks, presets/history/versions, DAM depth, import/export control, proofing/viewing aids, and trust surfaces (backup, recovery, diagnostics).

---

## 1. Where Kromora is already competitive

Credit where due — these do not need to be built, only preserved:

- **Non-destructive value document** (`EditDocument` v6: RAW develop, Light, Color, Effects, crop, rotation, LUT, ordered local layers, Auto provenance). Identity-neutral, `Codable`/`Sendable`/`Equatable`.
- **One graph, multiple qualities.** `RenderPipeline` + `RenderEngine` actor isolation, interactive/preview/full scales, deterministic stage order. Preview and export cannot drift — the same property Lightroom sells as "what you see is what you export."
- **RAW via `CIRAWFilter`** with probed per-file controls, neutral-from-file defaults, highlight recovery / EDR / gamut mapping where the decoder supports them.
- **Local masking done right for v1:** brush/erase, linear, radial, and Vision semantic (foreground / background / subject / person / face) with add / subtract / intersect / replace, invert, solo, per-layer amount, and one pipeline driving preview, overlay, histogram, comparison, copy/paste, and full-res export.
- **Content-aware Auto** with candidate evaluation through the real renderer, guardrails, bounded regional layers, provenance, and no-op repeats.
- **Library culling basics:** virtualized mosaic, async thumbnails, picks/rejects, 0–5 stars, combined filters, multi-select, filmstrip, keyboard-first culling (`P/X/U/0–5/arrows`).
- **Comparison model** (single + side-by-side, hold-`Space` baseline, sticky presentation) and pannable/zoomable canvas with Fit/Fill.
- **Looks system:** `.cube` parsing, starter pack with licensed provenance, folder watch, stable references, derive-from-JPG with report and charts.
- **Export correctness:** full-res from source, TIFF/JPEG/PNG/HEIF, long-edge sizing, working-space + bit-depth + alpha validation, camera vs. location metadata split (GPS excluded by default), collision-safe naming, Export All that continues past failures.
- **Portable `.kromoralibrary` package** with manifest/membership shards, checksummed identities, embedded Look bytes, XMP sidecars, read-only validation (`criticalFailures` vs. rebuildable gaps), backup/restore, trash, and termination-flush persistence.
- **Observability and test discipline:** signposts, bounded telemetry, input→presentation latency separation, deterministic + render/UI + opt-in RAW/benchmark lanes.

None of the recommendations below should break these invariants.

---

## 2. Develop & image quality — the core edit must match pixel-for-pixel trust

### 2.1 White balance and tone fundamentals
- **White-balance eyedropper (click-neutral).** Sliders exist (2000–11000 K + tint); pros expect click-to-neutralize with loupe + averaged sample, plus `As Shot / Auto / Daylight / Cloudy / Shade / Tungsten / Fluorescent / Flash / Custom` presets. Ships in every competitor.
- **Per-channel tone curves.** Today: one master RGB curve (`LightToneCurve`). Add R/G/B channel curves + parametric (Highlights/Lights/Darks/Shadows with split controls) + point-curve import/export. Black-and-white conversion quality depends on this.
- **Dedicated B&W / monochrome mixer.** The 8-channel HSL mixer exists but there is no B&W panel (per-channel gray conversion with auto-mix, grain coupling, filter presets). Darktable's monochrome and Lightroom's B&W panel are reference points.
- **Color Calibration panel** (shadow tint, R/G/B primaries hue/sat). This is the "secret sauce" panel in Lightroom for skin and landscape work; nothing equivalent exists today.
- **Highlight/shadow clipping overlays + histogram clipping badges.** Histogram exists (RGB/Luma/R/G/B) but there are no clipping indicators, no `J`-style overlay, no per-channel numeric clip counts, no click-to-jump exposure. Without this, EDR/highlight-recovery controls are flying blind.
- **RGB / Lab readout under cursor.** No eyedropper readout (pre/post values, 0–100 + 8-bit + Lab) was found. Essential for product/skin work and for trusting Auto.

### 2.2 Detail: sharpening, noise, and texture
- **Sharpening with Masking / Radius / Detail.** Develop exposes `sharpnessAmount / contrastAmount / detailAmount`, but there is no radius, masking (edge-restricted sharpening with Alt-preview), or per-image auto. Lightroom's masking slider alone is a headline feature.
- **Luminance vs. color noise split with detail/contrast retention.** Amounts exist (`luminanceNoiseReductionAmount`, `colorNoiseReductionAmount`); pros expect detail/contrast smoothness + single-pixel color-noise visualization.
- **AI / high-ISO denoise tier.** CIRAWFilter NR is the floor. A "Denoise (Raw details)" strength/preview step is now table stakes in Lightroom; Darktable's profiled denoise sets the open-source bar.
- **Output sharpening on export** (screen/print/matte/glossy × Low/Standard/High). Currently export has no sharpening stage — prints and small JPEGs will look soft next to Lightroom output.
- **Moiré brush + local sharpen/NR.** Moiré is global-only; local layers cannot touch sharpness, NR, moiré, or texture-adjacent detail. Every competitor allows local sharpness/NR.

### 2.3 Optics and geometry
- **Lens profile correction (auto + manual).** Today: one `lensCorrectionEnabled` boolean. Missing: automatic body+lens profile lookup, distortion slider, vignetting (lens) slider separate from creative vignette, chromatic aberration + defringe (eyedropper + purple/green hue controls).
- **Upright / auto geometry.** Crop has straighten angle, flips, vertical/horizontal perspective, and aspect presets — good bones. Missing: `Auto / Level / Vertical / Full` upright, guided (draw-two-lines) upright, aspect + scale + offset + rotate-fine after upright, grid + rule-of-thirds + golden-ratio + diagonal overlays during geometry.
- **Straighten-by-drag.** No draw-a-horizon-line tool was found; angle is numeric only.
- **Boundary warp / constrain-crop behavior.** After upright/rotate, pros expect warp-to-fill vs. constrain toggle. Neither exists.
- **Fisheye / manual distortion + vignette lens model** for adapted and vintage glass.

### 2.4 Color science depth
- **Camera profiles / DCP support.** No camera-matching / Adobe Standard / Camera Faithful / custom DCP selection. CIRAWFilter defaults are correct but "Canon look" shooters will feel homeless.
- **Working-space breadth + soft proofing.** `WorkingSpace` is sRGB + Display P3 only. Add Adobe RGB, ProPhoto RGB, Rec. 2020; add soft-proof toggle with intent (perceptual/relative), simulate-paper, gamut warning, and out-of-gamut % readout. Without proofing, print users cannot trust color.
- **HDR edit/display path.** `extendedDynamicRangeAmount` exists in Develop but there is no HDR canvas handling, HDR histogram scale, or HDR export (gain-map / ISO 21496-1) story. Lightroom now edits and exports HDR; this will age fast.

---

## 3. Retouch — the single biggest functional hole

There is **no spot removal, healing, clone, red-eye, or dust-visualization tool** anywhere in the document, pipeline, or masking UI. This alone disqualifies Kromora from "Lightroom-level" for wedding, portrait, landscape, and archival work.

What "done" looks like:
- Spot heal (content-aware), clone stamp with source-pin + offset nudge, feather/opacity/size per spot, visualize-spots (high-contrast dust finder), dust-grid navigation (jump to next spot at 1:1).
- Red-eye / pet-eye with pupil finder + darken + pupil-size controls.
- Sensor-dust batch behavior: copy/paste spots across frames from the same body (wedding second-shooter workflow).
- Non-destructive spot list per photo (rename, hide/show each, opacity), rendered after geometry and before creative grain so spots track the final frame — same ordering discipline the pipeline already uses for vignette/grain.

---

## 4. Local editing & masking — from very good to best-in-class

The mask *compositor* is ahead of most 1.0 editors. The *selector* and *adjustment* breadth are where Lightroom pulls away.

### 4.1 Missing selectors (highest value first)
- **Luminance range mask** (range + smoothness + invert, with interactive histogram picker).
- **Color range mask** (eyedropper + falloff, single + multi-sample, refine).
- **Depth range mask** (where depth data exists; graceful absence elsewhere).
- **Sky / background auto-select refinement** (one-click sky with refine-edge; subject-select already exists via Vision — promote it to one-click Select Subject / Select Sky buttons, not a component users must assemble).
- **Object-select brush** (lasso/rectangle → Vision segmentation) alongside the paint brush.
- **People masking sub-targets** (skin / eyes / iris / teeth / lips / hair / clothing) — Lightroom's people-masking is the portrait-retouch bar.
- **Edge-aware brush options:** Auto Mask (color/containment edge detection), feather per stroke, flow vs. density separation in UI copy, size/ feather / flow quick-adjust (`[`/`]` exists for radius — add feather/flow, scroll-resize, right-drag-resize).

### 4.2 Missing local adjustments
`LocalAdjustments` covers 13 fields (exposure, contrast, Hi/Sh, whites/blacks, temp/tint, sat/vib, texture/clarity/dehaze). Global has far more. Add locally:
- Tone curve (at least region curve), HSL per-channel, color grading wheels, sharpness/NR/moiré, vignette-local dodge/burn, grain-local, LUT-intensity-local, B&W-mix-local.
- Per-layer **color pick + opacity + blend intent** naming; Lightroom layers show which sliders moved — Kromora layers should badge non-identity controls.
- **Intersect/Subtract with range masks** (e.g., Subject ∩ Luminance) — the compositor supports the ops; the UI must let a range be a component.

### 4.3 Mask visualization and editing ergonomics
- Overlay color choices (red/green/white/black), marching-ants edge, B&W mask view, before/after per-layer solo already exists — add **hold-to-preview-layer** and per-component visibility.
- Invert/duplicate/rename/drag-reorder polish, per-component feather + density sliders surfaced next to the canvas (not buried), brush-stroke smoothing + stabilize toggle for trackpads.
- Mask overlay at full-res export proof (mask-aware histogram already exists — extend to numeric masked-pixel % + clipped-pixel %).

---

## 5. Presets, history, versions — the non-destructive memory pros pay for

This cluster is entirely absent and is the second-biggest gap after retouch:

- **User edit presets** (not Looks): create from current settings, subset checkboxes (reuse the selective-copy sheet taxonomy), amount slider on apply, favorite/star, folders/groups, import/export `.xmp`-compatible preset files, right-click update-with-current, auto-apply on import by camera/ISO rule.
- **Preset browser + amount.** The Look browser proves the UI pattern; presets need the same hover-preview + before/after wipe.
- **History panel** (step list: Import → Auto → each slider commit → crop → mask edits; click any step to preview, fork-from-here, clear-above, copy step settings, snapshot-from-step). Undo depth of 100 exists but is invisible and linear-only.
- **Snapshots** (named frozen states inside one photo) and **Virtual Copies / Versions** (multiple named interpretations of one source with independent history, pick/reject per version, stack/expand in grid). Wedding culling without versions is painful.
- **Auto-sync / Sync settings** across selected grid items (live mirror while sliders move + one-shot sync dialog with the same subset taxonomy as presets). Copy/paste exists (`⌘C/⌘V`, selective sheet) but is one-at-a-time and modal — pros sync hundreds.
- **Match Total Exposure** (meter + ISO-aware exposure alignment across a selection).
- **Reset granularity UI:** reset exists per control/section/photo — add reset-to-import, reset-crop-only, reset-masks-only in one menu.

---

## 6. Library / DAM — from culler to catalog

Culling is pleasant; cataloging is thin.

### 6.1 Organization
- **Collections (manual) + Smart Collections (rule-based)** with badges, nesting, and sync-to-export. Today there are no containers beyond the whole package window.
- **Folders view** (even package-internal date/camera folders) for shoot-day triage. The package deliberately retired referenced-folder browsing — replace it with virtual folders by date/camera/look, not a return to bookmarks.
- **Color labels** (Red/Yellow/Green/Blue/Purple + custom sets, filterable, Lightroom-compatible label text in XMP).
- **Stacks** (burst/HDR/pano/version stacks with pick-as-cover, expand/collapse, auto-stack by capture time).
- **Keywords:** hierarchical keyword list, apply/remove on multi-select, synonyms, keyword suggestions from Vision analysis, filterable + export-to-XMP (`dc:subject`/`lr:hierarchicalSubject`).
- **People / Faces:** Vision face detection → name, confirm, cluster; filter by person. `SemanticTarget.face/person` exists in masks — promote detection to DAM.
- **Ratings/flags depth:** add dim/reject-auto-advance options, compare-mode flag propagation to both panes, spray-can painter (Lightroom's painter) for rating/label/keyword spray across the grid.

### 6.2 Finding
- `LibraryQuery` already supports `searchText` + rich sort keys (name, capture date, rating, flag, label, camera, lens, revision) — but the Library surface only exposes flag + rating pickers. Expose: **search field (filename, camera, lens, keyword, caption), sort menu, and filter bar** (edited / unedited, has-look, has-mask, has-spots, cropped, Auto-applied, missing-original, GPS-present, file-type, orientation, ISO/aperture/focal buckets, date histogram).
- **Metadata browser pills** (camera × lens × date drill-down) and saved-filter presets.
- **Duplicate detection** (import-time + library-time, perceptual-near-dupe grouping for bursts).

### 6.3 Metadata editing (all missing, all expected)
- Title, caption, copyright, creator, location (manual + reverse-geocode affordance), star/flag/label already exist — but nothing writes back. Make Info inspector fields editable with multi-select batch edit, undoable, persisted to sidecar + package, exported per policy.
- EXIF is read-only display today. Add batch capture-time shift, GPS strip/offset per export (policy exists — add per-photo override), and copy-metadata-across-photos.

---

## 7. Import — from file opener to ingest station

Import works (folder, single, Photos ≤50, removable media, drag/drop). A pro ingest station adds:

- **Import dialog with preview grid:** thumbnail grid with check-all/none, loupe, sort, already-imported dimming (don't-import-suspected-duplicates), destination summary, and Build Previews selector (Minimal/Standard/1:1/Smart).
- **Copy organization:** organize-by-date (`YYYY/MM/DD` + custom tokens), rename template (`{date}_{seq}_{camera}_{orig}` with live preview), second-copy backup to another volume on import, copy-as-DNG option.
- **Apply on import:** develop preset + metadata preset + keywords + label + auto-advance flag defaults per import source.
- **Larger Photos imports** (raise or page past the 50 cap), import-from-camera (PTP/tethered ingest) progress with bad-file quarantine that stays browsable.
- **Tethered capture** (Canon/Nikon/Sony via native capture APIs): live ingest folder, overlay, auto-apply preset, shutter-from-app. Darktable and Lightroom Classic treat this as core studio functionality.
- **Background ingest:** import while culling/exporting with pause/resume, per-file status icons, and a finish report that matches the existing partial-failure pattern.

---

## 8. Export, output, and sharing — where trust is signed

Export is correct but narrow.

- **Export presets + batch queue:** named presets (JPEG-full, JPEG-web-2048, TIFF-16-ProPhoto, PNG-client…), multi-preset fan-out from one selection, background queue with per-item progress/retry/cancel/reveal-in-Finder, history of recent exports.
- **Sizing depth:** long-edge exists — add short-edge, width×height, megapixels, percentage, don't-enlarge toggle, resolution (ppi) field, custom crop-to-fit per preset.
- **Sharpen-for + noise handling on export** (see §2.2), JPEG quality with estimated file size, quality-vs-size live estimate, limit-to-KB (iterative quality) for delivery portals.
- **Color-space breadth:** add Adobe RGB + ProPhoto + Rec. 2020 targets (working space is sRGB/P3 only today); embed-profile vs. convert toggle; proof-to-preset linkage.
- **Naming templates:** `{orig}_{look}_{seq}_{date}_{width}w` token editor with collision preview — beyond `sourceName` / `sourceNameWithLook`.
- **Watermarking:** text + logo (SVG/PNG), position/anchor/opacity/scale, per-preset on/off.
- **Destinations:** export-to-folder exists + Photos delivery option — add export-to-original-folder, open-in-external-editor round-trip (TIFF/PSD handoff with stack-with-original), Share sheet, Mail/Messages, AirDrop batch, publish services (SmugMug/Flickr/500px-style plugin seam even if Apple-only).
- **Print module:** layout, margins, cell size, contact sheet, print sharpening, ICC/paper profile selection, soft-proof coupling. No competitor at this tier ships without print.
- **Slideshow / web gallery export:** fullscreen slideshow with theme + music hook, static-HTML gallery export for client proofing.
- **Original + settings export** (RAW + sidecar bundle) for handoff and archive.

---

## 9. Viewing, comparison, and proofing ergonomics

- **Split before/after in one canvas** (left/right, top/bottom, draggable divider) alongside the existing two-pane side-by-side.
- **Reference view** (any two photos side by side, zoom-locked) for match-grade work across frames.
- **Zoom affordances:** 1:1 / 2:1 / Fit shortcuts with pixel readout, navigator thumbnail with viewport box, focus-peaking-at-100% toggle for culling sharpness.
- **Survey / compare-grid (N-select)** and lights-out fullscreen (`L`/`F` idioms) for client review.
- **Clipping, focus, and AF-point overlays:** clipping (see §2.1), depth/face-box overlay toggle from analysis evidence, straighten grid + aspect-safe guides in crop (thirds, diagonal, golden spiral, center-cross, aspect-ratio guides).
- **Histogram depth:** clipped-channel tint on the chart, numeric R/G/B/Lab under cursor, waveform + parade + vectorscope modes for video-adjacent and studio shooters, histogram source toggle (preview vs. full-res probe).
- **Second-display / fullscreen preview** (`Window ▸ Secondary Display`) for studio culling.

---

## 10. Performance and scale — keep the Metal promise at 100k frames

The bounded-cache + Metal-surface + windowed-query architecture is the right shape. To hold it under pro catalogs:

- **Smart / standard preview pyramid:** prebuilt 2560px edit-aware previews for instant culling + offline editing; background builder with progress, pause, quality selector, and storage accounting. Full RAW develop on every grid scroll will not survive 50k-frame weddings.
- **Thumbnail throughput:** sustained 60fps grid scroll on 45–100 MP RAWs, visible-neighborhood prioritization already exists — add prefetch-ahead + burst-aware batch decode + RAW-embedded-JPEG fast path with develop-badge ("preview approximate until developed").
- **Slider-to-photon latency budget:** publish and defend an interaction budget (e.g., p50/p95 input→presented-frame on reference hardware), keep the interactive pixel cap adaptive, and surface a "degraded-preview" badge instead of silently lagging — the telemetry to prove this already exists (`LiveEditTelemetry`).
- **Background work transparency:** one activity center (import / preview-build / analysis / export / mask-cache) with per-job progress, cancel, pause, and error surfacing — instead of scattered status strings.
- **Cache controls:** user-visible cache sizes (preview/mask/analysis), purge actions, offline-volume behavior, low-disk warnings before a 2,000-frame export fills the drive.
- **Large-catalog scale:** 100k+ asset windowing already started (`isPortableWindowed`, shard pagination) — add virtualized sort/filter without full re-projection, background reindex with "results updating" affordance, and cold-open time budget (dock → first thumbnail grid).
- **Export throughput:** multi-image concurrency tuned to CPU/GPU, Metal-vs-CPU fallback per format, ETA + throughput (MP/s) in the queue, thermal-throttle grace (slow down, don't fail).
- **Memory-pressure drills:** keep the eviction paths, but add a user-facing "performance mode" (reduced preview resolution while on battery / low memory) and persist it per device.

---

## 11. Ease of use — the difference between powerful and professional

- **First-run experience:** welcome → sample library (licensed RAWs + edits to play with) → import-your-first-shoot → 60-second tour of Library/Edit/Export. Today a cold open with no package is a blank window.
- **Empty states with actions:** every empty surface (no library, no selection, no results, no Looks, export-done) should carry its next action as a button, not a sentence.
- **Guided edits / learn panel:** before/after recipe cards ("Fix backlight," "Save the highlights," "Creamy skin") that apply stepped, undoable, annotated edits reusing the existing Auto/preview path — Darkroom's onboarding killer feature.
- **Contextual help where sliders live:** one-line "what this does + when to reach for it" popovers per section, clipping-aware hints ("highlights clipped — try Whites −40 before Exposure"), and a `?`-shortcut cheat sheet in-app (shortcuts exist but are undiscoverable beyond menus).
- **Workspace customization:** hide/reorder inspector sections, solo-mode, favorites bar of pinned sliders, collapsible filmstrip sizes, saved workspace layouts (Culling / Color / Retouch / Print).
- **Command palette + searchable menus** (`⌘K`: "apply preset X," "export as…," "upright auto," "select sky"…). Non-negotiable once commands exceed ~50.
- **Crop UX polish:** double-click-to-commit, `Enter`/`Esc` already implied — add crop-preset quick keys, invert-aspect key (`X` idiom), lock-to-aspect drag handles with pixel readout, straighten-line tool (§2.3).
- **Brush UX polish:** live size/feather cursor ring, pressure-curve settings for tablets, Apple Pencil double-tap to switch brush/erase, stabilize toggle, last-stroke nudge (`↑/↓` nudge exists for masks — extend to spot pins).
- **Undo confidence:** visible dirty indicator, per-section "edited" dots (some exist as resettable labels — make them universal), jump-to-last-edit command after navigation.
- **Accessibility and locale:** full VoiceOver coverage of grid/canvas/sliders with value announcements, high-contrast overlay colors, reduced-motion respect for transitions, Dynamic Type in panels, full string localization (`.strings` + per-locale screenshots), right-to-left layout audit.
- **Haptics and trackpad fluency:** pinch-to-zoom + two-finger-pan inertia already implied by canvas — add rotate-gesture straighten, pressure scrub on sliders, Touch Bar / Control Center widget parity where macOS offers it.

---

## 12. Stability, data safety, and trust — the pro contract

Pros entrust irreplaceable files. Kromora's validation + trash + termination-flush is a strong start; close the loop:

- **Versioned automatic backups:** scheduled package snapshots (hourly/daily, keep-N), backup-on-upgrade, one-click restore with dry-run diff ("12,304 assets, 3,102 revisions, 0 critical failures"), off-volume backup target picker, Time-Machine-friendly layout note.
- **Crash / power-loss recovery:** relaunch offers "restored N unsaved edits from journal" with per-photo review; never silently drop the abandoned-snapshot path that shutdown currently discards.
- **Health dashboard:** package verification on open + on demand, background scrub with badge (green/amber/red), quarantine-and-continue for corrupt originals/revisions (per-record reporting exists — surface it as a repairable list, not a log line), orphan-sidecar and missing-original hunters with relink suggestions.
- **Storage clarity:** what lives where (package vs. Application Support projection vs. device caches vs. Pictures exports) is documented in `STORAGE_POLICY.md` — mirror it in-app as a Settings pane with sizes, open-in-Finder buttons, move-library, and low-space guard before large imports/exports.
- **Diagnostics bundle:** one-click support export (sanitized log + package validation summary + hardware/GPU + render-pipeline version + recent telemetry, GPS/filenames redacted) for bug reports.
- **Safe updates:** staged migration with rollback snapshot before any schema bump (`currentVersion = 6` has no rollback story today), newer-version refusal message with "export sidecars first" guidance, release-notes surface in the updater sheet.
- **Privacy posture as a feature:** keep the camera-vs-location split, add per-photo location override, faces-recognition opt-in with on-device disclosure, network-off guarantee page (zero third-party deps + no analytics is a marketable trust asset — say so in-app).

---

## 13. Interop and ecosystem — avoid the walled garden

- **XMP round-trip with Lightroom/Bridge:** today XMP carries an opaque base64 Kromora blob (lossless for Kromora, opaque to everyone else). Add standard-mapped fields (exposure, white balance, crop, rating/label, keywords, IPTC) so ratings and basic develops survive a Lightroom round-trip; keep the blob as the full-fidelity extension.
- **Sidecar DNG + original fidelity:** export-original-with-settings bundle, checksum-verified copy, read-only source guarantee surfaced in UI ("originals are never modified" badge).
- **External-editor round-trip:** Edit in Photoshop / Pixelmator / Affinity (TIFF/PSD handoff, stack-with-original, re-import auto-stacked).
- **Drag-out / Share / Shortcuts:** drag full-res out of the grid, macOS Share sheet, Apple Shortcuts actions (import, apply preset, export preset), Services menu, droplet export.
- **Camera/lens database freshness:** show embedded-profile vs. built-in mapping version; flag unrecognized bodies with "basic support" badge instead of silent defaults.
- **Video-stills parity (explicit decision):** Lightroom edits video thumbnails/trim; Darktable ignores video. Either support motion-JPEG/HEVC frame grading or declare stills-only in the README and hide video files at import with an explicar — silent inclusion in the grid is the worst option.

---

## 14. Competitive parity snapshot (where the gap is widest)

| Capability | Lightroom Classic/CC | Darkroom | Darktable | Kromora today |
|---|---|---|---|---|
| Non-destructive parametric edits | ✅ | ✅ | ✅ | ✅ strong |
| RAW develop breadth | ✅✅ deep + profiles | ✅ Apple RAW | ✅✅ deep + modules | ✅ good, decoder-bound |
| Per-channel + parametric curves | ✅ | ✅ | ✅ | ❌ master-only |
| Calibration / B&W mixer | ✅ | partial | ✅ | ❌ |
| Lens profiles + CA/defringe + upright | ✅ | partial | ✅ | ❌ boolean + manual perspective only |
| Spot heal / clone / red-eye | ✅ | ✅ | ✅ | ❌ **absent** |
| Luminance / color / depth range masks | ✅ | ✅ partial | ✅ | ❌ **absent** |
| People/sky one-click masks | ✅ | ✅ | partial | partial (Vision components, no one-click) |
| Local sharpness/NR/curve/HSL | ✅ | partial | ✅ | ❌ 13-field subset |
| User presets + amount + sync/auto-sync | ✅ | ✅ | ✅ styles | ❌ Looks-only |
| History panel + snapshots + virtual copies | ✅ | ✅ versions | ✅ snapshots/duplicates | ❌ undo-only, invisible |
| Keywording / labels / faces / smart collections | ✅ | ✅ partial | ✅ | ❌ flags+stars only |
| Metadata editing + IPTC/XMP round-trip | ✅ | partial | ✅ | ❌ read-only + opaque blob |
| Import dialog + rename + backup + presets | ✅ | n/a (Photos-first) | ✅ | ❌ direct ingest only |
| Export presets/queue/sharpen/watermark/print | ✅ | ✅ partial | ✅ | partial (correct, narrow) |
| Soft proof + HDR path | ✅ | partial | ✅ partial | ❌ |
| Clipping + readout + scopes | ✅ | ✅ | ✅ | ❌ chart only |
| Tethered capture | ✅ Classic | ❌ | ✅ | ❌ |
| Performance at 100k+ (smart previews) | ✅ | ✅ | partial | partial (windowed query, no smart previews) |

**Read the table as a roadmap:** rows with ❌ are exactly the "play at their level" list. The top three rows to flip first on photographer value are **retouch (§3)**, **presets/history/versions (§5)**, and **range masks (§4.1)** — not because they are cheap, but because every wedding/portrait/landscape pro hits them on day one.

---

## 15. Suggested "polish" punchlist (grouped by photographer pain, not cost)

**Can't call it pro without these:**
1. Spot heal/clone/red-eye + visualize spots. — [KRMA-599](../.dg/issues/KRMA-599.md)
2. User presets + preset browser + sync/auto-sync + history panel + snapshots + virtual copies. — [KRMA-603](../.dg/issues/KRMA-603.md), [KRMA-604](../.dg/issues/KRMA-604.md), [KRMA-605](../.dg/issues/KRMA-605.md)
3. Luminance + color range masks; one-click Subject/Sky/People targets. — [KRMA-600](../.dg/issues/KRMA-600.md), [KRMA-601](../.dg/issues/KRMA-601.md); Sky selection is also tracked in [KRMA-580](../.dg/issues/KRMA-580.md), [KRMA-583](../.dg/issues/KRMA-583.md), and [KRMA-584](../.dg/issues/KRMA-584.md)
4. WB eyedropper + preset menu; per-channel + parametric curves; clipping overlays + RGB/Lab readout; camera profiles/DCP selection. — [KRMA-594](../.dg/issues/KRMA-594.md), [KRMA-595](../.dg/issues/KRMA-595.md), [KRMA-597](../.dg/issues/KRMA-597.md), [KRMA-629](../.dg/issues/KRMA-629.md)
5. Lens auto-profiles + CA/defringe; Upright auto/level/guided. — [KRMA-627](../.dg/issues/KRMA-627.md), [KRMA-628](../.dg/issues/KRMA-628.md)
6. Sharpening radius/masking/detail + output sharpening; B&W mixer; calibration panel. — [KRMA-598](../.dg/issues/KRMA-598.md), [KRMA-596](../.dg/issues/KRMA-596.md), [KRMA-602](../.dg/issues/KRMA-602.md)
7. Export presets + queue + naming tokens + sharpen-for + watermark + AdobeRGB/ProPhoto targets + print. — [KRMA-612](../.dg/issues/KRMA-612.md), [KRMA-613](../.dg/issues/KRMA-613.md), [KRMA-614](../.dg/issues/KRMA-614.md), [KRMA-625](../.dg/issues/KRMA-625.md)
8. Keywords/labels/faces + collections/smart collections + stacks + editable IPTC + XMP round-trip. — [KRMA-606](../.dg/issues/KRMA-606.md), [KRMA-607](../.dg/issues/KRMA-607.md), [KRMA-608](../.dg/issues/KRMA-608.md), [KRMA-609](../.dg/issues/KRMA-609.md)
9. Import dialog with previews/dupe-guard/rename/date-folders/backup-copy/apply-on-import; tethered capture. — [KRMA-610](../.dg/issues/KRMA-610.md), [KRMA-611](../.dg/issues/KRMA-611.md)
10. Backup/versioning + crash recovery + health dashboard + diagnostics bundle + rollback-safe updates. — [KRMA-622](../.dg/issues/KRMA-622.md), [KRMA-623](../.dg/issues/KRMA-623.md), [KRMA-624](../.dg/issues/KRMA-624.md)

**Turns powerful into pleasant:**
11. Reference view, split before/after divider, survey grid, fullscreen/lights-out, second display, navigator, 1:1/2:1 loupe. — [KRMA-615](../.dg/issues/KRMA-615.md), [KRMA-616](../.dg/issues/KRMA-616.md)
12. Histogram scopes (waveform/parade/vectorscope), proof preview, HDR story, overlay guides (thirds/golden/diagonal/safe). — [KRMA-597](../.dg/issues/KRMA-597.md), [KRMA-613](../.dg/issues/KRMA-613.md), [KRMA-616](../.dg/issues/KRMA-616.md)
13. Brush cursor ring + auto-mask + flow controls + Pencil support; crop commit keys + invert-aspect key + straighten-line. — [KRMA-601](../.dg/issues/KRMA-601.md), [KRMA-602](../.dg/issues/KRMA-602.md), [KRMA-628](../.dg/issues/KRMA-628.md), [KRMA-630](../.dg/issues/KRMA-630.md)
14. Smart-preview pyramid + activity center + cache settings + cold-open budget. — [KRMA-617](../.dg/issues/KRMA-617.md), [KRMA-618](../.dg/issues/KRMA-618.md)
15. Command palette, saved workspaces, guided-edit cards, first-run sample library, in-app shortcut sheet. — [KRMA-619](../.dg/issues/KRMA-619.md), [KRMA-620](../.dg/issues/KRMA-620.md)
16. External-editor round-trip, drag-out/Share/Shortcuts actions, standard-mapped XMP, original+settings bundle, camera/lens profile freshness, and explicit video support policy. — [KRMA-609](../.dg/issues/KRMA-609.md), [KRMA-625](../.dg/issues/KRMA-625.md), [KRMA-626](../.dg/issues/KRMA-626.md)
17. VoiceOver/Dynamic Type/reduced-motion/localization pass; privacy page (on-device, no analytics). — [KRMA-621](../.dg/issues/KRMA-621.md)

The linked tickets are backlog candidates derived from this evaluation, not an implementation sequence. Related recommendations are grouped where one ticket owns the shared workflow. Existing Sky-selection tickets are linked under item 3.

---

*End of evaluation. No implementation, sequencing, or cost judgments were made — that belongs to planning. The next artifact after this should be product decisions (which rows are in-scope for Kromora's identity), not task breakdowns.*

---

## Preserved deferred proposals (removed from active backlog)

The following proposals were removed from the active DispatchGraph backlog during MVP scope review. Their original issue bodies and acceptance criteria are retained here so any proposal can be restored as a new issue later. Issue identifiers are historical references; do not treat this section as a committed roadmap.

### KRMA-596 — Add monochrome mixing and camera color calibration

**Original status:** `backlog`. **Original issue:** `KRMA-596`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-596
title: Add monochrome mixing and camera color calibration
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:26.294Z
updated: 2026-09-26T13:56:42.761Z
blockers: []
order: fffffff0
board: product
---

## Objective

Give photographers control over black-and-white channel mixing and camera-oriented shadow/primary color calibration.

## Context

The Color inspector has an HSL mixer, but the evaluation found no dedicated monochrome mixer or camera calibration panel.

Derived from §2.1 White balance and tone fundamentals; §2.4 Color science depth in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a monochrome conversion with per-color contribution controls, an Auto Mix action, and useful filter presets.
- [ ] Provide shadow tint and red, green, and blue primary hue/saturation controls.
- [ ] Persist these settings non-destructively and verify they run in the shared render pipeline.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-601 — Expand semantic and edge-aware mask selection

**Original status:** `backlog`. **Original issue:** `KRMA-601`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-601
title: Expand semantic and edge-aware mask selection
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:29.727Z
updated: 2026-09-26T13:56:42.940Z
blockers: []
order: jpppppp6
board: product
---

## Objective

Make semantic and brush-based mask selection easier to create and refine.

## Context

Existing Vision mask components require assembly in the masking workflow. Sky selection is tracked separately in KRMA-580/583/584.

Derived from §4.1 Missing selectors; §4.3 Mask visualization and editing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Offer one-click Select Subject and People sub-targets such as skin, eyes, hair, teeth, and clothing where Vision supports them.
- [ ] Add a lasso/rectangle object-selection brush backed by segmentation and edge-aware Auto Mask options.
- [ ] Separate and explain brush feather and flow controls, with practical quick-adjust gestures.
- [ ] Preserve graceful fallback messaging when the image or system cannot provide a requested semantic target.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-602 — Broaden local adjustment controls and mask editing

**Original status:** `backlog`. **Original issue:** `KRMA-602`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-602
title: Broaden local adjustment controls and mask editing
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:30.412Z
updated: 2026-09-26T13:56:42.975Z
blockers: []
order: kkkkkkk0
board: product
---

## Objective

Bring local editing closer to global adjustment breadth and make mask changes easier to inspect.

## Context

LocalAdjustments currently cover a smaller field set than global editing. Existing masks and compositor operations should remain the foundation.

Derived from §4.2 Missing local adjustments; §4.3 Mask visualization and editing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add local tone curve, HSL, color grading, sharpening/noise/moiré, vignette, grain, LUT intensity, and monochrome mixing as supported mask adjustments.
- [ ] Show which non-neutral controls changed on each layer and provide layer color, opacity, and blend intent.
- [ ] Add hold-to-preview-layer and per-component visibility, plus visible feather/density controls.
- [ ] Keep adjustment-only edits efficient and consistent across preview, histogram, comparison, and full-resolution export.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-603 — Add user edit presets and an edit preset browser

**Original status:** `backlog`. **Original issue:** `KRMA-603`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-603
title: Add user edit presets and an edit preset browser
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:31.086Z
updated: 2026-09-26T13:56:43.011Z
blockers: []
order: lfffffeu
board: product
---

## Objective

Let photographers save reusable edit settings separately from Looks and apply them with control over what changes.

## Context

The current Looks system handles LUTs; the evaluation identified reusable edit presets as a separate missing workflow.

Derived from §5 Presets, history, versions in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create presets from the current edit with category/subset selection, favorites, and folders.
- [ ] Browse presets with preview and before/after comparison, and control application amount where meaningful.
- [ ] Import/export documented XMP-compatible preset files and update a preset from the current edit.
- [ ] Support optional rule-based application by camera or ISO without overriding settings excluded by the preset.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-605 — Add multi-photo sync and match-total-exposure tools

**Original status:** `backlog`. **Original issue:** `KRMA-605`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-605
title: Add multi-photo sync and match-total-exposure tools
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:32.469Z
updated: 2026-09-26T13:56:43.081Z
blockers: []
order: n555554i
board: product
---

## Objective

Apply and synchronize edits across selected photos without repeating one-photo-at-a-time copy/paste.

## Context

Selective copy exists, but the evaluation found no multi-photo live sync or exposure matching.

Derived from §5 Presets, history, versions in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a one-shot sync dialog using the same category-selection model as presets/selective copy.
- [ ] Support opt-in live Auto Sync while editing a selection, with clear source and target behavior.
- [ ] Match total exposure across selected photos using exposure and available ISO/capture metadata.
- [ ] Add reset-to-import, reset-crop-only, and reset-masks-only actions with undoable results.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-606 — Add collections, virtual folders, stacks, and color labels

**Original status:** `backlog`. **Original issue:** `KRMA-606`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-606
title: Add collections, virtual folders, stacks, and color labels
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:33.149Z
updated: 2026-09-26T13:56:43.123Z
blockers: []
order: nzzzzzzc
board: product
---

## Objective

Organize a package library into photographer-defined groups and views without restoring fragile folder bookmarks.

## Context

The current library is package-centered with culling basics; this ticket is for organization inside that model, not referenced-folder browsing.

Derived from §6.1 Organization in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Support manual and rule-based Smart Collections, nesting, and visible collection badges.
- [ ] Provide virtual folders based on date, camera, or Look, plus burst/HDR/panorama/version stacks with a selectable cover.
- [ ] Add configurable color labels and label filtering.
- [ ] Persist organization in the portable library and include supported labels in metadata/XMP exchange.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-607 — Add hierarchical keywords and face-based organization

**Original status:** `backlog`. **Original issue:** `KRMA-607`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-607
title: Add hierarchical keywords and face-based organization
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:33.824Z
updated: 2026-09-26T13:56:43.168Z
blockers: []
order: ouuuuuu6
board: product
---

## Objective

Make photos searchable by reusable keywords and confirmed people identities.

## Context

The evaluation notes that Vision face/person concepts exist for masks but are not promoted into catalog organization.

Derived from §6.1 Organization in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create hierarchical keywords with synonyms, multi-select apply/remove, and Vision-based suggestions.
- [ ] Detect faces on device and support name, confirm, and cluster workflows with explicit user control.
- [ ] Filter the library by keywords and people.
- [ ] Persist metadata and export keywords through standard XMP subject fields.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-608 — Expose library search, filters, sorting, and duplicate groups

**Original status:** `backlog`. **Original issue:** `KRMA-608`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-608
title: Expose library search, filters, sorting, and duplicate groups
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:34.498Z
updated: 2026-09-26T13:56:43.206Z
blockers: []
order: ppppppp0
board: product
---

## Objective

Let photographers find images using existing query capabilities and richer catalog facets.

## Context

`LibraryQuery` already includes search text and rich sort keys; the evaluation found the library surface exposes only a subset.

Derived from §6.2 Finding in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Expose search for filename, camera, lens, keyword, and caption, plus a visible sort menu.
- [ ] Add filter facets for edit/look/mask/spot/crop/Auto state, source availability, file type, orientation, and capture settings/date.
- [ ] Provide camera/lens/date metadata drill-down pills and saved-filter presets.
- [ ] Detect exact and likely near duplicates at import or library time and present reviewable groups without deleting originals.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-609 — Make photo metadata editable and map standard XMP fields

**Original status:** `backlog`. **Original issue:** `KRMA-609`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-609
title: Make photo metadata editable and map standard XMP fields
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:35.192Z
updated: 2026-09-26T13:56:43.241Z
blockers: []
order: qkkkkkju
board: product
---

## Objective

Allow metadata edits in the Info inspector and exchange common fields with other photo applications.

## Context

Metadata is currently read-only and XMP stores an opaque Kromora payload; preserve package durability and privacy policy.

Derived from §6.3 Metadata editing; §13 Interop and ecosystem in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Edit title, caption, copyright, creator, and supported location fields, including batch edits with undo.
- [ ] Persist edits through package records and sidecars and apply the documented export-location policy.
- [ ] Map exposure, white balance, crop, rating, labels, keywords, and IPTC fields to standard XMP while retaining the full-fidelity Kromora extension.
- [ ] Add round-trip tests for fields Kromora can represent and define behavior for unsupported external values.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-610 — Build a preview-based import workstation

**Original status:** `backlog`. **Original issue:** `KRMA-610`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-610
title: Build a preview-based import workstation
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:35.866Z
updated: 2026-09-26T13:56:43.276Z
blockers: []
order: rfffffeo
board: product
---

## Objective

Give photographers a reviewable ingest flow with organization, duplicate checks, and defaults before files enter a package.

## Context

Existing import sources remain the entry points. This ticket adds ingest planning and progress while keeping the portable package as library owner.

Derived from §7 Import — from file opener to ingest station in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a preview grid with check-all/none, loupe, sorting, destination summary, and already-imported duplicate hints.
- [ ] Support date-based organization, rename templates with live preview, and optional second-copy backup.
- [ ] Allow apply-on-import edit/metadata presets, keywords, labels, and advance defaults; offer preview-build choices.
- [ ] Support background import with pause/resume, per-file status, quarantine for bad files, and a finish report; remove or page beyond the current Photos batch cap.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-611 — Add tethered camera capture

**Original status:** `backlog`. **Original issue:** `KRMA-611`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-611
title: Add tethered camera capture
type: feature
status: backlog
priority: low
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:36.548Z
updated: 2026-09-26T14:15:06.423Z
blockers: []
order: saaaaa9i
board: product
---

## Objective

Support studio capture into the open package with immediate preview and configurable edit defaults.

## Context

The evaluation lists tethered capture as a studio workflow gap. Camera API support and the initial supported-device scope need an explicit product decision.

Derived from §7 Import — from file opener to ingest station in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Define and implement a supported native camera capture path for selected camera models.
- [ ] Ingest new captures into the active package with per-frame status and recoverable failures.
- [ ] Show live/near-live preview and optionally apply an import preset.
- [ ] Document unsupported cameras and keep normal editing and import responsive during capture.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-612 — Add named export presets and a resilient batch queue

**Original status:** `backlog`. **Original issue:** `KRMA-612`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-612
title: Add named export presets and a resilient batch queue
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:37.227Z
updated: 2026-09-26T13:56:43.346Z
blockers: []
order: t555554c
board: product
---

## Objective

Turn one-off export into a reusable, observable delivery workflow.

## Context

Full-resolution export is already correct; this work expands configuration and queue control without changing preview/export render parity.

Derived from §8 Export, output, and sharing in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Save named export presets and fan one selection out to multiple presets.
- [ ] Queue exports with per-item progress, retry, cancel, reveal, recent history, and continuation after individual failures.
- [ ] Add short-edge, dimensions, megapixel, percentage, resolution, don't-enlarge, and crop-to-fit options.
- [ ] Add filename token templates with collision preview, watermark controls, JPEG size estimates/limits, and output sharpening.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-613 — Add soft proofing, wider output spaces, and an HDR workflow

**Original status:** `backlog`. **Original issue:** `KRMA-613`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-613
title: Add soft proofing, wider output spaces, and an HDR workflow
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:37.913Z
updated: 2026-09-26T13:56:43.381Z
blockers: []
order: tzzzzzz6
board: product
---

## Objective

Let photographers judge output color and dynamic range against their target display or delivery format.

## Context

WorkingSpace currently covers sRGB and Display P3; the evaluation found no soft-proof or end-to-end HDR story.

Derived from §2.4 Color science depth; §8 Export, output, and sharing; §9 Viewing in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Support Adobe RGB and ProPhoto RGB export targets and evaluate Rec. 2020 with profile conversion and embedding controls.
- [ ] Provide a soft-proof toggle with rendering intent, paper simulation, gamut warning, and out-of-gamut feedback.
- [ ] Define HDR canvas, histogram, and export behavior, including a supported gain-map format where feasible.
- [ ] Link proof settings to export presets and preserve existing sRGB/P3 behavior.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-614 — Add print, contact-sheet, slideshow, and web-gallery output

**Original status:** `backlog`. **Original issue:** `KRMA-614`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-614
title: Add print, contact-sheet, slideshow, and web-gallery output
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:38.612Z
updated: 2026-09-26T13:56:43.416Z
blockers: []
order: uuuuuuu0
board: product
---

## Objective

Support client and print delivery directly from selected library photos.

## Context

Print and gallery workflows are absent from current export, which is focused on individual image files.

Derived from §8 Export, output, and sharing in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create print layouts with page/margins/cell controls, contact sheets, print sharpening, and ICC/paper profile selection.
- [ ] Provide a fullscreen slideshow with configurable presentation styling.
- [ ] Export a static client gallery with chosen images and a useful visual theme.
- [ ] Make output options reproducible through saved settings and report partial failures clearly.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-615 — Add split, reference, and survey comparison views

**Original status:** `backlog`. **Original issue:** `KRMA-615`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-615
title: Add split, reference, and survey comparison views
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:39.295Z
updated: 2026-09-26T13:56:43.451Z
blockers: []
order: vpppppou
board: product
---

## Objective

Make frame-to-frame matching and before/after review possible without leaving the editing context.

## Context

The app already has a comparison model and pannable/zoomable canvas; extend rather than replace those paths.

Derived from §9 Viewing, comparison, and proofing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add a draggable left/right or top/bottom before/after divider in one canvas.
- [ ] Allow any two photos to be compared with zoom/pan locked for match-grade work.
- [ ] Add an N-select survey grid and lights-out/fullscreen review modes.
- [ ] Keep the existing side-by-side and hold-Space comparison behavior available.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-616 — Add canvas navigation, focus aids, and composition guides

**Original status:** `backlog`. **Original issue:** `KRMA-616`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-616
title: Add canvas navigation, focus aids, and composition guides
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:39.972Z
updated: 2026-09-26T13:56:43.487Z
blockers: []
order: wkkkkkjo
board: product
---

## Objective

Make precise inspection and crop/geometry work faster and more legible.

## Context

Canvas navigation, crop geometry, and analysis overlays already have separate owners; keep guides presentation-only and coordinate-correct.

Derived from §9 Viewing, comparison, and proofing ergonomics; §11 Crop UX polish in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add Fit, 1:1, and 2:1 commands with pixel readout and a navigator thumbnail showing the viewport.
- [ ] Add focus peaking at 100% and expose available focus/AF or depth/face evidence as optional overlays.
- [ ] Provide crop/straighten guides for thirds, diagonal, golden spiral, center, and aspect-safe framing.
- [ ] Support a secondary display or fullscreen preview while retaining crop and overlay coordinate alignment.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-617 — Build edit-aware smart previews for large libraries

**Original status:** `backlog`. **Original issue:** `KRMA-617`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-617
title: Build edit-aware smart previews for large libraries
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:40.657Z
updated: 2026-09-26T13:56:43.523Z
blockers: []
order: xfffffei
board: product
---

## Objective

Make culling and offline browsing responsive without running a full RAW develop render for every grid cell.

## Context

Visible-neighborhood thumbnail prioritization and windowed queries already exist. This ticket covers preview pyramids and throughput beyond that work.

Derived from §10 Performance and scale in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Build bounded 2560-pixel edit-aware previews in the background with progress, pause, quality selection, and storage accounting.
- [ ] Use an appropriate RAW embedded-JPEG fast path and visibly identify previews that approximate current edits.
- [ ] Measure scrolling and cold-open behavior on large RAW catalogs and prioritize visible/prefetch-ahead work.
- [ ] Keep final canvas/export output sourced from the original and preserve preview/export parity.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-618 — Add a work activity center and cache controls

**Original status:** `backlog`. **Original issue:** `KRMA-618`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-618
title: Add a work activity center and cache controls
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:41.325Z
updated: 2026-09-26T13:56:43.573Z
blockers: []
order: yaaaaa9c
board: product
---

## Objective

Make background work, cache usage, and degraded performance understandable and controllable.

## Context

Telemetry and bounded caches already exist; preserve bounded resource use and avoid adding another unbounded scheduler.

Derived from §10 Performance and scale in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show import, preview-build, analysis, export, and mask-cache jobs in one activity center with progress, cancel, and pause where safe.
- [ ] Expose preview/mask/analysis cache sizes and purge controls, offline-volume behavior, and low-disk warnings.
- [ ] Add a per-device performance mode for battery or memory pressure and define how preview quality adapts.
- [ ] Publish a measurable slider-to-presented-frame latency budget and surface a degraded-preview state instead of silently lagging.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-620 — Add a command palette and customizable workspaces

**Original status:** `backlog`. **Original issue:** `KRMA-620`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-620
title: Add a command palette and customizable workspaces
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:44.240Z
updated: 2026-09-26T13:56:44.536Z
blockers: []
order: zk
board: product
---

## Objective

Make the growing command set searchable and let photographers shape common work layouts.

## Context

The current menu and inspector architecture should remain the source of command availability; workspace preferences should be per device.

Derived from §11 Ease of use in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a keyboard-opened command palette that searches and invokes available menu and editing actions.
- [ ] Allow inspector sections to be hidden/reordered and frequently used controls to be pinned.
- [ ] Support saved workspace layouts such as Culling, Color, Retouch, and Print.
- [ ] Ensure palette commands respect current selection, active editor state, and command availability.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-621 — Complete accessibility, localization, and privacy affordances

**Original status:** `backlog`. **Original issue:** `KRMA-621`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-621
title: Complete accessibility, localization, and privacy affordances
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:44.955Z
updated: 2026-09-26T13:56:45.254Z
blockers: []
order: zs
board: product
---

## Objective

Make core library and editing workflows usable across assistive technologies, languages, and privacy expectations.

## Context

Keep macOS-native accessibility conventions and the no-third-party-dependency product constraint.

Derived from §11 Ease of use; §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Audit VoiceOver labels, focus order, and value announcements across grid, canvas, and controls.
- [ ] Support Dynamic Type, high-contrast mask overlays, and reduced-motion behavior.
- [ ] Localize user-visible strings and validate right-to-left layout in primary workflows.
- [ ] Explain on-device analysis and network behavior, and make face-recognition opt-in with clear disclosure.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-622 — Add scheduled package backups and crash-edit recovery

**Original status:** `backlog`. **Original issue:** `KRMA-622`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-622
title: Add scheduled package backups and crash-edit recovery
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:45.677Z
updated: 2026-09-26T13:56:46.019Z
blockers: []
order: zw
board: product
---

## Objective

Protect irreplaceable edits from package loss, failed upgrades, and interrupted writes.

## Context

Portable package backup/restore and termination-flush persistence exist; this ticket closes automation and abandoned-snapshot recovery gaps.

Derived from §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create scheduled package snapshots with retention controls and backup-before-upgrade behavior.
- [ ] Allow a chosen off-volume backup target and provide a dry-run restore summary before applying it.
- [ ] Recover abandoned edit journals on relaunch and let users review restored edits per photo.
- [ ] Exercise interruption and restore behavior without modifying imported originals.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-623 — Add a package health dashboard and support diagnostics bundle

**Original status:** `backlog`. **Original issue:** `KRMA-623`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-623
title: Add a package health dashboard and support diagnostics bundle
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:46.418Z
updated: 2026-09-26T13:56:46.718Z
blockers: []
order: zy
board: product
---

## Objective

Turn package integrity and support diagnostics into understandable, repairable user workflows.

## Context

Package validation and recovery primitives exist; surface them without reducing corruption to a log entry or changing data silently.

Derived from §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show package health on open and on demand, with background verification status and clear severity.
- [ ] List corrupt revisions, missing originals, and orphan sidecars with per-record repair/relink actions where possible.
- [ ] Export a sanitized diagnostics bundle with package validation, hardware/GPU, render version, and recent telemetry.
- [ ] Redact GPS and personal filenames by default and let the user review bundle contents.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-624 — Make package schema upgrades rollback-safe

**Original status:** `backlog`. **Original issue:** `KRMA-624`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-624
title: Make package schema upgrades rollback-safe
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:47.120Z
updated: 2026-09-26T13:56:47.413Z
blockers: []
order: zz
board: product
---

## Objective

Make library-format upgrades recoverable and explain refusal when a package comes from a newer app.

## Context

The evaluation found no rollback story for package schema changes. Coordinate this with package backup work without making migration depend on opaque external state.

Derived from §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Take and verify a rollback snapshot before a schema migration changes durable package data.
- [ ] Recover cleanly from interrupted migration and keep the pre-migration package available.
- [ ] Show an actionable message for a newer package version, including safe sidecar/export guidance.
- [ ] Present release notes alongside the existing updater flow.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-626 — Surface camera/lens support and decide video-file behavior

**Original status:** `backlog`. **Original issue:** `KRMA-626`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-626
title: Surface camera/lens support and decide video-file behavior
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:48.500Z
updated: 2026-09-26T13:56:48.792Z
blockers: []
order: zzq
board: product
---

## Objective

Make camera compatibility and video import behavior explicit instead of silently implying support.

## Context

Profile selection is decoder-bound and video support is currently ambiguous; this issue includes the product decision needed before implementation.

Derived from §13 Interop and ecosystem in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Expose whether a camera/lens uses embedded or built-in profile data and identify the mapping version.
- [ ] Show an understandable basic-support state for unrecognized camera bodies or lenses.
- [ ] Make and document an explicit product decision to support selected video still workflows or exclude video files.
- [ ] Ensure unsupported media is clearly handled during import and never silently appears as an editable photo.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
````

</details>

### KRMA-627 — Add automatic and manual lens-profile corrections

**Original status:** `backlog`. **Original issue:** `KRMA-627`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-627
title: Add automatic and manual lens-profile corrections
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T14:07:07.556Z
updated: 2026-09-26T14:07:07.844Z
blockers: []
order: zzv
board: product
---

## Objective

Correct lens distortion, optical vignetting, chromatic aberration, and defringe using automatic profiles and manual controls.

## Context

Derived from §2.3 Optics and geometry in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Look up a lens profile using available body/lens metadata and show when no profile is available.
- [ ] Provide separate lens vignetting and creative vignette controls, plus manual distortion adjustment.
- [ ] Correct lateral chromatic aberration and provide purple/green defringe sampling and hue controls.
- [ ] Keep corrections non-destructive and consistent in preview and full-resolution export.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
````

</details>

### KRMA-628 — Add Upright geometry and straighten-by-drag

**Original status:** `backlog`. **Original issue:** `KRMA-628`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-628
title: Add Upright geometry and straighten-by-drag
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T14:07:08.237Z
updated: 2026-09-26T14:07:08.523Z
blockers: []
order: zzx
board: product
---

## Objective

Provide guided and automatic perspective correction with practical crop and straighten controls.

## Context

Derived from §2.3 Optics and geometry; §11 Crop UX polish in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Offer Auto, Level, Vertical, and Full upright modes plus a guided two-line perspective tool.
- [ ] Allow a user-drawn horizon line to set straighten angle.
- [ ] Expose warp-to-fill versus constrain-crop behavior and follow-up scale, offset, aspect, and fine-rotation controls.
- [ ] Show composition and aspect guides while adjusting geometry and preserve the original non-destructive crop.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
````

</details>

### KRMA-629 — Add camera profile and DCP selection

**Original status:** `backlog`. **Original issue:** `KRMA-629`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-629
title: Add camera profile and DCP selection
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T14:07:08.908Z
updated: 2026-09-26T14:07:09.195Z
blockers: []
order: zzy
board: product
---

## Objective

Let photographers choose camera-matching profiles instead of relying only on decoder defaults.

## Context

Derived from §2.4 Color science depth in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Discover and display embedded or built-in camera profiles for the source when available.
- [ ] Support selecting compatible DCP profiles, including documented standard and camera-matching choices.
- [ ] Handle missing, unsupported, or mismatched profiles with a clear fallback and status.
- [ ] Persist profile selection and use the same color transform in preview and export.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
````

</details>

### KRMA-630 — Polish brush and crop interaction controls

**Original status:** `backlog`. **Original issue:** `KRMA-630`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-630
title: Polish brush and crop interaction controls
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T14:07:09.613Z
updated: 2026-09-26T14:07:09.896Z
blockers: []
order: zzz
board: product
---

## Objective

Make brush and crop interactions precise, discoverable, and comfortable with trackpads and supported input devices.

## Context

Derived from §11 Ease of use; §15 punchlist item 13 in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show a live brush size/feather cursor ring and add smoothing/stabilization and flow controls where applicable.
- [ ] Support pressure-aware brush behavior and Apple Pencil shortcuts when the platform and device expose them.
- [ ] Add crop quick keys for preset selection and aspect inversion, clear commit/cancel behavior, and pixel feedback while resizing.
- [ ] Keep existing keyboard, VoiceOver, and crop/mask coordinate behavior intact.

## Implementation notes

Preserve non-destructive edits, shared preview/export behavior, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation.
````

</details>

### KRMA-567 — Masking: select a mask by clicking its pin on the photo

**Original status:** `backlog`. **Original issue:** `KRMA-567`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-567
title: "Masking: select a mask by clicking its pin on the photo"
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:18.547Z
updated: 2026-09-26T13:56:42.342Z
depends_on:
  - KRMA-563
blockers: []
order: 5zzzzzzu
board: product
---

## Objective

Let a photographer choose "the sky" by pointing at the sky instead of reading the Masks list. Show a small pin on the canvas for each mask and select the mask by clicking its pin, as Lightroom does. This is an interaction change and needs product sign-off on pin placement and visibility before implementation.

## Acceptance criteria

- Each mask shows one pin at a stable, meaningful location (for example the gradient center, radial center, brush centroid, or smart-mask coverage centroid), transformed correctly through crop, zoom, and pan.
- Clicking a pin selects that mask (same effect as clicking its row); the selected mask's pin is visually distinct. Pins never intercept painting or gradient-handle drags.
- Pins can be hidden (for example follow the overlay toggle, or appear only on hover of the canvas); agreed behavior is documented.
- Pins are presentation-only: no document, history, or render-request changes.
- VoiceOver can reach and activate pins or an equivalent; tests cover pin placement math and selection; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Canvas geometry goes through `CanvasMaskTransform`; pointer input through `MaskPointerSurface` (hit testing only when a drawing tool is active).
````

</details>

### KRMA-568 — Masking: offer intent-based starting points when a mask is created

**Original status:** `backlog`. **Original issue:** `KRMA-568`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-568
title: "Masking: offer intent-based starting points when a mask is created"
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:19.544Z
updated: 2026-09-26T13:56:42.415Z
depends_on:
  - KRMA-563
blockers: []
order: 7ppppppi
board: product
---

## Objective

Photographers usually know what they want ("brighten the subject", "darken the sky") before they know the slider values. When a mask is created, offer a few one-click starting points that set sensible local adjustments, which the photographer then fine-tunes.

## Acceptance criteria

- After creating a mask, a small, dismissible set of starting points is offered (for example Brighten, Darken, Warm, Cool, Add detail, Soften); choosing one sets the mask's local adjustments to documented values in one undoable step.
- Starting points only set `LocalAdjustments` on the new mask; they never alter the mask shape, other masks, or global adjustments.
- Choosing nothing leaves the mask neutral; the offer does not reappear for that mask.
- Values are defined in one value type with tests (range-valid for every LocalAdjustmentControl, one undo entry, correct layer scope); reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Local controls, ranges and neutrals: Sources/KromoraKit/Models/LocalAdjustmentControl.swift; bindings via AppViewModel.localAdjustmentBinding.
````

</details>

### KRMA-569 — Masking: collapse unchanged adjustment groups and summarize changes

**Original status:** `backlog`. **Original issue:** `KRMA-569`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-569
title: "Masking: collapse unchanged adjustment groups and summarize changes"
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:20.547Z
updated: 2026-09-26T13:56:42.378Z
depends_on:
  - KRMA-563
blockers: []
order: 6uuuuuuo
board: product
---

## Objective

Replace the wall of 13 local sliders with something scannable. Keep the Light, Color, and Effects groups collapsed unless they contain changes, and show what changed on each group header (for example "Light · Exposure −0.7"), so the photographer sees what a mask does at a glance.

## Acceptance criteria

- Each group (Light, Color, Effects, as in `LocalAdjustmentControl.inspectorGroups`) is a disclosure; a group with any non-neutral value starts expanded, others start collapsed, per selected mask. Manual expand/collapse is respected while that mask stays selected.
- Collapsed group headers summarize changed controls with the same readouts the rows use; a group reset is available from the header.
- Amount stays visible outside the groups.
- No change to how values are stored, rendered, or undone.
- Tests cover the expansion rule and the summary text; reviewed in the running app for consistency with the Edit inspectors (InspectorDisclosure).

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Grouping lives in `LocalAdjustmentControl.inspectorGroups` (MaskingWorkspace.swift) with a coverage test in MaskingWorkspaceTests.
````

</details>

### KRMA-570 — Masking: move the canvas tools into a floating strip on the photo

**Original status:** `backlog`. **Original issue:** `KRMA-570`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-570
title: "Masking: move the canvas tools into a floating strip on the photo"
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:21.552Z
updated: 2026-09-26T13:56:42.451Z
depends_on:
  - KRMA-563
blockers: []
order: 8kkkkkkc
board: product
---

## Objective

Keep the photographer's eyes on the photo: move Brush, Erase, Linear, and Radial from the inspector into a small floating tool strip near the image (Pixelmator/Photos style), and retire "Select" as a visible tool since Esc already returns to it. The inspector then holds only masks and adjustments. This is an interaction change and needs product sign-off on placement before implementation.

## Acceptance criteria

- A floating strip appears over the canvas only while the Masking inspector is active, shows the four drawing tools with their shortcuts (B, E, L, R), highlights the active tool, and clicking the active tool again returns to no tool (same as Esc).
- Brush settings (size, feather, flow, strength) are reachable from the strip when Brush or Erase is active; Option-scroll and [ ] keep working.
- The strip never covers handles it cannot be moved away from; placement is agreed and documented, and it respects crop mode and comparison view.
- The inspector no longer shows the tool picker; the one-line tool guidance moves to the strip or a transient hint.
- VoiceOver and keyboard parity with today's tool picker; tests cover tool state transitions; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Tool state: `MaskInteractionState.Tool`; shortcuts in Sources/KromoraKit/Views/KeyboardShortcuts.swift; canvas host in Sources/KromoraKit/Views/PreviewView.swift.
````

</details>

### KRMA-571 — Masking: show a thumbnail of each mask in the Masks list

**Original status:** `backlog`. **Original issue:** `KRMA-571`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-571
title: "Masking: show a thumbnail of each mask in the Masks list"
type: feature
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:22.559Z
updated: 2026-09-26T13:56:42.486Z
depends_on:
  - KRMA-563
blockers: []
order: 9ffffff6
board: product
---

## Objective

Make masks recognisable at a glance rather than by name: show a tiny black-and-white silhouette of each mask's effective coverage in its Masks-list row (and optionally for parts of multi-part masks).

## Acceptance criteria

- Each mask row shows a small thumbnail of its effective coverage over the cropped frame, updated after edits settle (not per pointer sample).
- Thumbnails are generated off the main actor through the existing mask overlay render path at a tiny target size, cached per mask definition, and never block the preview or overlay renders.
- Presentation-only: no document, history, or export changes; disabled masks read as disabled.
- Tests cover thumbnail invalidation on mask edits and no work for unchanged masks; performance checked on a many-mask document; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Overlay images come from RenderEngine.makeMaskOverlayImage via MaskingWorkflowCoordinator.renderMaskOverlay (grayscale inspection already produces a silhouette).
````

</details>

### KRMA-580 — Feasibility spike: on-device pretrained semantic Sky mask

**Original status:** `backlog`. **Original issue:** `KRMA-580`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-580
title: "Feasibility spike: on-device pretrained semantic Sky mask"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - vision
  - masking
  - research
  - core-ml
created: 2026-09-25T03:02:00.429Z
updated: 2026-09-26T13:56:42.529Z
blockers: []
order: aaaaaaa0
board: product
---

## Objective

Determine whether Kromora can generate a useful automatic Sky matte locally on-device using an existing pretrained semantic-segmentation model. This is a feasibility and architecture spike with a minimal prototype, not production masking UI work.

Kromora does not want to train a custom model. Start by evaluating a small pretrained model with a known Sky class, with SegFormer B0 fine-tuned on ADE20K as the first candidate. Consider another off-the-shelf model only if it is materially easier to convert and ship on Apple platforms at comparable quality.

## Constraints

- No custom training, fine-tuning, or dataset creation.
- Inference must run fully on-device; photo data must not be sent to a service.
- Prefer Core ML and Apple frameworks for runtime integration.
- Preserve Kromora’s zero third-party runtime dependency constraint. Conversion tooling may use documented Python packages in a reproducible development script.
- Do not implement the final Add Mask → Sky UI or redesign the masking architecture.
- Keep the prototype small; it may live outside the production provider if that makes the feasibility work faster.

## Candidate

Evaluate SegFormer B0 pretrained/fine-tuned on ADE20K first. Confirm that the exact checkpoint includes a Sky class and verify the applicable licenses for the checkpoint, model code, and dataset. Prefer the smallest checkpoint that meets the quality bar. An alternative pretrained model is acceptable if the comparison explains why it is easier to convert/package on macOS with comparable Sky quality.

## Investigation requirements

### 1. Model acquisition and redistribution

- Record the exact model/checkpoint source, version or revision, class set, and expected downloaded and converted file sizes.
- Identify licenses for the weights, architecture/code, and training dataset separately.
- Confirm whether the selected artifacts may legally be redistributed in a commercial macOS application. Record evidence or unresolved legal questions; do not assume a permissive license from the model name alone.
- Record attribution and notice requirements.

### 2. Core ML conversion

- Determine whether the model converts and runs cleanly in Core ML on the project’s supported macOS deployment target.
- Prefer a reproducible conversion script in the repository over manual conversion steps.
- Record required Python, conversion tool, and package versions. Keep conversion dependencies out of the app’s runtime dependency graph.
- Record whether any unsupported layers, custom operations, or post-processing are required.

### 3. Input/output contract

Document the concrete model contract:

- model input width/height and color format
- RGB channel ordering and normalization
- output tensor shape and data type
- whether output contains logits, probabilities, or class IDs
- exact Sky class ID for the selected checkpoint
- resize/crop/letterbox policy and coordinate mapping from model output back to the analysis image
- confidence threshold or argmax policy, if applicable
- conversion of the class map into a grayscale/alpha matte

### 4. Prototype inference

Build the smallest deterministic harness needed to:

1. load the converted model,
2. preprocess a real image at the intended analysis resolution,
3. run local inference,
4. extract the Sky class,
5. map the matte back to analysis-image dimensions, and
6. save or inspect the matte in a useful grayscale/overlay form.

The prototype need not enter production masking code. Preserve source image dimensions and mapping metadata so coordinate mistakes can be distinguished from model quality.

### 5. Performance

Measure on Apple Silicon and record:

- converted model file size
- model load time
- first inference time
- warm inference time
- peak or approximate memory usage, if practical
- hardware, macOS version, Core ML compute-unit configuration, and analysis input dimensions

Use at least one representative Kromora-sized source image, but run inference at the model’s intended analysis resolution rather than full photo resolution. Report whether latency is reasonable for an interactive photo editor.

### 6. Quality

Test a small, varied set of images covering:

- clear blue sky
- cloudy or overcast sky
- sunset or sunrise
- sky partly hidden by trees
- skyline/buildings
- mountain horizon
- no-sky exterior
- indoor scene

Save sample masks or screenshots for review. Record obvious failure modes, including trees classified as sky, water classified as sky, bright windows classified as sky, horizon leakage, gaps between leaves, missed clouds, and false positives when there is no sky.

Compare against crude heuristics only as a baseline to show whether the pretrained model provides a meaningful improvement. Do not tune a custom classifier or train any model.

### 7. Integration fit

- Describe how the output would fit Kromora’s `SemanticMaskProviding` boundary and existing `AnalysisImage`, `RegionMask`, `NormalizedMask`, and `MaskStore` flow.
- Prefer returning the same kind of analysis-space grayscale matte used by existing semantic-mask providers.
- Identify cache/versioning, model resource packaging, memory, cancellation, and macOS availability considerations for a production provider.
- Keep any production-facing changes minimal and explicitly separate them from the feasibility prototype.

## Success criteria

The spike can recommend proceeding only if the evidence supports all of these:

- fully on-device inference with no custom training
- licensing that permits commercial redistribution of required artifacts
- a reproducible conversion/package path
- acceptable file size, memory use, and latency for an interactive editor
- masks meaningfully better than crude heuristics on the varied cases
- output can be represented in Kromora’s existing analysis-space mask format

If any criterion fails, document the blocker and recommend an alternative or no-go.

## Deliverables

- prototype inference harness and reproducible conversion script, if conversion is viable
- converted test model artifact when practical and legally distributable; otherwise document a reproducible download/build path without committing a large or restricted artifact
- model source, checkpoint/version, class set, license, notices, input/output contract, and conversion requirements
- measured file size, model load time, first/warm inference latency, and memory estimate
- saved sample mattes/screenshots for the varied quality set
- observed failure modes and recommendation on whether to proceed
- recommendation for the exact model/checkpoint to productionize, or a documented no-go

## Context

- Existing semantic provider boundary and Vision implementation: `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`.
- Analysis and cache integration: `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift` and `MaskStore.swift`.
- Analysis-space image and matte value types: `Sources/KromoraKit/Models/PhotoAnalysis/AnalysisImage.swift`, `RegionMask.swift`, and `AnalysisValueTypes.swift`.
- `CLAUDE.md` requires macOS 14+ and zero third-party runtime dependencies.
- Related but separate UI issue: KRMA-567 (select a mask by clicking its canvas pin); do not implement Sky creation UI in this spike.

## Checks

Run prototype/conversion checks appropriate to the chosen model, including a clean documented conversion or model-load/inference path. Then run:

- `git diff --check`

Record all commands and their results in the handoff. A production `swift build` is required only if production code or package resources are changed; do not add heavyweight dependencies or artifacts just to make the spike compile as an app feature.

## Out of scope

- Custom model training or fine-tuning.
- Add Mask → Sky production UX.
- Sky replacement, generative fill, edge-refinement UI, or user-painted corrections.
- Water, vegetation, or building masks.
- Shipping a large scene-segmentation framework.

## Handoff

Clearly document the selected model/checkpoint or no-go, source and license, commercial redistribution conclusion, converted model size, inference latency and hardware, Sky class index, preprocessing/output mapping, observed mask quality and failure modes, production integration risks, and the recommendation on whether to proceed.
````

</details>

### KRMA-583 — Add production on-device Sky semantic mask provider

**Original status:** `backlog`. **Original issue:** `KRMA-583`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-583
title: Add production on-device Sky semantic mask provider
type: feature
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - vision
  - masking
  - core-ml
  - performance
created: 2026-09-25T03:17:08.906Z
updated: 2026-09-26T13:56:42.571Z
depends_on:
  - KRMA-580
blockers: []
order: b555554u
board: product
---

## Objective

Productionize automatic on-device Sky masking in Kromora using the pretrained Core ML semantic-segmentation model selected and validated by KRMA-580. Add one production semantic class, `sky`, and keep scene-class extraction generic so more classes could be added later without a second provider architecture.

This issue depends on KRMA-580. Use the exact checkpoint, redistribution conclusion, Core ML artifact/conversion path, Sky class index, and input/output contract recorded by that spike. Do not guess these values or repeat the full model-selection exercise. If the spike is not a go, stop before adding or shipping a model artifact and record the blocker.

## Architecture

Add a scene-semantic provider that owns the model-specific inference and maps a requested semantic class from the shared class prediction result:

```text
SceneSemanticMaskProvider
    ↓
shared scene-segmentation inference
    ↓
class prediction map
    ↓
requested semantic class (.sky)
    ↓
analysis-space matte
```

Expose only `sky` in this issue. Keep class extraction generic enough for future vegetation, water, building, or ground classes, but do not add those classes or a broad masking architecture redesign.

## Implementation requirements

### Model ownership and lifecycle

- Add one selected Core ML model artifact to the appropriate app/package resource location, following the license and attribution requirements from KRMA-580.
- Do not duplicate model copies or introduce conversion dependencies into the app’s runtime dependency graph.
- Provide one appropriately scoped, lazily initialized model service/instance reused across images. Keep initialization and inference off the main actor/thread.
- Keep model ownership small and aligned with Kromora’s current architecture; do not introduce a general ML service framework.

### Preprocessing and output mapping

- Implement the exact resize/crop behavior, RGB ordering, normalization, and orientation policy documented by KRMA-580.
- Do not stretch a square model output to the photo. Map output coordinates back through the model’s resize/crop transform to the analysis image dimensions, preserving aspect and crop behavior.
- Produce a grayscale/alpha matte in Kromora’s analysis-image coordinate space, suitable for `RegionMask`/`NormalizedMask` and existing mask rendering.
- Keep mask/image coordinate conventions explicit and ensure the rendered matte aligns pixel-for-pixel with the analysis image.

### Sky extraction and edge quality

- Extract `sky` using the exact class ID and logits/probability/class-map interpretation documented by the spike.
- Generate a Sky-selected / non-Sky-unselected mask. Use confidence values if they improve results and the spike justifies the policy.
- Preserve useful soft output when available. Use only the simplest appropriate interpolation/refinement when mapping to analysis dimensions.
- Do not draw synthetic geometry, return a rectangular fallback, or silently substitute a full-frame mask.
- If there are no meaningful Sky pixels, return the existing semantic-mask not-applicable/unavailable behavior. Do not create an empty active mask or accidental full-frame inverse.

### Cache and concurrency

- Integrate with the existing semantic-mask cache/version system. Include model/checkpoint/provider version in cache identity so a future model change invalidates incompatible mattes.
- Deduplicate concurrent inference for the same source/image analysis and reuse the complete scene class map if it serves the requested class.
- Keep cancellation and cache/source identity fences consistent with existing providers.
- If one model pass produces the complete scene map, later scene-class requests should extract/cache their class matte from that result rather than rerun inference.

### Masking workflow

- Expose `.sky` as the only new scene-semantic target through the existing semantic mask and local-mask workflow so the generated result can be selected and edited like other semantic masks.
- Do not expose vegetation, water, buildings, ground, or other model classes.
- Avoid redesigning Add Mask or the masking workspace.

## Tests

Add deterministic tests around:

- class-map to Sky matte extraction and exact class ID mapping from KRMA-580
- non-square model input/output and image-space coordinate mapping
- resize/crop transform and orientation handling
- correct output dimensions and representative coverage
- no-Sky/unavailable behavior without empty active masks or full-frame inversions
- provider/model version participation in cache identity
- reuse of one cached scene-class result for multiple class extraction requests, if exposed by the architecture
- source/cache identity, concurrency deduplication, and cancellation as appropriate
- existing Vision Person, Face, Foreground, and Subject behavior remaining unchanged

Use synthetic class maps for stable unit coverage. Add at least one smoke/integration test with the actual model when practical and supported by the license/resource setup; do not make the entire suite depend on nondeterministic model output.

## Diagnostics

When debug diagnostics are enabled, make it possible to inspect or record:

- model input and output dimensions
- analysis/source image dimensions and mapping transform
- Sky class index
- Sky pixel coverage
- inference duration

Do not add noisy production logging by default.

## Acceptance criteria

- Sky inference runs entirely on-device with the selected pretrained model and no custom training.
- The model is loaded once/reused appropriately, and inference does not block the UI thread.
- One scene-model inference can be reused for concurrent or later requests for the same analysis identity.
- The provider returns an analysis-space Sky matte that aligns correctly with the photo and works through existing mask rendering/local adjustment paths.
- No-sky images report the semantic target as unavailable/not applicable rather than creating empty or full-frame masks.
- Model/provider changes invalidate cached Sky results.
- Only `sky` is exposed; existing Vision-backed semantic providers and behavior are unchanged.
- The implementation follows KRMA-580 licensing, artifact, preprocessing, class-index, and output-mapping findings.
- Handoff documents provider/model locations, preprocessing and class mapping, cache behavior, measured average inference latency, and the path for adding another semantic class.

## Context

- Prerequisite model decision and exact contract: KRMA-580, on-device pretrained semantic Sky feasibility spike.
- Existing provider boundary and Vision provider: `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`.
- Coordinator/cache integration: `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift` and `MaskStore.swift`.
- Analysis image and mask value types: `AnalysisImage.swift`, `RegionMask.swift`, `AnalysisValueTypes.swift`, and `MaskOperations.swift` in `Sources/KromoraKit/Models/PhotoAnalysis/`.
- Local semantic mask recipe and rendering path: `Sources/KromoraKit/Models/LocalMaskModels.swift`, `LocalMaskRendering.swift`, and `LocalMaskRenderer.swift`.
- Project constraints: macOS 14+ and zero third-party runtime dependencies (`CLAUDE.md`).

## Checks

- `swift build`
- Run relevant semantic-mask, model/provider, photo-analysis, local-mask rendering, and masking-workflow tests.
- Run the actual-model smoke test when practical.
- `git diff --check`

## Out of scope

- Sky replacement, generative fill, or user-selected models.
- Training or fine-tuning.
- Exposing vegetation, water, building, ground, or other scene classes.
- Changing Person, Face, Foreground, or Subject providers.
- Edge-refinement UI or broad masking-architecture redesign.

## Handoff

Document the provider and model resource locations, exact model/checkpoint and license, preprocessing pipeline, class/output mapping, image-space transform, cache/version behavior, average inference latency, no-Sky behavior, and how another semantic class can reuse the scene prediction result.
````

</details>

### KRMA-584 — Expose automatic Sky mask in masking workflow

**Original status:** `backlog`. **Original issue:** `KRMA-584`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-584
title: Expose automatic Sky mask in masking workflow
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - masking
  - semantic-mask
  - ui
created: 2026-09-25T03:19:13.712Z
updated: 2026-09-26T13:56:42.608Z
depends_on:
  - KRMA-583
blockers: []
order: bzzzzzzo
board: product
---

## Objective

Expose the production Sky semantic matte in Kromora's existing masking workflow. Users can create a Sky mask from Add Mask and edit it like the existing Subject, Person, and Foreground masks.

This issue depends on KRMA-583, which implements the scene-semantic Sky provider. Use its analysis-space matte, cache, and availability behavior; do not add UI workarounds for provider alignment or segmentation issues.

## Expected behavior

```text
Add Mask → Sky
```

- Selecting Sky requests the semantic matte and, when applicable, creates one ordinary editable local mask.
- The mask uses the existing overlay rendering and local adjustment workflow.
- It can be selected, renamed, inverted, reset, or deleted wherever those actions are supported for other local masks.
- Adjustments and mask state remain independent from other masks.
- Switching photos uses the correct photo's cached analysis and never carries a prior photo's matte into the new image.
- If no usable Sky is detected, do not create an empty or otherwise meaningless mask. Use the existing unavailable/not-applicable feedback; if none fits this flow, add the smallest consistent message or state.

## UI integration

- Add Sky alongside existing automatic semantic-mask choices in Add Mask.
- Do not add a separate AI section or redesign Add Mask.
- Expose only Sky; keep the existing structure compatible with future scene classes without adding Vegetation, Water, Buildings, or Ground now.
- Reuse existing semantic-mask loading/progress behavior. Keep the UI responsive while analysis runs and reuse scene inference already computed for the image.
- Render the provider matte through the normal mask overlay. If alignment is offset, stretched, or cropped, fix provider coordinate mapping in KRMA-583 rather than introducing rendering compensation here.

## Tests

Add or update deterministic workflow/UI tests covering:

- Sky appears in Add Mask.
- Selecting Sky creates exactly one editable Sky mask when applicable.
- No-sky/unavailable results do not create a bogus mask and communicate unavailability consistently.
- Sky selection, rename, inversion, reset/deletion behavior follows existing mask semantics.
- Sky adjustments do not mutate another mask's matte or adjustments.
- Switching photos requests/displays the correct cached Sky analysis without leaking the previous image's result.
- Existing semantic-mask and masking workflow behavior remains unchanged.

Prefer provider/cache test seams or synthetic results over tests that depend on nondeterministic model inference. Keep actual model inference off the main actor/thread.

## Acceptance criteria

- Sky is available from Add Mask next to existing automatic semantic options.
- A usable result creates a normal independently editable local mask with the existing overlay and adjustment behavior.
- An unavailable result creates no mask and gives consistent feedback.
- Mask selection and supported rename/invert/reset/delete actions behave as they do for other semantic masks.
- Per-mask adjustments and per-photo cached results stay isolated.
- Existing loading and inference reuse behavior is preserved; the UI remains responsive.
- No renderer alignment hacks or additional scene categories are introduced.

## Dependency and context

- Depends on KRMA-583: production on-device Sky semantic mask provider.
- Follow the semantic mask creation path, Add Mask options, loading state, and local-mask tests already used by Subject, Person, and Foreground.
- Kromora targets macOS 14+ and has no third-party runtime dependencies.

## Checks

- `swift build`
- Run relevant `MaskingWorkflow`, `LocalMask`, and semantic-mask tests.
- `git diff --check`

## Out of scope

- Sky replacement or generative editing.
- New mask-combination UX or general Add Mask redesign.
- Vegetation, Water, Buildings, Ground, or other scene classes.
- UI-side correction of matte alignment or segmentation quality.

## Handoff

Document where Sky was added to Add Mask, how provider availability/loading is surfaced, how mask creation uses the existing local-mask workflow, and which tests/checks were run.
````

</details>

### KRMA-648 — Add edge-mask preview for sharpening Masking control

**Original status:** `backlog`. **Original issue:** `KRMA-648`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-648
title: Add edge-mask preview for sharpening Masking control
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T06:28:08.602Z
updated: 2026-09-27T06:28:08.602Z
parent: KRMA-598
blockers: []
order: zzzx
board: product
---

## Objective

Add a live edge-mask preview to the sharpening Masking control, matching the acceptance
criteria in KRMA-598 (parent).

## Context

KRMA-598 added sharpening Radius/Amount/Detail/Masking and wired Masking into
`RenderPipeline.applyDetailControls` (Sources/KromoraKit/Models/RenderPipeline.swift), which
derives a CIEdges-based matte to restrict sharpening to strong edges. The evaluation this
feature was derived from (`.context/2026-09-22-professional-polish-evaluation.md` §2.2) calls
out Lightroom's Alt-preview (hold a modifier while dragging Masking to see the black/white
mask full-screen) as a headline feature on its own -- the slider alone is not the acceptance bar.

KRMA-598 shipped the underlying masking math and persistence but explicitly deferred the
preview UI (see its implementation comment and verification report).

## Acceptance criteria

- [ ] While adjusting sharpening Masking (drag or equivalent interaction), show a live
      grayscale preview of the derived edge mask over the image.
- [ ] The preview reuses the same mask CIImage `RenderPipeline.applyDetailControls` already
      computes, rather than a second implementation, so the preview matches the applied result.
- [ ] Regression coverage for the preview's visibility/dismissal and that it does not mutate
      the edit document (preview-only, like existing crop/comparison overlays).

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum,
Swift 6 safety, and zero third-party dependencies.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
````

</details>

### KRMA-649 — Add single-pixel color-noise inspection view

**Original status:** `backlog`. **Original issue:** `KRMA-649`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-649
title: Add single-pixel color-noise inspection view
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T06:28:55.340Z
updated: 2026-09-27T06:28:55.340Z
parent: KRMA-598
blockers: []
order: zzzy
board: product
---

## Objective

Add a single-pixel color-noise inspection view, matching the acceptance criteria in KRMA-598
(parent).

## Context

KRMA-598 added luminance/color noise reduction and detail/contrast retention controls
(`DetailAdjustments` in `Sources/KromoraKit/Models/EffectsAdjustments.swift`, applied through
`RenderPipeline.applyDetailControls`), but did not add the acceptance-criteria "single-pixel
color-noise inspection view" -- a 100%-zoom pixel-level readout that lets a photographer judge
residual chroma noise directly, the way `docs/COMPARISON_MODE.md`/clipping-alert style inspection
tools already let them judge other artifacts. KRMA-598's implementation comment explicitly
disclosed this as deferred.

## Acceptance criteria

- [ ] Add an inspection view that magnifies the image to single-pixel (100%/1:1) scale at the
      cursor or a fixed sample point, useful for judging color noise after luminance/color NR
      settings are applied.
- [ ] The view reflects the current noise reduction settings (before/after or live), not just
      the unprocessed source.
- [ ] Regression coverage proving the inspection view does not mutate the edit document and
      updates when noise controls change.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum,
Swift 6 safety, and zero third-party dependencies. Consider whether existing Info-tab pixel
readout plumbing (see KRMA-597) can be reused rather than building a second inspection surface.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
````

</details>

### KRMA-651 — Add automatic pupil/face detection for red-eye and pet-eye correction

**Original status:** `backlog`. **Original issue:** `KRMA-651`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-651
title: Add automatic pupil/face detection for red-eye and pet-eye correction
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T07:14:01.683Z
updated: 2026-09-27T07:14:01.683Z
parent: KRMA-599
blockers: []
order: zzzzh
board: product
---

## Objective

Add automatic pupil/face detection so an eye correction can be placed and sized without the
user manually positioning every eye, matching the acceptance criteria in KRMA-599 (parent).

## Context

KRMA-599's acceptance criteria call for "red-eye and pet-eye correction with adjustable pupil
detection, size, and darkening." The shipped `EyeCorrection` model
(`Sources/KromoraKit/Models/RetouchModels.swift`) and `RetouchInspectorView` let a user add an
eye correction and adjust its center, width/height, pupil size, and darkening — but center
placement is entirely manual; there is no automatic pupil or face/eye detection anywhere in the
feature. `docs/RETOUCH.md` explicitly discloses this: "It does not perform automatic face/pupil
detection; eye centers are recipe values." `EyeCorrection` has no field recording whether a
center came from detection vs. manual placement (contrast with `RetouchSpot.sourceWasAutoPicked`,
which exists on spots but is likewise never set by any auto-pick logic today).

## Acceptance criteria

- [ ] Detect likely human pupils (and, where feasible, pet eyes) in the current preview/photo
      and offer them as starting points for a new `EyeCorrection`, using an on-device framework
      already available on macOS 14 (e.g. Vision face/landmark detection) — no new third-party
      dependency.
- [ ] Detected placement remains fully editable afterward (center, size, pupil size, darkening),
      preserving the existing manual-placement path as a fallback when detection finds nothing.
- [ ] Regression coverage for the detection-to-recipe path (detected point maps to a valid,
      editable `EyeCorrection` in source-normalized coordinates) and for the no-detection
      fallback.

## Implementation notes

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
````

</details>

### KRMA-655 — Add animated zebra overlay for clipped highlights

**Original status:** `backlog`. **Original issue:** `KRMA-655`.

<details>
<summary>Open preserved issue specification</summary>

````markdown
---
id: KRMA-655
title: Add animated zebra overlay for clipped highlights
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - clipping
created: 2026-09-27T16:16:12.867Z
updated: 2026-09-27T16:16:38.997Z
order: zzzzx
board: product
---

## Objective

Add a toggleable zebra overlay that marks clipped highlight regions on the photo with animated diagonal dashed lines, similar to the exposure zebras shown in Sony cameras.

## Context

The current canvas clipping feedback reports total highlight and shadow counts in a small badge. It does not show where clipped highlights occur. The attached camera-screen reference shows a bright lamp area marked by diagonal zebra stripes; the requested behavior is a moving dashed pattern over the clipped image regions.

Relevant existing code:

- `Sources/KromoraKit/Views/PreviewView.swift` — displays the current clipping alert overlay over the canvas.
- `Sources/KromoraKit/Models/KromoraSettings.swift` — persists the `showClippingAlerts` preference.
- `Sources/KromoraKit/Models/Histogram.swift` — computes histogram bins and clipping counts from the rendered preview.
- `Sources/KromoraKit/Views/InfoInspectorView.swift` — displays numeric clipping counts.
- `Tests/KromoraKitTests/HistogramTests.swift` and Preview/canvas overlay tests — likely locations for focused coverage.

KRMA-616 includes focus peaking for focus evidence. This ticket is specifically for exposure zebras that reveal clipped image tones; do not treat these as the same overlay.

## Acceptance criteria

- [ ] Draw animated diagonal dashed zebra marks only over clipped highlight regions of the current rendered photo, so the user can see where highlights have reached the display clipping ceiling.
- [ ] Keep the pattern aligned with the displayed image through crop, zoom, pan, and preview updates; it must not cover the surrounding inspector or window chrome.
- [ ] Make the zebra overlay toggleable through the existing clipping-alert control or an equally clear control, and keep the numeric histogram clipping counts available.
- [ ] Keep the overlay presentation-only: it does not change rendered pixels, saved edits, exports, or editing hit testing.
- [ ] Keep animation lightweight and respect the system Reduce Motion setting.
- [ ] Add focused tests for identifying/displaying clipped regions and for overlay visibility/state, and update relevant documentation.

## Implementation notes

Use the rendered image representation and clipping definition consistently with the histogram; do not infer positions from aggregate counts alone. Preserve the existing highlight/shadow count behavior. Keep the overlay coordinate mapping correct for the displayed crop and canvas transform, and preserve macOS 14, Swift 6, and zero third-party dependencies.
````

</details>
