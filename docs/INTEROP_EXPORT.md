# Interoperability exports

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

The Edit toolbar's Share action renders a TIFF copy and opens the macOS sharing picker. With multiple
photos selected, Kromora renders the selection and passes the successful TIFF files together, so
AirDrop and other installed sharing services can deliver them as a batch. Sharing exports preserve
camera metadata and exclude GPS under the existing export policy. Services and Shortcuts destinations
shown by macOS depend on what is installed and enabled on that Mac.

## Original + settings bundle

Choose **File → Export Original + Settings Bundle…** and select a parent folder. Kromora creates a
`.kromora-original` package containing the byte-for-byte source file, a Codable `settings.json`
`EditDocument`, and a `manifest.json` with SHA-256 checksums for both payloads. Export verifies the
written files before publishing the package. `OriginalSettingsBundle.verify(at:)` checks those
checksums when a consumer needs to validate the package. The source asset in the active library is
only read; the bundle makes its own copy. The manifest records that the original is read-only and
whether location metadata was included. This export currently excludes GPS metadata from the
manifest policy; no source bytes or EXIF fields are rewritten.

The bundle is a Finder package directory, not a compressed archive. Preserve all three files when
copying it. An edit recipe is data, not a rendered preview, and reproducing a LUT-backed edit also
requires the corresponding LUT to be available in Kromora.
