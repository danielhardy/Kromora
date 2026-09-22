import XCTest
import CoreImage
@testable import KromoraKit

/// Phase 2's render-boundary ship gate: live and one-shot Core Image contexts are centralized in
/// RenderEngineResources/RenderEngine. The other render-adjacent owners use the shared factory,
/// which keeps context construction auditable and prevents a new ad-hoc context from bypassing the
/// engine resource policy.
///
/// **This reads source text, and that is deliberate.** A `CIContext` leaves no observable trace —
/// two of them render identically, cost twice the memory, and no runtime assertion can tell them
/// apart. `ImageProcessor` held the second one for five migration steps without a single test
/// noticing. The only way to keep it from coming back is to look.
final class RenderStackTests: XCTestCase {

    /// The module's source directory, found relative to this file rather than to the working
    /// directory — `swift test` and Xcode disagree about the latter.
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)          // Tests/KromoraKitTests/RenderStackTests.swift
            .deletingLastPathComponent()          // Tests/KromoraKitTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // package root
            .appendingPathComponent("Sources/KromoraKit")
    }

    private func swiftFiles() throws -> [URL] {
        let root = Self.sourcesDirectory
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not enumerate \(root.path)"
        )
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    /// Every file that constructs a `CIContext`, by name.
    private func filesConstructingAContext() throws -> Set<String> {
        var found: Set<String> = []
        for url in try swiftFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Skip the doc comments that *mention* `CIContext(` — only real constructions count.
            let constructs = text.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { return false }
                return trimmed.contains("CIContext(")
            }
            if constructs { found.insert(url.lastPathComponent) }
        }
        return found
    }

    func testOnlyNamedTypesInTheModuleOwnACIContext() throws {
        let files = try swiftFiles()
        XCTAssertGreaterThan(files.count, 20,
                             "expected to scan the whole module; found \(files.count) files under \(Self.sourcesDirectory.path)")

        let owners = try filesConstructingAContext()
        XCTAssertEqual(
            owners,
            ["RenderEngine.swift", "RenderEngineResources.swift"],
            """
            RenderEngineResources owns shared and one-shot context construction; RenderEngine owns \
            the live render context. Other render-adjacent code must use those boundaries.
            """
        )
    }

    /// Thumbnails were the other half of Step 7, and they deliberately did **not** move onto the
    /// engine: `CGImageSource` reads a file's embedded preview, so a 30 MB DNG thumbnails in
    /// milliseconds without being demosaiced. Routing them through the actor would queue every
    /// filmstrip tile behind the preview render for no gain.
    ///
    /// Pinned as source text for the same reason as above — a `CIImage` creeping in here would
    /// change the cost profile and nothing else.
    func testThumbnailsStayOutOfCoreImage() throws {
        let url = Self.sourcesDirectory.appendingPathComponent("Models/Thumbnails.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let code = text.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///")
        }.joined(separator: "\n")

        for symbol in ["CIContext", "CIImage", "CIFilter", "RenderEngine"] {
            XCTAssertFalse(code.contains(symbol),
                           "\(symbol) in Thumbnails would put the filmstrip on the render path")
        }
        XCTAssertTrue(code.contains("CGImageSource"), "thumbnails should still read embedded previews")
    }
}
