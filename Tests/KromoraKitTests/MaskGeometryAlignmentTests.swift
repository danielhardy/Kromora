import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import KromoraKit

/// KRMA-1146: source-derived mattes (Subject and the other smart masks) are computed from the
/// oriented source, so they must follow the photograph through quarter-turn, flip, straighten,
/// perspective, and crop. The oracle is the photograph itself: a bright block sits at a known
/// place, the matte covers exactly that block, and a darkening local layer must therefore remove
/// every bright pixel wherever the geometry carried the block. Misregistered coverage leaves
/// bright pixels behind.
final class MaskGeometryAlignmentTests: TempDirectoryTestCase {
    private static let width = 96
    private static let height = 64
    /// The block in upper-left normalized coordinates of the oriented source.
    private static let block = CGRect(x: 0.10, y: 0.15, width: 0.25, height: 0.30)
    private static let margin = 0.03

    private func writeSource() throws -> ImageSource {
        let w = Self.width, h = Self.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let point = CGPoint(x: (Double(x) + 0.5) / Double(w), y: (Double(y) + 0.5) / Double(h))
                let value: UInt8 = Self.block.contains(point) ? 255 : 40
                let index = (y * w + x) * 4
                rgba[index] = value; rgba[index + 1] = value; rgba[index + 2] = value
            }
        }
        let image = try XCTUnwrap(rgba.withUnsafeMutableBytes { bytes -> CGImage? in
            CGContext(
                data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        })
        let url = tempDirectory.appendingPathComponent("block-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return ImageSource(url: url, nativeExtent: CGSize(width: w, height: h))
    }

    private var layer: LocalAdjustmentLayer {
        LocalAdjustmentLayer(
            id: UUID(), isInverted: false, amount: 1,
            components: [MaskComponent(
                mode: .replace, source: .semantic(SemanticMaskDefinition(target: .subject))
            )],
            adjustments: LocalAdjustments(exposure: -4)
        )
    }

    private func engine(for source: ImageSource) -> RenderEngine {
        RenderEngine(maskResolver: BlockMaskResolver(
            sourceFingerprint: source.cacheFingerprint,
            block: Self.block.insetBy(dx: -Self.margin, dy: -Self.margin)
        ))
    }

    private func luminance(of result: RenderResult) throws -> (width: Int, height: Int, values: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try Pixels.bytes(of: image)
        return (image.width, image.height, stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] })
    }

    private func brightCount(_ pixels: (width: Int, height: Int, values: [UInt8])) -> Int {
        pixels.values.filter { $0 > 150 }.count
    }

    private static let scenarios: [(name: String, rotation: ImageRotation, crop: CropAdjustments)] = [
        ("straighten", .zero, CropAdjustments(straightenAngle: 15)),
        ("quarter-turn", .clockwise90, CropAdjustments()),
        ("quarter-turn+straighten+crop", .counterClockwise90,
         CropAdjustments(normalizedRect: CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96),
                         straightenAngle: -10)),
        ("flip+perspective", .zero, CropAdjustments(flipHorizontal: true, verticalPerspective: 0.1)),
        ("crop only", .zero, CropAdjustments(normalizedRect: CGRect(x: 0, y: 0.4, width: 0.7, height: 0.6))),
        ("half+flipV+straighten", .half, CropAdjustments(straightenAngle: 8, flipVertical: true)),
    ]

    func testSubjectMatteStaysRegisteredToThePhotographUnderEveryGeometry() async throws {
        let source = try writeSource()
        let engine = engine(for: source)
        for scenario in Self.scenarios {
            let plain = EditDocument(crop: scenario.crop, rotation: scenario.rotation)
            var masked = plain
            masked.localAdjustments = [layer]
            for (quality, label) in [(RenderQuality.export, "export"), (.preview, "preview")] {
                let size: CGSize? = quality == .preview ? CGSize(width: 96, height: 96) : nil
                let base = try luminance(of: try await engine.render(RenderRequest(
                    source: source, document: plain, targetSize: size, quality: quality, output: .raster
                )))
                let adjusted = try luminance(of: try await engine.render(RenderRequest(
                    source: source, document: masked, targetSize: size, quality: quality, output: .raster
                )))
                XCTAssertGreaterThan(brightCount(base), 20,
                                     "\(scenario.name) \(label): the block must be visible in the fixture")
                XCTAssertEqual(base.width, adjusted.width)
                XCTAssertEqual(
                    brightCount(adjusted), 0,
                    "\(scenario.name) \(label): matte must cover the block wherever geometry put it"
                )
                // Pixels away from the block must not be touched by the layer.
                var untouched = 0, darkTotal = 0
                for (before, after) in zip(base.values, adjusted.values) where before < 100 {
                    darkTotal += 1
                    if abs(Int(before) - Int(after)) > 3 { untouched += 1 }
                }
                XCTAssertLessThan(
                    Double(untouched), 0.35 * Double(darkTotal),
                    "\(scenario.name) \(label): the layer must not spill far beyond the subject"
                )
            }
        }
    }

    func testOverlayCoverageFollowsTheBlockThroughGeometry() async throws {
        let source = try writeSource()
        let engine = engine(for: source)
        for scenario in Self.scenarios where scenario.crop.normalizedRect == nil {
            // The overlay covers the whole post-geometry frame, so compare it with the uncropped photo.
            let plain = EditDocument(crop: scenario.crop, rotation: scenario.rotation)
            let photo = try luminance(of: try await engine.render(RenderRequest(
                source: source, document: plain, quality: .export, output: .raster
            )))
            let layer = self.layer
            let request = MaskOverlayRequest(
                source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
                targetSize: PixelDimensions(width: photo.width, height: photo.height),
                geometry: MaskSourceGeometry(
                    nativeSize: source.nativeExtent, rotation: scenario.rotation, crop: scenario.crop),
                style: MaskOverlayStyle(inspection: .grayscale, red: 1, green: 0, blue: 0)
            )
            let rendered = await engine.makeMaskOverlayImage(request)
            let overlay = try XCTUnwrap(rendered, scenario.name)
            XCTAssertEqual(overlay.width, photo.width)
            XCTAssertEqual(overlay.height, photo.height)
            let coverage = try Pixels.bytes(of: overlay)
            var bright = 0, missed = 0, covered = 0
            for index in photo.values.indices {
                let isCovered = coverage[index * 4] > 128
                if isCovered { covered += 1 }
                if photo.values[index] > 200 {
                    bright += 1
                    if !isCovered { missed += 1 }
                }
            }
            XCTAssertGreaterThan(bright, 20, scenario.name)
            XCTAssertEqual(missed, 0, "\(scenario.name): overlay left photograph pixels of the subject uncovered")
            XCTAssertLessThan(Double(covered), 3.0 * Double(bright),
                              "\(scenario.name): overlay coverage must stay near the subject")
        }
    }

    func testMaskAddedBeforeGeometrySurvivesSavedReopenAndGeometryReset() async throws {
        let source = try writeSource()
        let engine = engine(for: source)
        var maskFirst = EditDocument(localAdjustments: [layer])
        maskFirst.rotation = .counterClockwise90
        maskFirst.crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96),
            straightenAngle: -10
        )

        // EditDocument is the durable recipe persisted by the editor; a reopened recipe must
        // resolve source-derived pixels in the same frame even though its matte cache is new.
        let saved = try JSONEncoder().encode(maskFirst)
        let reopened = try JSONDecoder().decode(EditDocument.self, from: saved)
        XCTAssertEqual(reopened, maskFirst)

        for (quality, label) in [(RenderQuality.export, "export"), (.preview, "preview")] {
            let result = try await engine.render(RenderRequest(
                source: source, document: reopened,
                targetSize: quality == .preview ? CGSize(width: 96, height: 96) : nil,
                quality: quality, output: .raster
            ))
            XCTAssertEqual(
                brightCount(try luminance(of: result)), 0,
                "reopened \(label): the saved mask must follow the block through rotation, crop, and straighten"
            )
        }

        var reset = reopened
        reset.rotation = .zero
        reset.crop = .neutral
        let resetResult = try await engine.render(RenderRequest(
            source: source, document: reset, quality: .export, output: .raster
        ))
        XCTAssertEqual(
            brightCount(try luminance(of: resetResult)), 0,
            "reset: the mask must remain registered after geometry is cleared"
        )
    }

    func testCroppedOverlayCoverageMatchesTheVisiblePhotograph() async throws {
        let source = try writeSource()
        let engine = engine(for: source)
        let geometries: [(ImageRotation, CropAdjustments)] = [
            (.zero, CropAdjustments(
                normalizedRect: CGRect(x: 0.08, y: 0.12, width: 0.82, height: 0.76)
            )),
            (.counterClockwise90, CropAdjustments(
                normalizedRect: CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96),
                straightenAngle: -10
            )),
        ]

        for (rotation, crop) in geometries {
            let fullCrop = CropAdjustments(
                straightenAngle: crop.straightenAngle,
                flipHorizontal: crop.flipHorizontal,
                flipVertical: crop.flipVertical,
                verticalPerspective: crop.verticalPerspective,
                horizontalPerspective: crop.horizontalPerspective
            )
            let fullDocument = EditDocument(crop: fullCrop, rotation: rotation)
            let croppedDocument = EditDocument(crop: crop, rotation: rotation)
            let fullPhoto = try luminance(of: try await engine.render(RenderRequest(
                source: source, document: fullDocument, quality: .export, output: .raster
            )))
            let croppedPhoto = try luminance(of: try await engine.render(RenderRequest(
                source: source, document: croppedDocument, quality: .export, output: .raster
            )))
            let layer = self.layer
            let resolved = await engine.makeMaskOverlayImage(MaskOverlayRequest(
                source: source, layers: [layer], selectedLayerID: layer.id, soloLayerID: nil,
                targetSize: PixelDimensions(width: fullPhoto.width, height: fullPhoto.height),
                geometry: MaskSourceGeometry(
                    nativeSize: source.nativeExtent, rotation: rotation, crop: crop),
                style: MaskOverlayStyle(inspection: .grayscale, red: 1, green: 0, blue: 0)
            ))
            let overlay = try XCTUnwrap(resolved)
            let coverage = try Pixels.bytes(of: overlay)
            let rect = try XCTUnwrap(crop.normalizedRect)
            let top = 1 - rect.maxY
            var bright = 0, missed = 0, visibleCoverage = 0
            for y in 0..<croppedPhoto.height {
                for x in 0..<croppedPhoto.width {
                    let sourceX = rect.minX + (CGFloat(x) + 0.5) / CGFloat(croppedPhoto.width) * rect.width
                    let sourceY = top + (CGFloat(y) + 0.5) / CGFloat(croppedPhoto.height) * rect.height
                    let overlayX = min(overlay.width - 1, max(0, Int(sourceX * CGFloat(overlay.width))))
                    let overlayY = min(overlay.height - 1, max(0, Int(sourceY * CGFloat(overlay.height))))
                    let isCovered = coverage[(overlayY * overlay.width + overlayX) * 4] > 128
                    let photoValue = croppedPhoto.values[y * croppedPhoto.width + x]
                    if photoValue > 200 {
                        bright += 1
                        if !isCovered { missed += 1 }
                    }
                    if isCovered { visibleCoverage += 1 }
                }
            }

            XCTAssertGreaterThan(bright, 20)
            XCTAssertEqual(missed, 0, "the crop-clipped overlay must cover every visible subject pixel")
            XCTAssertLessThan(Double(visibleCoverage), 3.0 * Double(bright))
        }
    }

    func testIdentityGeometryKeepsTheUnwarpedFrame() {
        let geometry = MaskSourceGeometry(
            nativeSize: CGSize(width: 96, height: 64), rotation: .zero, crop: CropAdjustments()
        )
        XCTAssertTrue(geometry.isIdentity)
        let turned = MaskSourceGeometry(
            nativeSize: CGSize(width: 96, height: 64), rotation: .clockwise90, crop: CropAdjustments()
        )
        XCTAssertEqual(
            turned.sourceFrame(forOutput: CGRect(x: 0, y: 0, width: 64, height: 96)),
            CGRect(x: 0, y: 0, width: 96, height: 64),
            "a quarter-turn resolves the matte over the unrotated source frame"
        )
    }
}

/// Returns a hard-edged raster for the requested frame with `block` (upper-left normalized) set.
private struct BlockMaskResolver: LocalMaskResolving {
    let sourceFingerprint: String
    let block: CGRect

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let w = request.targetSize.width, h = request.targetSize.height
        let values = (0..<h).flatMap { y in
            (0..<w).map { x -> Float in
                block.contains(CGPoint(x: (Double(x) + 0.5) / Double(w),
                                       y: (Double(y) + 0.5) / Double(h))) ? 1 : 0
            }
        }
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint, definitionHash: request.definitionHash,
            targetSize: request.targetSize, quality: request.quality,
            descriptor: .raster(try NormalizedMask(size: request.targetSize, values: values))
        )
    }
}
