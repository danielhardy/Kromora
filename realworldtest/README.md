# Local real-world image fixtures

This is a local-only fixture folder. Put RAW images here to make them available to RAW-dependent
tests. `Fixtures.localRAWURLs` discovers supported RAW files in this directory automatically; no
environment variable is needed. Tests that inspect every image visit all discovered RAWs; tests
that need one image use the first filename-sorted RAW. To isolate one input, point
`KROMORA_RAW_FIXTURE_DIR` at a directory containing only that RAW. The optional lane can be run with:

```bash
scripts/ci-tests.sh optional
```

The RAW extensions currently recognized are DNG, CR2, CR3, NEF, ARW, ORF, RAF, RW2, PEF, SRW, X3F,
and RAW. Standard formats such as HEIC are not selected by the RAW fixture helpers. For KRMA-737,
place `IMG_0371.DNG` here to make it part of the per-image decoder-seed check. Tests that require a
matching in-camera JPEG still need a same-stem pair in the fixture directory.

Files in this folder are ignored by Git; only this README is tracked. Keep any local fixtures you add
here out of commits unless the project explicitly changes that policy. Required test lanes use
generated fixtures and continue to run without local images.

The following terms apply to files Daniel Hardy has separately released for local project use:

I, Daniel Hardy, license the photo files in this directory under the
[Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

You may share and adapt these files for any purpose, including commercial purposes, provided that
you give appropriate credit, link to the license, and indicate whether changes were made. Suggested
credit: “Photo by Daniel Hardy, used under CC BY 4.0.”

This release covers my copyright in the contributed photographs. It does not grant rights to any
third-party people, property, trademarks, or other material depicted in them; users are responsible
for obtaining any permissions those uses may require. The files are provided as-is, without warranty.
