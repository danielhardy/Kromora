# Interoperability exports

This is a rendered-file handoff guide, not a promise of live layered or Lightroom-compatible
round-tripping. See [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md) for the product boundary.

## External editor

Choose **File → Edit in External Editor…** to render the current non-destructive document as a
full-resolution TIFF. Kromora writes the TIFF first and then opens it with macOS's default TIFF
editor. Camera metadata is retained; precise location metadata remains excluded. The open library
original is never passed to the external editor. To bring the result back, choose **File → Open
Image…** and select the edited TIFF. This creates a separate library photo; the current package has
no stack/group relationship model, so the returned derivative is not auto-stacked with its source.

TIFF is used for the handoff because the current render encoder supports it directly. PSD is not
written by Kromora. The external editor may save another format, which can be imported through the
same Open Image command.

## Sharing

The Edit toolbar's Share action opens the macOS sharing picker immediately and renders nothing
until the user picks a service. Each shared photo is a lazy file representation: the service's
request renders the photo from the snapshot taken when the picker opened, so cancelling the picker
writes nothing. Output is HEIC with the long edge capped at 4096 px (smaller photos are never
upscaled) at quality 0.85, encoded in the current working space; if HEIC encoding fails the item is
re-encoded as JPEG so it is not dropped. With multiple photos selected, each is its own lazy item
in one picker, so AirDrop and other services can deliver them as a batch. Sharing preserves camera
metadata and excludes GPS. Rendering runs as a registered share job, and a new export, Share, or
bundle command is refused while one is running. Services and Shortcuts destinations shown by macOS
depend on what is installed and enabled on that Mac.

## Original + settings bundle

Choose **File → Export Original + Settings Bundle…**. Kromora first asks whether to keep the
original's embedded metadata, warning that the preserved file may contain location data such as GPS
coordinates; choose **Keep Original Metadata** to continue, then select a parent folder. Kromora creates a
`.kromora-original` package containing the byte-for-byte source file, a Codable `settings.json`
`EditDocument`, and a `manifest.json` with SHA-256 checksums for both payloads. Export verifies the
written files before publishing the package. `OriginalSettingsBundle.verify(at:)` checks those
checksums when a consumer needs to validate the package. The source asset in the active library is
only read; the bundle makes its own copy. The manifest records that the original is read-only and
whether location metadata was included; the app always records `locationMetadataIncluded: true`
because the original is copied byte-for-byte, so any GPS in the source file travels with the bundle.
No source bytes or EXIF fields are rewritten.

The bundle is a Finder package directory, not a compressed archive. Preserve all three files when
copying it. An edit recipe is data, not a rendered preview, and reproducing a LUT-backed edit also
requires the corresponding LUT to be available in Kromora.
