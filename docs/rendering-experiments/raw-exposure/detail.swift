import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO

// Detail probe for DSC00324; same 1140px square for all variants, full decoder scale.
let args=CommandLine.arguments
precondition(args.count == 3, "detail RAW OUTPUT_DIR")
let source=URL(fileURLWithPath:args[1]), root=URL(fileURLWithPath:args[2])
let out=root.appendingPathComponent("renders/DSC00324/focused")
let linear=CGColorSpace(name:CGColorSpace.extendedLinearDisplayP3)!, display=CGColorSpace(name:CGColorSpace.displayP3)!
let context=CIContext(options:[.workingColorSpace:linear,.cacheIntermediates:false])
let modes=["default","raw_nr0","raw_nr1","rgb_nr","raw_sharp0","raw_sharp1","rgb_sharp"]
var items=[[String:Any]](), reference:[Float]? = nil
for mode in modes {
 autoreleasepool {
  let raw=CIRAWFilter(imageURL:source)!
  let baseNR=raw.luminanceNoiseReductionAmount, baseSharp=raw.sharpnessAmount
  if mode == "raw_nr0" && raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount=0 }
  if mode == "raw_nr1" && raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount=1 }
  if mode == "raw_sharp0" && raw.isSharpnessSupported { raw.sharpnessAmount=0 }
  if mode == "raw_sharp1" && raw.isSharpnessSupported { raw.sharpnessAmount=1 }
  var image=raw.outputImage!
  if mode == "rgb_nr" { image=image.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.1,"inputSharpness":0.5]) }
  if mode == "rgb_sharp" { image=image.applyingFilter("CIUnsharpMask",parameters:["inputRadius":1.0,"inputIntensity":0.5]) }
  let b=image.extent.integral, side=Int((b.width*0.19).rounded())
  let rect=CGRect(x:Int(b.minX+b.width*0.35),y:Int(b.maxY-b.height*0.23)-side,width:side,height:side)
  var p=[Float](repeating:0,count:side*side*4)
  context.render(image,toBitmap:&p,rowBytes:side*16,bounds:rect,format:.RGBAf,colorSpace:linear)
  var sum=0.0,edge=0.0,n=0,edgeN=0,diff=0.0,dn=0
  func lum(_ i:Int)->Double {0.2289746*Double(p[i])+0.6917385*Double(p[i+1])+0.0792869*Double(p[i+2])}
  for q in 0..<(side*side) { let i=q*4, y=lum(i); guard y.isFinite else {continue}; sum += y; n += 1
   if q%side<side-1 { let yy=lum(i+4); if yy.isFinite {edge += abs(y-yy); edgeN += 1} }
   if let ref=reference { for c in 0..<3 {let v=Double(p[i+c])-Double(ref[i+c]); if v.isFinite {diff += v*v; dn += 1}} }
  }
  if mode == "default" { reference=p }
  let cg=context.createCGImage(image,from:rect,format:.RGBA8,colorSpace:display)!
  let dest=CGImageDestinationCreateWithURL(out.appendingPathComponent("detail_\(mode).png") as CFURL,"public.png" as CFString,1,nil)!
  CGImageDestinationAddImage(dest,cg,nil); precondition(CGImageDestinationFinalize(dest))
  items.append(["mode":mode,"width":side,"meanLuma":sum/Double(max(n,1)),"meanNeighborAbsDifference":edge/Double(max(edgeN,1)),"rmsRGBDifferenceFromDefault":dn>0 ? sqrt(diff/Double(dn)) : 0,
     "luminanceNRSupported":raw.isLuminanceNoiseReductionSupported,"sharpnessSupported":raw.isSharpnessSupported,"defaultLuminanceNR":baseNR,"defaultSharpness":baseSharp,
     "effectiveLuminanceNR":raw.luminanceNoiseReductionAmount,"effectiveSharpness":raw.sharpnessAmount,"decoderVersion":raw.decoderVersion.rawValue])
 }
 print(mode); fflush(stdout)
}
let d=try JSONSerialization.data(withJSONObject:["source":source.path,"note":"RGB NR and sharpening are illustrative settings, not calibrated equivalents; comparisons retain decoder defaults.","records":items],options:[.prettyPrinted,.sortedKeys])
try d.write(to:root.appendingPathComponent("metrics/DSC00324-detail.json"),options:.atomic)
