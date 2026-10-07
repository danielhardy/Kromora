import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

@MainActor
final class FilmstripThumbnailTests: TempDirectoryTestCase {
    private enum ThumbnailState: CaseIterable {
        case original, edited, stale, fallback
    }

    func testSquareCellsStayFilledAcrossThumbnailStatesAndAppearances() throws {
        let settings = KromoraSettings(
            preferences: makeTestUserDefaults(),
            userLookFolderURL: tempDirectory.appendingPathComponent("looks", isDirectory: true)
        )
        settings.showPhotoNames = false

        for size in [CGSize(width: 160, height: 80), CGSize(width: 80, height: 160)] {
            let thumbnail = try makeRedThumbnail(size: size)
            for appearance in [ColorScheme.light, .dark] {
                let item = ImageCollection.Item(
                    asset: PhotoAsset(data: Data([1]), filename: "test.png"),
                    thumbnail: thumbnail
                )
                for state in ThumbnailState.allCases {
                    switch state {
                    case .original:
                        break
                    case .edited:
                        item.applyEditedThumbnail(thumbnail, revision: "edited")
                    case .stale:
                        item.markEditedThumbnailStale()
                    case .fallback:
                        item.applyEditedThumbnail(nil, revision: "failed")
                    }

                    let renderer = ImageRenderer(content: FilmstripThumbnail(
                        item: item, settings: settings, isSelected: false
                    ).environment(\.colorScheme, appearance))
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.cgImage)
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let label = "\(size), \(appearance), \(state)"
                    XCTAssertEqual(image.width, 96, label)
                    XCTAssertEqual(image.height, 96, label)

                    // Midpoints of all four edges must contain photo pixels: fitting a
                    // nonsquare source leaves two of these transparent. Corners stay clipped.
                    for point in [(1, 48), (94, 48), (48, 1), (48, 94)] {
                        let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1))
                        let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
                        XCTAssertGreaterThan(rgb.alphaComponent, 0.99, label)
                        XCTAssertGreaterThan(rgb.redComponent, rgb.greenComponent + 0.5, label)
                        XCTAssertGreaterThan(rgb.redComponent, rgb.blueComponent + 0.5, label)
                    }
                    for point in [(0, 0), (95, 0), (0, 95), (95, 95)] {
                        let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1))
                        XCTAssertLessThan(color.alphaComponent, 0.01, label)
                    }
                }
            }
        }
    }

    private func makeRedThumbnail(size: CGSize) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: size)
    }
}
