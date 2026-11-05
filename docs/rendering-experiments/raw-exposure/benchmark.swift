import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin

// Window-independent proxy, not an AppViewModel/RenderEngine interaction benchmark.
let args = CommandLine.arguments
if args.count < 3 { fputs("usage: benchmark RAW OUTPUT_JSON\n", stderr); exit(2) }
let url = URL(fileURLWithPath: args[1])
let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
let ctx = CIContext(options: [.workingColorSpace:linear, .cacheIntermediates:false])
func elapsed(_ start: Date) -> Double { Date().timeIntervalSince(start) }
func render(_ image: CIImage) -> Double {
    let r = image.extent.integral, w = Int(r.width), h = Int(r.height)
    var data = [Float](repeating: 0, count:w*h*4)
    let t = Date()
    ctx.render(image, toBitmap:&data, rowBytes:w*16, bounds:r, format:.RGBAf, colorSpace:linear)
    return elapsed(t)
}
func develop(_ scale: Float, _ ev: Float) -> CIImage {
    let f = CIRAWFilter(imageURL:url)!; f.scaleFactor = scale; f.exposure = ev
    return f.outputImage!
}
let raw = CIRAWFilter(imageURL:url)!
let scale = Float(min(1, 800 / max(raw.nativeSize.width,raw.nativeSize.height)))
let t = Date(); let base = develop(scale,0); let first = render(base); let cold = elapsed(t)
// Materialize a developed, float RGB preview once, to represent source-cache reuse.
let r = base.extent.integral, w = Int(r.width), h = Int(r.height)
var buffer = [Float](repeating:0,count:w*h*4)
ctx.render(base,toBitmap:&buffer,rowBytes:w*16,bounds:r,format:.RGBAf,colorSpace:linear)
let data = buffer.withUnsafeBytes { Data($0) }
let cached = CIImage(bitmapData:data,bytesPerRow:w*16,size:r.size,format:.RGBAf,colorSpace:linear)
var rgb = [Double](), rawTimes = [Double]()
for ev: Float in [-1,-2,1,2,-1] {
 let a = CIFilter.exposureAdjust(); a.inputImage = cached; a.ev = ev
 rgb.append(render(a.outputImage!))
 let t = Date(); _ = render(develop(scale,ev)); rawTimes.append(elapsed(t))
}
let fullStart = Date(); let full = develop(1,-1); let fullRender = render(full); let fullTotal = elapsed(fullStart)
var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
let result: [String:Any] = ["source":url.path,"scale":scale,"firstPreviewRenderSeconds":first,"firstPreviewConstructAndRenderSeconds":cold,
 "cachedRGBPreviewSeconds":rgb,"freshRAWPreviewSeconds":rawTimes,"fullRawMinus1RenderSeconds":fullRender,
 "fullRawMinus1ConstructAndRenderSeconds":fullTotal,"peakRSSBytes":usage.ru_maxrss,
 "limitations":"Independent Core Image proxy, no app cache, UI scheduling or drawable; timings include CPU float readback, no GPU/CPU utilization sampling."]
let json = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
try json.write(to:URL(fileURLWithPath:args[2]),options:.atomic)
