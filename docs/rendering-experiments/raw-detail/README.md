# RAW luminance noise reduction: decoder vs RGB crops (KRMA-1175)

Each sheet is 1:1 pixels (shown at 2×, nearest-neighbour) of the full-resolution development. Columns:
neutral (decoder defaults, no control), decoder Luminance NR at slider 50 (`RAWDetailRouting`), and the
previous RGB `CINoiseReduction` path with its slider bisected until the flat-field noise equals the
decoder's. Rows: the strongest-edge tile and the flattest tile chosen from the neutral frame.

- `DSC00324-luminance50.png` — ISO 2000 Sony ILCE-7M2 bird. RGB matched at slider 54.
- `DSC04513-luminance50.png` — night sky. RGB matched at slider 49.

Regenerate with
`KROMORA_RAW_DETAIL_CROP_DIR=<empty dir> swift test --filter RAWDetailRoutingBenchmark/testPrintMatchedNoiseComparison`
(sheets are assembled from the per-tile PNGs the test writes) and read the numbers in
[`docs/TESTING.md`](../../TESTING.md#raw-noise-reduction-routing-krma-1175). Not a perceptual study.

Photos by Daniel Hardy, used under CC BY 4.0, cropped and processed by the Kromora renderer.
