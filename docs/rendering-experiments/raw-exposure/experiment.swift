import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import CoreGraphics
import AppKit
import Darwin

// Standalone diagnostic. This intentionally duplicates the small, neutral Kromora graph:
// CIRAWFilter -> optional CIExposureAdjust -> extended-linear Display P3 CIContext.
// It does not import or modify the application's document, caches, or UI.
let args = CommandLine.arguments
if args.count < 3 { fputs("usage: experiment RAW OUTPUT_DIR [max_dimension]\n", stderr); exit(2) }
let url = URL(fileURLWithPath: args[1]), root = URL(fileURLWithPath: args[2])
let maxDimension = args.count > 3 ? (Double(args[3]) ?? 1000) : 1000
let name = url.deletingPathExtension().lastPathComponent
let out = root.appendingPathComponent("renders/\(name)")
let metricDir = root.appendingPathComponent("metrics")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: metricDir, withIntermediateDirectories: true)
let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
let display = CGColorSpace(name: CGColorSpace.displayP3)!
let context = CIContext(options: [.workingColorSpace: linear, .cacheIntermediates: false])
let evs: [Float] = [-3, -2, -1, 0, 1, 2]
let modes = ["A", "B", "C", "D"]
let start = Date()
func seconds(_ t: Date) -> Double { Date().timeIntervalSince(t) }
func settings(_ f: CIRAWFilter) -> [String: Any] {
    ["decoderVersion": f.decoderVersion.rawValue, "supportedDecoderVersions": f.supportedDecoderVersions.map(\.rawValue),
     "exposure": f.exposure, "baselineExposure": f.baselineExposure, "shadowBias": f.shadowBias,
     "boost": f.boostAmount, "boostShadow": f.boostShadowAmount, "edr": f.extendedDynamicRangeAmount,
     "gamutMapping": f.isGamutMappingEnabled, "highlightRecoverySupported": f.isHighlightRecoverySupported,
     "highlightRecoveryEnabled": f.isHighlightRecoveryEnabled, "lensSupported": f.isLensCorrectionSupported,
     "lensEnabled": f.isLensCorrectionEnabled, "temperature": f.neutralTemperature, "tint": f.neutralTint,
     "sharpness": f.sharpnessAmount, "contrast": f.contrastAmount, "detail": f.detailAmount,
     "luminanceNR": f.luminanceNoiseReductionAmount, "colorNR": f.colorNoiseReductionAmount,
     "moire": f.moireReductionAmount, "localToneMap": f.localToneMapAmount,
     "nativeWidth": f.nativeSize.width, "nativeHeight": f.nativeSize.height, "scaleFactor": f.scaleFactor]
}
func savePNG(_ image: CIImage, _ path: URL) throws {
    guard let cg = context.createCGImage(image, from: image.extent.integral, format: .RGBA8, colorSpace: display),
          let dest = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil) else { throw NSError(domain: "png", code: 1) }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "png", code: 2) }
}
func histogram(_ pixels: [Float], _ w: Int, _ h: Int) -> [String: Any] {
    var boundary = [Int](repeating: 0, count: 3), negative = [Int](repeating: 0, count: 3)
    var nonfinite = 0, nan = 0, infinite = 0, anyBoundary = 0, outOfGamut = 0, highlight = 0
    var bins = Set<Int>(), highSum = 0.0, highSq = 0.0, shadowSum = 0.0, shadowSq = 0.0, shadowCount = 0
    var highChromR = 0.0, highChromB = 0.0, edgeSum = 0.0, edgeCount = 0
    func lum(_ i: Int) -> Double { 0.2289746 * Double(pixels[i]) + 0.6917385 * Double(pixels[i+1]) + 0.0792869 * Double(pixels[i+2]) }
    for p in 0..<(w*h) {
        let i = p*4, rgb = [pixels[i], pixels[i+1], pixels[i+2]]
        for x in rgb { if x.isNaN { nan += 1 }; if x.isInfinite { infinite += 1 } }
        guard rgb.allSatisfy(\.isFinite) else { nonfinite += 1; continue }
        for c in 0..<3 { if rgb[c] >= 1 { boundary[c] += 1 }; if rgb[c] < 0 { negative[c] += 1 } }
        if rgb.contains(where: {$0 >= 1}) { anyBoundary += 1 }
        if rgb.contains(where: {$0 < 0 || $0 > 1}) { outOfGamut += 1 }
        let y = lum(i)
        if y >= 0.75 && y < 1.0 {
            highlight += 1; bins.insert(Int((y * 4096).rounded(.down)))
            highSum += y; highSq += y*y
            let s = Double(rgb[0] + rgb[1] + rgb[2]); if s > 0 { highChromR += Double(rgb[0])/s; highChromB += Double(rgb[2])/s }
            if p % w != w-1 { let j = i+4; let n = lum(j); if n.isFinite && n >= 0.75 && n < 1 { edgeSum += abs(y-n); edgeCount += 1 } }
        }
        if y >= 0 && y < 0.05 { shadowCount += 1; shadowSum += y; shadowSq += y*y }
    }
    func sd(_ sum: Double, _ sq: Double, _ n: Int) -> Double { n > 0 ? sqrt(max(0, sq/Double(n) - pow(sum/Double(n),2))) : 0 }
    return ["pixels":w*h, "channelsAtOrAboveOne":boundary, "pixelsAnyChannelAtOrAboveOne":anyBoundary,
            "percentAnyChannelAtOrAboveOne":100*Double(anyBoundary)/Double(w*h), "pixelsOutsideP3UnitCube":outOfGamut,
            "negativeChannels":negative, "pixelsNonfinite":nonfinite, "nanChannels":nan, "infiniteChannels":infinite,
            "highlightPixelCountY075to1":highlight, "highlightOccupiedBins4096":bins.count,
            "highlightLumaStdDev":sd(highSum,highSq,highlight), "highlightNeighborAbsDifference":edgeCount > 0 ? edgeSum/Double(edgeCount) : 0,
            "highlightMeanRedChromaticity":highlight > 0 ? highChromR/Double(highlight) : 0,
            "highlightMeanBlueChromaticity":highlight > 0 ? highChromB/Double(highlight) : 0,
            "shadowPixelsY0to005":shadowCount, "shadowLumaStdDev":sd(shadowSum,shadowSq,shadowCount)]
}
var records = [[String: Any]]()
var referencePixels = [String: [Float]]()
var comparisons = [[String: Any]]()
var targetMedians = [String: Double]()
for edr: Float in [0, 1] {
 for mode in modes {
  for ev in evs {
    let t = Date()
    guard let f = CIRAWFilter(imageURL: url) else { fputs("Not a decodable RAW: \(url.path)\n", stderr); exit(1) }
    if mode == "C" || mode == "D" { f.boostAmount = 0 }
    f.extendedDynamicRangeAmount = edr
    if mode == "B" || mode == "D" { f.exposure = ev }
    f.scaleFactor = Float(min(1, maxDimension / max(f.nativeSize.width, f.nativeSize.height)))
    let decoderSettings = settings(f)
    guard let developed = f.outputImage else { fputs("Decoder output unavailable: \(mode) \(ev)\n", stderr); exit(1) }
    let graph: CIImage
    if mode == "A" || mode == "C" { let a = CIFilter.exposureAdjust(); a.inputImage = developed; a.ev = ev; graph = a.outputImage! } else { graph = developed }
    let rect = graph.extent.integral, w = Int(rect.width), h = Int(rect.height)
    guard w > 0 && h > 0 && w*h < 100_000_000 else { fatalError("invalid extent") }
    var pixels = [Float](repeating: 0, count: w*h*4)
    let beforeRender = Date()
    context.render(graph, toBitmap: &pixels, rowBytes: w*16, bounds: rect, format: .RGBAf, colorSpace: linear)
    let renderSeconds = seconds(beforeRender), totalSeconds = seconds(t)
    let pairKey = "\(Int(edr))_\(Int(ev))_\((mode == "A" || mode == "B") ? "AB" : "CD")"
    if mode == "A" || mode == "C" { referencePixels[pairKey] = pixels }
    else if let reference = referencePixels.removeValue(forKey: pairKey) {
        var maxDiff = 0.0, squared = 0.0, changed = 0, finiteCount = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            for c in 0..<3 {
                let a = Double(reference[i+c]), b = Double(pixels[i+c])
                if a.isFinite && b.isFinite { let d = abs(a-b); maxDiff = max(maxDiff,d); squared += d*d; finiteCount += 1; if d > 1e-6 { changed += 1 } }
            }
        }
        comparisons.append(["pair": pairKey, "maxAbsoluteChannelDifference": maxDiff,
                            "rmsChannelDifference": finiteCount > 0 ? sqrt(squared/Double(finiteCount)) : 0,
                            "channelsDifferingOver1e-6": changed, "finiteChannels":finiteCount])
    }
    let id = "\(mode)_ev\(Int(ev))_edr\(Int(edr))"
    try savePNG(graph, out.appendingPathComponent("\(id).png"))
    // Use one recorded global gain to align each frame's median with A at the same EV/EDR.
    // This is only a display aid; all measurements above use unnormalized float pixels.
    var luminances = [Double](); luminances.reserveCapacity(w*h/16+1)
    for p in stride(from:0, to:w*h, by:16) {
        let i = p*4, y = 0.2289746*Double(pixels[i]) + 0.6917385*Double(pixels[i+1]) + 0.0792869*Double(pixels[i+2])
        if y.isFinite && y > 0 { luminances.append(y) }
    }
    luminances.sort(); let median = luminances.isEmpty ? 0 : luminances[luminances.count/2]
    let medianKey = "\(Int(edr))_\(Int(ev))"
    if mode == "A" { targetMedians[medianKey] = median }
    let target = targetMedians[medianKey] ?? median
    let gain = (median > 0 && target > 0) ? target/median : 1
    let normalized = CIFilter.exposureAdjust(); normalized.inputImage = graph; normalized.ev = Float(log2(gain))
    try savePNG(normalized.outputImage!, out.appendingPathComponent("matched_\(id).png"))
    var rec = histogram(pixels,w,h)
    rec["mode"] = mode; rec["ev"] = ev; rec["edr"] = edr; rec["width"] = w; rec["height"] = h
    rec["sampleMedianLinearY"] = median; rec["displayMatchGain"] = gain; rec["renderSeconds"] = renderSeconds; rec["constructAndRenderSeconds"] = totalSeconds; rec["decoder"] = decoderSettings
    records.append(rec)
    print("\(name) \(id) \(String(format: "%.3f", totalSeconds))s", terminator: "\n"); fflush(stdout)
  }
 }
}
var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
let result: [String: Any] = ["source":url.path, "sourceBytes": (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
 "generatedAt":ISO8601DateFormatter().string(from: start), "operatingSystem":ProcessInfo.processInfo.operatingSystemVersionString,
 "workingSpace":"extended-linear Display P3", "measurement":"RGBAf float, no output tone map", "display":"Display P3 RGBA8, fixed transform, no normalization",
 "maxDimension":maxDimension, "peakRSSBytes":usage.ru_maxrss, "comparisons":comparisons, "records":records]
let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
try json.write(to: metricDir.appendingPathComponent("\(name).json"), options: .atomic)
