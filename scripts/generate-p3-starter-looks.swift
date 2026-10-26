#!/usr/bin/env swift
// Regenerates the active Display P3 starter Looks (Sources/KromoraKit/Resources/StarterLooks) from the
// sRGB source Looks (scripts/starter-looks-srgb, not bundled), which are the defined source
// parameters: a 3x3x3 sRGB control lattice per Look.
//
// Usage:
//   swift scripts/generate-p3-starter-looks.swift generate            # write the P3 cubes + manifest
//   swift scripts/generate-p3-starter-looks.swift review <out.png>    # render an A/B contact sheet
//
// Procedure (deterministic; no ColorSync dependence, so output is reproducible):
//   for each node of a 17^3 lattice in Display P3 (encoded):
//     decode P3 -> linear P3 -> linear sRGB -> extended-sRGB encoding (sign-preserving)
//     evaluate the source Look (trilinear over its control lattice, linearly extrapolated and
//       bounded just outside [0, 1] so wide-gamut inputs get a continuation, not a clamp)
//     decode -> linear sRGB -> linear P3 -> P3 encoding, clamp to [0, 1]
// The table values are therefore P3 coordinates sampled on a P3 lattice, not relabelled sRGB values.
import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDir = root.appendingPathComponent("scripts/starter-looks-srgb")
let outputDir = root.appendingPathComponent("Sources/KromoraKit/Resources/StarterLooks")
let latticeSize = 17
let extrapolationBound: Double = 0.5   // extended-sRGB coordinates are bounded to [-0.5, 1.5]

typealias V3 = SIMD3<Double>

func decode(_ v: Double) -> Double {   // sRGB / P3 transfer function (identical), sign-preserving
    let a = abs(v)
    let l = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
    return v < 0 ? -l : l
}
func encode(_ v: Double) -> Double {
    let a = abs(v)
    let e = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
    return v < 0 ? -e : e
}
// Linear Display P3 -> linear sRGB and back (D65 primaries).
let p3ToSRGB: [[Double]] = [
    [ 1.2249401763, -0.2249401763,  0.0000000000],
    [-0.0420569547,  1.0420569547,  0.0000000000],
    [-0.0196375546, -0.0786360456,  1.0982736002],
]
let sRGBToP3: [[Double]] = [
    [0.8224621, 0.1775380, 0.0000000],
    [0.0331941, 0.9668058, 0.0000000],
    [0.0170827, 0.0723974, 0.9105199],
]
func mul(_ m: [[Double]], _ v: V3) -> V3 {
    V3(m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
       m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
       m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
}
func map(_ v: V3, _ f: (Double) -> Double) -> V3 { V3(f(v.x), f(v.y), f(v.z)) }

struct SourceLook {
    let size: Int
    let table: [V3]   // R fastest
    func sample(_ c: V3) -> V3 {
        let n = Double(size - 1)
        let p = map(c) { min(max($0, -extrapolationBound), 1 + extrapolationBound) * n }
        var i0 = [0, 0, 0]; var t = [0.0, 0.0, 0.0]
        for a in 0..<3 {
            let base = min(max(Int(floor(p[a])), 0), size - 2)
            i0[a] = base; t[a] = p[a] - Double(base)   // t outside [0, 1] extrapolates linearly
        }
        func at(_ r: Int, _ g: Int, _ b: Int) -> V3 { table[(b * size + g) * size + r] }
        var out = V3.zero
        for dr in 0...1 { for dg in 0...1 { for db in 0...1 {
            let w = (dr == 1 ? t[0] : 1 - t[0]) * (dg == 1 ? t[1] : 1 - t[1]) * (db == 1 ? t[2] : 1 - t[2])
            out += w * at(i0[0] + dr, i0[1] + dg, i0[2] + db)
        } } }
        return out
    }
}

func parseCube(_ url: URL) -> SourceLook {
    let text = try! String(contentsOf: url, encoding: .utf8)
    var size = 0; var rows: [V3] = []
    for line in text.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("LUT_3D_SIZE") { size = Int(t.split(separator: " ")[1])! }
        else if let r = Optional(t.split(separator: " ").compactMap { Double($0) }), r.count == 3, !t.hasPrefix("#") {
            rows.append(V3(r[0], r[1], r[2]))
        }
    }
    precondition(size >= 2 && rows.count == size * size * size, "bad source cube \(url.lastPathComponent)")
    return SourceLook(size: size, table: rows)
}

