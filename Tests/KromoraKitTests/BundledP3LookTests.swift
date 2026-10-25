import XCTest
import CoreImage
@testable import KromoraKit

/// The prepared Display P3 starter set (KRMA-1117): valid, stamped, genuinely regenerated rather than
/// retagged, free of unintended neutral clipping, and inactive until KRMA-1121.
final class BundledP3LookTests: XCTestCase {
    private let p3Directory = BundledLookLibrary.preparedP3ResourceSubdirectory

    func testTheActiveStarterSetIsStillSRGBAndUnchanged() throws {
        let library = BundledLookLibrary.load()
        XCTAssertEqual(library.looks.count, 13)
        XCTAssertTrue(library.warnings.isEmpty)
        XCTAssertTrue(library.looks.allSatisfy { $0.authoringSpace == .sRGB })
        XCTAssertEqual(BundledLookLibrary.resourceSubdirectory, "Resources/StarterLooks")
    }

    func testPreparedP3SetValidatesAndIsStamped() throws {
        let manifest = try BundledLookLibrary.validate(subdirectory: p3Directory)
        XCTAssertEqual(manifest.looks.count, 13)
        XCTAssertTrue(manifest.looks.allSatisfy { $0.approval.notes.contains("Display P3") })
        XCTAssertTrue(manifest.looks.allSatisfy { $0.source.contains("generate-p3-starter-looks") })

        let library = BundledLookLibrary.load(subdirectory: p3Directory)
        XCTAssertTrue(library.warnings.isEmpty, "\(library.warnings)")
        XCTAssertEqual(library.looks.count, 13)
        XCTAssertTrue(library.looks.allSatisfy { $0.authoringSpace == .displayP3 })
        XCTAssertEqual(
            Set(library.looks.map(\.id)), Set(BundledLookLibrary.load().looks.map(\.id)),
            "the flip keeps stable Look identities"
        )
    }

    func testP3TablesAreRegeneratedNotRetagged() throws {
        let active = Dictionary(uniqueKeysWithValues: BundledLookLibrary.load().looks.map { ($0.id, $0) })
        for p3 in BundledLookLibrary.load(subdirectory: p3Directory).looks {
            let srgb = try XCTUnwrap(active[p3.id])
            XCTAssertGreaterThan(p3.size, srgb.size, "\(p3.name) is resampled on a finer P3 lattice")
            XCTAssertNotEqual(p3.contentHash, srgb.contentHash)
        }
    }

    /// Neutral input must come out the same neutral tone as the active sRGB Look, within a small
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
        let active = Dictionary(uniqueKeysWithValues: BundledLookLibrary.load().looks.map { ($0.id, $0) })
        for p3 in BundledLookLibrary.load(subdirectory: p3Directory).looks {
            let a = try render(try XCTUnwrap(active[p3.id]))
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
