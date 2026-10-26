import AppKit
import CoreGraphics
import XCTest

@testable import KromoraKit

/// KRMA-1131: opt-in contact sheet for the A/B review that decides which starter Looks the
/// film-look family supersedes. It renders each new Look next to the starter Look(s) it would
/// replace through the app's real render path, on neutral develops of local photos, and writes one
/// PNG for a person to judge. It asserts nothing about taste and deletes nothing.
///
/// Run with `KROMORA_LOOK_CONTACT_SHEET=<out.png> KROMORA_RAW_FIXTURE_DIR=<folder with photos>`.
final class FilmLookContactSheetTests: XCTestCase {
    /// (replacement, candidates it would supersede), by manifest id.
    private static let pairs: [(new: String, old: [String])] = [
        ("kromora.starter.field-report", ["kromora.starter.muted-film"]),
        ("kromora.starter.amber-print", ["kromora.starter.honey-negative"]),
        ("kromora.starter.plain-mono", ["kromora.starter.soft-mono", "kromora.starter.paper-grain"]),
        ("kromora.starter.fine-mono", ["kromora.starter.silver-noir"]),
    ]

    func testWriteFilmLookContactSheet() async throws {
        let env = ProcessInfo.processInfo.environment
        let out = try XCTUnwrap(env["KROMORA_LOOK_CONTACT_SHEET"].map { URL(fileURLWithPath: $0) },
                                "opt-in: set KROMORA_LOOK_CONTACT_SHEET")
        let photos = Array(Fixtures.localRAWURLs.prefix(2))
        try XCTSkipIf(photos.isEmpty, "set KROMORA_RAW_FIXTURE_DIR to a folder with photos")

        let library = BundledLookLibrary.load()
        func look(_ id: String) throws -> CubeLUT {
            try XCTUnwrap(library.looks.first { $0.id == id }, "missing bundled Look \(id)")
        }

        let cell = CGSize(width: 520, height: 390)
        let engine = RenderEngine(maskResolver: DefaultLocalMaskResolver())

        func render(_ source: ImageSource, _ cube: CubeLUT?) async throws -> CGImage {
            var document = EditDocument()
            if let cube { document.lut = LUTSettings(lutID: cube.lutID, intensity: 1) }
            let request = RenderRequest(
                source: source, document: document, lut: cube, targetSize: cell,
                quality: .preview, output: .raster, space: .current)
            let image = await engine.makeCGImage(request)
            return try XCTUnwrap(image, "render failed")
        }

        // Columns: neutral | new Look | each candidate. Rows: pair x photo.
        let maxColumns = 1 + 1 + (Self.pairs.map(\.old.count).max() ?? 1)
        let label: CGFloat = 26
        let rowCount = Self.pairs.count * photos.count
        let width = Int(cell.width) * maxColumns
        let height = Int(cell.height + label) * rowCount
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        func caption(_ text: String, x: CGFloat, y: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: x + 8, y: y + 7)
            CTLineDraw(line, context)
        }

        var row = 0
        for pair in Self.pairs {
            for photo in photos {
                let source = ImageSource(url: photo, nativeExtent: .zero)
                let top = CGFloat(height) - CGFloat(row + 1) * (cell.height + label)
                var column = 0
                func draw(_ image: CGImage, _ text: String) {
                    let x = CGFloat(column) * cell.width
                    let scale = min(cell.width / CGFloat(image.width), cell.height / CGFloat(image.height))
                    let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
                    context.draw(image, in: CGRect(
                        x: x + (cell.width - w) / 2, y: top + label + (cell.height - h) / 2, width: w, height: h))
                    caption(text, x: x, y: top)
                    column += 1
                }
                draw(try await render(source, nil), "neutral  (\(photo.deletingPathExtension().lastPathComponent))")
                let replacement = try look(pair.new)
                draw(try await render(source, replacement), "NEW  \(replacement.name)")
                // Candidates removed by the review (muted-film, paper-grain, silver-noir) are no
                // longer bundled; the sheet keeps the Looks that still are.
                for id in pair.old {
                    guard let candidate = library.looks.first(where: { $0.id == id }) else { continue }
                    draw(try await render(source, candidate), "remove?  \(candidate.name)")
                }
                row += 1
            }
        }

        let image = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: out)
        print("=== KRMA-1131 contact sheet: \(out.path) (\(width)x\(height), \(rowCount) rows)")
    }
}
