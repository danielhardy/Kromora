import XCTest
import CoreImage
@testable import KromoraKit

/// The active Display P3 starter set (KRMA-1117, activated by KRMA-1121): valid, stamped, genuinely
/// regenerated from the sRGB source lattices rather than retagged, and free of unintended neutral
/// clipping. The sRGB sources live in `scripts/starter-looks-srgb` and are not bundled.
final class BundledP3LookTests: XCTestCase {
    private var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/starter-looks-srgb", isDirectory: true)
    }

    private func sourceLooks() throws -> [String: CubeLUT] {
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: sourceDirectory.appendingPathComponent("manifest.json"))) as! [String: Any]
        var result = [String: CubeLUT]()
        for entry in manifest["looks"] as! [[String: Any]] {
            let resource = entry["resource"] as! String
            result[entry["id"] as! String] = try CubeLUT(
                url: sourceDirectory.appendingPathComponent(resource), source: .bundled)
        }
        return result
    }

    func testTheActiveStarterSetIsDisplayP3() throws {
        let library = BundledLookLibrary.load()
        XCTAssertEqual(library.looks.count, 14)
        XCTAssertTrue(library.warnings.isEmpty, "\(library.warnings)")
        XCTAssertTrue(library.looks.allSatisfy { $0.authoringSpace == .displayP3 })
        XCTAssertEqual(BundledLookLibrary.resourceSubdirectory, "Resources/StarterLooks")
        let manifest = try BundledLookLibrary.validate(subdirectory: BundledLookLibrary.resourceSubdirectory)
        XCTAssertTrue(manifest.looks.allSatisfy { $0.approval.notes.contains("Display P3") })
        // The 13 resampled starters name the P3 script; the film-family Looks are authored directly in P3.
        XCTAssertTrue(manifest.looks.allSatisfy {
            $0.source.contains("generate-p3-starter-looks") || $0.source.contains("SlideLookGenerator")
        })
    }

    func testP3TablesAreRegeneratedNotRetagged() throws {
        let sources = try sourceLooks()
        let resampled = BundledLookLibrary.load().looks.filter { sources[$0.id] != nil }
        XCTAssertEqual(Set(sources.keys), Set(resampled.map(\.id)))
        XCTAssertEqual(resampled.count, 13)
        for p3 in resampled {
            let srgb = try XCTUnwrap(sources[p3.id])
            XCTAssertEqual(srgb.authoringSpace, .sRGB)
            XCTAssertGreaterThan(p3.size, srgb.size, "\(p3.name) is resampled on a finer P3 lattice")
            XCTAssertNotEqual(p3.contentHash, srgb.contentHash)
        }
    }

    /// Neutral input must come out the same neutral tone as the sRGB source Look, within a small
    /// tolerance, so the regeneration neither clips nor shifts the tonal ramp.
    func testNeutralRampMatchesTheSRGBLookWithoutClipping() throws {
        let steps = 17
        var pixels = [Float]()
        for i in 0..<steps { let v = Float(i) / Float(steps - 1); pixels += [v, v, v, 1] }
        let ramp = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * 4), bytesPerRow: pixels.count * 4,
            size: CGSize(width: steps, height: 1), format: .RGBAf, colorSpace: WorkingSpace.sRGB.cgColorSpace)
        let context = CIContext(options: [.workingColorSpace: WorkingSpace.displayP3.cgColorSpace])
        func render(_ lut: CubeLUT) throws -> [UInt8] {
            let output = try XCTUnwrap(lut.apply(to: ramp))
            var bytes = [UInt8](repeating: 0, count: steps * 4)
            context.render(output, toBitmap: &bytes, rowBytes: steps * 4,
                           bounds: CGRect(x: 0, y: 0, width: steps, height: 1),
                           format: .RGBA8, colorSpace: WorkingSpace.sRGB.cgColorSpace)
            return bytes
        }
        let sources = try sourceLooks()
        for p3 in BundledLookLibrary.load().looks {
            guard let source = sources[p3.id] else { continue }   // directly authored Looks have no sRGB source
            let a = try render(source)
            let b = try render(p3)
            for i in 0..<steps {
                for c in 0..<3 {
                    XCTAssertEqual(Int(a[i * 4 + c]), Int(b[i * 4 + c]), accuracy: 4,
                                   "\(p3.name) neutral step \(i) channel \(c)")
                }
            }
        }
    }
}
