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
1. Spot heal/clone/red-eye + visualize spots.
2. User presets + preset browser + sync/auto-sync + history panel + snapshots + virtual copies.
3. Luminance + color range masks; one-click Subject/Sky/People targets.
4. WB eyedropper + preset menu; per-channel + parametric curves; clipping overlays + RGB/Lab readout.
5. Lens auto-profiles + CA/defringe; Upright auto/level/guided.
6. Sharpening radius/masking/detail + output sharpening; B&W mixer; calibration panel.
7. Export presets + queue + naming tokens + sharpen-for + watermark + AdobeRGB/ProPhoto targets + print.
8. Keywords/labels/faces + collections/smart collections + stacks + editable IPTC + XMP round-trip.
9. Import dialog with previews/dupe-guard/rename/date-folders/backup-copy/apply-on-import.
10. Backup/versioning + crash recovery + health dashboard + diagnostics bundle.

**Turns powerful into pleasant:**
11. Reference view, split before/after divider, survey grid, fullscreen/lights-out, second display, navigator, 1:1/2:1 loupe.
12. Histogram scopes (waveform/parade/vectorscope), proof preview, HDR story, overlay guides (thirds/golden/diagonal/safe).
13. Brush cursor ring + auto-mask + flow controls + Pencil support; crop commit keys + invert-aspect key + straighten-line.
14. Smart-preview pyramid + activity center + cache settings + cold-open budget.
15. Command palette, saved workspaces, guided-edit cards, first-run sample library, in-app shortcut sheet.
16. External-editor round-trip, drag-out/Share/Shortcuts actions, standard-mapped XMP, original+settings bundle.
17. VoiceOver/Dynamic Type/reduced-motion/localization pass; privacy page (on-device, no analytics).

---

*End of evaluation. No implementation, sequencing, or cost judgments were made — that belongs to planning. The next artifact after this should be product decisions (which rows are in-scope for Kromora's identity), not task breakdowns.*
