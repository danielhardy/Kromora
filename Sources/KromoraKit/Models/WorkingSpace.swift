import CoreGraphics

/// The one colour space Kromora works in.
///
/// Two things have to agree or the app is quietly wrong:
///
/// - **LUT interpolation** — the space `CIColorCubeWithColorSpace` interpolates the cube in.
/// - **Output encoding** — the space every raster and every export encoder writes.
///
/// Before this type they were four independent `CGColorSpace(name: .sRGB)!` literals that merely
/// happened to agree, plus **two sites that passed no colour space at all**: `createCGImage` in
/// `renderPreview` and `renderToNSImage` used the `CIContext` default while export forced sRGB. That
/// is byte-identical at sRGB today and wrong the moment a wide-gamut source or a P3 output appears —
/// a latent preview/export mismatch rather than a hypothetical one.
///
/// Every one of those sites now takes a `WorkingSpace`, defaulting to `.current`. Because they read
/// one value, they cannot desync: changing the default moves LUT interpolation and output encoding
/// together, atomically, in one line.
///
/// **Not covered, deliberately:** source *decode*. A P3 or Adobe RGB JPEG is still funnelled through
/// its embedded profile into the `CIContext` working space, exactly as before. This seam governs how
/// the cube is interpolated and how pixels are written out — not how they are read in.
///
/// **A Look's interpolation space is its authoring space, not this type's `current`.** A cube is
/// stamped (`CubeLUT.authoringSpaceHeaderKey`) and applied in the space it was written in, so an sRGB
/// Look keeps its meaning in a P3 pipeline. Save as Look (`LookLUTConverter`) and Derive
/// (`RecipeExtractor.Options.authoringSpace`) sample, fit, and stamp one explicit space, which is
/// `current` until the P3 flip and is threaded through the neutral baseline, measurement buffers and
/// fit rather than pinned.
///
/// See `docs/ENGINEERING_GUIDE.md`
enum WorkingSpace: String, Codable, Sendable, Equatable, CaseIterable {
    case sRGB
    case displayP3

    var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB:
            // Both names are guaranteed-resolvable system constants, so the
            // force-unwrap is safe and — the point of this type — localized here.
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }

    /// The space the app renders and exports in. Flipping this moves the canvas/export target and the
    /// default authoring space of newly saved and derived Looks.
    static let current: WorkingSpace = .sRGB
}
