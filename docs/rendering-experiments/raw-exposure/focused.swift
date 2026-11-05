import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO

// Fixed, full-resolution crops of the same pixels. This experiment does not alter Kromora.
let args = CommandLine.arguments
precondition(args.count == 4, "focused RAW OUTPUT_DIR PREVIEW_METRICS_JSON")
let source = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let previous = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [String:Any]
let records = previous["records"] as! [[String:Any]]
func median(_ mode: String, _ edr: Int) -> Double {
    let r = records.first { ($0["mode"] as? String) == mode && ($0["edr"] as? Int) == edr && ($0["ev"] as? Int) == -2 }!
    return (r["sampleMedianLinearY"] as! NSNumber).doubleValue
}
let target = median("B",0)
let name = source.deletingPathExtension().lastPathComponent
let dir = out.appendingPathComponent("renders/\(name)/focused")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
let display = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CIContext(options:[.workingColorSpace:linear, .cacheIntermediates:false])
struct Region { let name: String; let x: Double; let top: Double; let side: Double }
// Coordinates are fractions of the displayed image; side is fraction of width.
let regions: [Region] = name == "DSC01153" ? [
    Region(name:"white_flag",x:0.51,top:0.285,side:0.19),
    Region(name:"shadow_grass",x:0.17,top:0.78,side:0.19)
] : [Region(name:"bird_detail",x:0.35,top:0.23,side:0.19),
     Region(name:"bright_background",x:0.58,top:0.05,side:0.19)]
let configs: [(String,Float,Bool)] = [("raw",0,true),("rgb",0,false),("rgb_edr1",1,false)]
var result = [[String:Any]]()
var ref = [String:[Float]]()
for (label,edr,rawExposure) in configs {
 for region in regions {
  autoreleasepool {
    let filter = CIRAWFilter(imageURL:source)!
    filter.extendedDynamicRangeAmount = edr
    if rawExposure { filter.exposure = -2 }
    let image = filter.outputImage!
    let graph: CIImage
    if rawExposure { graph = image } else { let f = CIFilter.exposureAdjust(); f.inputImage = image; f.ev = -2; graph = f.outputImage! }
    let b = graph.extent.integral
    let side = max(1, Int((b.width * region.side).rounded()))
    let rect = CGRect(x:Int(b.minX + b.width*region.x), y:Int(b.maxY - b.height*region.top)-side, width:side,height:side)
    guard b.contains(rect) else { fatalError("crop outside image \(rect) \(b)") }
    var pixels = [Float](repeating:0,count:side*side*4)
    ctx.render(graph,toBitmap:&pixels,rowBytes:side*16,bounds:rect,format:.RGBAf,colorSpace:linear)
    let gain = rawExposure ? 1 : target / median("A",Int(edr))
    for i in stride(from:0,to:pixels.count,by:4) { for c in 0..<3 { pixels[i+c] *= Float(gain) } }
    var sum=0.0, sq=0.0, count=0, above=0, red=0.0, blue=0.0, edge=0.0, edgeN=0
    func lum(_ i:Int)->Double { 0.2289746*Double(pixels[i])+0.6917385*Double(pixels[i+1])+0.0792869*Double(pixels[i+2]) }
    for p in 0..<(side*side) {
      let i=p*4; let r=Double(pixels[i]), g=Double(pixels[i+1]), bl=Double(pixels[i+2])
      guard r.isFinite && g.isFinite && bl.isFinite else { continue }
      let y=lum(i); count += 1; sum += y; sq += y*y; red += r; blue += bl
      if max(r,g,bl) >= 1 { above += 1 }
      if p%side < side-1 { let v=lum(i+4); if v.isFinite { edge += abs(y-v); edgeN += 1 } }
    }
    var comparison:[String:Any] = [:]
    if label == "raw" { ref[region.name] = pixels }
    else if let original=ref[region.name] {
      var mse=0.0, maxDiff=0.0, n=0
      for i in stride(from:0,to:pixels.count,by:4) { for c in 0..<3 {
        let d=Double(pixels[i+c])-Double(original[i+c]); if d.isFinite { mse += d*d; maxDiff=max(maxDiff,abs(d)); n += 1 }
      }}
      comparison=["rmsRGBDifference":sqrt(mse/Double(max(n,1))),"maxRGBDifference":maxDiff]
    }
    let mean=sum/Double(max(count,1))
    let bytes = pixels.withUnsafeBytes { Data($0) }
    let crop=CIImage(bitmapData:bytes,bytesPerRow:side*16,size:CGSize(width:side,height:side),format:.RGBAf,colorSpace:linear)
    // Common +2 EV makes the aligned -2 EV crops readable, without individual auto tone mapping.
    let shown=CIFilter.exposureAdjust(); shown.inputImage=crop; shown.ev=2
    let cg=ctx.createCGImage(shown.outputImage!,from:crop.extent,format:.RGBA8,colorSpace:display)!
    let dest=CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(region.name)_\(label).png") as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(dest,cg,nil); precondition(CGImageDestinationFinalize(dest))
    result.append(["region":region.name,"mode":label,"rect":[rect.origin.x,rect.origin.y,rect.width,rect.height],"normalizationGain":gain,"count":count,
      "meanLuma":mean,"lumaStdDev":sqrt(max(0,sq/Double(max(count,1))-mean*mean)),"meanNeighborAbsDifference":edge/Double(max(edgeN,1)),
      "meanRed":red/Double(max(count,1)),"meanBlue":blue/Double(max(count,1)),"pixelsAnyChannelAtLeast1":above,"comparison":comparison,
      "decoderVersion":filter.decoderVersion.rawValue,"highlightRecovery":filter.isHighlightRecoveryEnabled,"gamutMapping":filter.isGamutMappingEnabled])
  }
  print("\(name) \(region.name) \(label)"); fflush(stdout)
 }
}
let obj:[String:Any]=["source":source.path,"match":"global preview median at -2 EV; A/EDR variant multiplied to match B/EDR0; visual output common +2 EV", "regions":result]
let data=try JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.sortedKeys])
try data.write(to:out.appendingPathComponent("metrics/\(name)-focused.json"),options:.atomic)