func p3Cube(from source: SourceLook) -> [V3] {
    var cube: [V3] = []
    let n = Double(latticeSize - 1)
    for b in 0..<latticeSize { for g in 0..<latticeSize { for r in 0..<latticeSize {
        let p3Encoded = V3(Double(r) / n, Double(g) / n, Double(b) / n)
        let srgbEncoded = map(mul(p3ToSRGB, map(p3Encoded, decode)), encode)
        let graded = source.sample(srgbEncoded)
        let back = map(mul(sRGBToP3, map(graded, decode)), encode)
        cube.append(map(back) { min(max($0, 0), 1) })
    } } }
    return cube
}

func title(of url: URL) -> String {
    let text = try! String(contentsOf: url, encoding: .utf8)
    for line in text.split(separator: "\n") where line.hasPrefix("TITLE") {
        return line.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }
    return url.deletingPathExtension().lastPathComponent
}

func cubeText(name: String, cube: [V3]) -> String {
    var lines = [
        "# Original Kromora starter Look: \(name) (Display P3)",
        "# Generated by scripts/generate-p3-starter-looks.swift from the sRGB starter Look of the same name.",
        "# KROMORA_AUTHORING_SPACE: displayP3",
        "TITLE \"\(name)\"",
        "LUT_3D_SIZE \(latticeSize)",
    ]
    for v in cube { lines.append(String(format: "%.6f %.6f %.6f", v.x, v.y, v.z)) }
    return lines.joined(separator: "\n") + "\n"
}

func cubeFiles() -> [URL] {
    try! FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "cube" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func generate() throws {
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    for url in cubeFiles() {
        let cube = p3Cube(from: parseCube(url))
        try cubeText(name: title(of: url), cube: cube)
            .write(to: outputDir.appendingPathComponent(url.lastPathComponent), atomically: true, encoding: .utf8)
    }
    var manifest = try JSONSerialization.jsonObject(
        with: Data(contentsOf: sourceDir.appendingPathComponent("manifest.json"))) as! [String: Any]
    var looks = manifest["looks"] as! [[String: Any]]
    for index in looks.indices {
        looks[index]["source"] = "Original in-house procedural asset; authored for Kromora. Display P3 regeneration: "
            + "scripts/generate-p3-starter-looks.swift resamples the sRGB control lattice of the same Look onto a "
            + "\(latticeSize)^3 Display P3 lattice (colour-managed conversion, not a relabelled sRGB table)."
        var approval = looks[index]["approval"] as! [String: Any]
        approval["recordID"] = "KRMA-1121-P3-STARTER-2026-10-25"
        approval["reviewer"] = "KRMA-1117 visual review (A/B contact sheet via `review`); activated by KRMA-1121"
        approval["approvedAt"] = "2026-10-25"
        approval["notes"] = "Display P3 authoring space (KROMORA_AUTHORING_SPACE: displayP3). Appearance on "
            + "in-gamut colours reviewed against the sRGB source Look via `review`; no camera profile or commercial emulation used."
        looks[index]["approval"] = approval
    }
    // Looks authored directly in P3 (for example the slide family, generated by the test-target
    // SlideLookGenerator) have no sRGB source: carry their existing entries and cubes forward.
    let sourceIDs = Set(looks.compactMap { $0["id"] as? String })
    if let existing = try? JSONSerialization.jsonObject(
        with: Data(contentsOf: outputDir.appendingPathComponent("manifest.json"))) as? [String: Any],
        let existingLooks = existing["looks"] as? [[String: Any]] {
        looks += existingLooks.filter { !sourceIDs.contains($0["id"] as? String ?? "") }
    }
    manifest["looks"] = looks
    manifest["acknowledgement"] = (manifest["acknowledgement"] as! String)
        + " The bundled set is authored in Display P3."
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try (data + Data("\n".utf8)).write(to: outputDir.appendingPathComponent("manifest.json"))
}

// MARK: - Review contact sheet

func review(to output: URL) throws {
    let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!])
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
    // Patches defined in sRGB: neutral ramp, primaries/secondaries, skin, sky, foliage.
    var patches: [V3] = (0..<8).map { V3(repeating: Double($0) / 7) }
    patches += [V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1), V3(1, 1, 0), V3(0, 1, 1), V3(1, 0, 1),
                V3(0.85, 0.65, 0.55), V3(0.45, 0.65, 0.9), V3(0.3, 0.5, 0.25), V3(0.9, 0.5, 0.2)]
    let columns = patches.count
    func strip(_ colors: [V3], space: CGColorSpace) -> CIImage {
        var px = [Float](); for c in colors { px += [Float(c.x), Float(c.y), Float(c.z), 1] }
        return CIImage(bitmapData: Data(bytes: px, count: px.count * 4), bytesPerRow: px.count * 4,
                       size: CGSize(width: colors.count, height: 1), format: .RGBAf, colorSpace: space)
    }
    func cube(_ url: URL, space: CGColorSpace) -> CIFilter {
        let look = parseCube(url)
        var floats = [Float](); for v in look.table { floats += [Float(v.x), Float(v.y), Float(v.z), 1] }
        let f = CIFilter(name: "CIColorCubeWithColorSpace")!
        f.setValue(look.size, forKey: "inputCubeDimension")
        f.setValue(Data(bytes: floats, count: floats.count * 4), forKey: "inputCubeData")
        f.setValue(space, forKey: "inputColorSpace"); return f
    }
    let urls = cubeFiles()
    let cell = 28, rowHeight = 28
    // Rows per Look: sRGB Look rendered to sRGB (top), P3 Look rendered to sRGB (bottom).
    let rows = urls.count * 2 + 1
    var canvas = [UInt8](repeating: 255, count: columns * cell * rows * rowHeight * 4)
    var report = ""
    func draw(_ image: CIImage, row: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: columns * 4)
        context.render(image, toBitmap: &buf, rowBytes: columns * 4, bounds: CGRect(x: 0, y: 0, width: columns, height: 1),
                       format: .RGBA8, colorSpace: sRGB)
        for y in 0..<rowHeight { for x in 0..<columns * cell {
            let s = (x / cell) * 4; let d = ((row * rowHeight + y) * columns * cell + x) * 4
            canvas[d] = buf[s]; canvas[d + 1] = buf[s + 1]; canvas[d + 2] = buf[s + 2]; canvas[d + 3] = 255
        } }
        return buf
    }
    let input = strip(patches, space: sRGB)
    _ = draw(input, row: 0)
    for (i, url) in urls.enumerated() {
        let a = cube(url, space: sRGB); a.setValue(input, forKey: kCIInputImageKey)
        let b = cube(outputDir.appendingPathComponent(url.lastPathComponent), space: p3)
        b.setValue(input, forKey: kCIInputImageKey)
        let ra = draw(a.outputImage!, row: 1 + i * 2)
        let rb = draw(b.outputImage!, row: 2 + i * 2)
        var worst = 0
        for k in 0..<columns { for c in 0..<3 { worst = max(worst, abs(Int(ra[k * 4 + c]) - Int(rb[k * 4 + c]))) } }
        report += "\(url.deletingPathExtension().lastPathComponent): max 8-bit sRGB difference \(worst)\n"
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &canvas, width: columns * cell, height: rows * rowHeight, bitsPerComponent: 8,
                        bytesPerRow: columns * cell * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
    print(report, terminator: "")
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "generate": try generate()
case "review" where args.count > 2: try review(to: URL(fileURLWithPath: args[2]))
default: print("usage: generate | review <out.png>"); exit(2)
}
