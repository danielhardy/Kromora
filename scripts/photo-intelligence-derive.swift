import CoreGraphics
import Foundation
import ImageIO

guard (4...5).contains(CommandLine.arguments.count) else {
    fputs("usage: photo-intelligence-derive.swift <input.jpg> <output.jpg> <linear-gain> [linear-contrast]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let gain = Double(CommandLine.arguments[3]), gain.isFinite, gain > 0 else {
    fputs("linear gain must be a positive finite number\n", stderr)
    exit(2)
}
let contrast = CommandLine.arguments.count == 5 ? Double(CommandLine.arguments[4]) ?? 1 : 1
guard contrast.isFinite, contrast > 0 else {
    fputs("linear contrast must be a positive finite number\n", stderr)
    exit(2)
}
guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fputs("could not decode input image\n", stderr)
    exit(1)
}

let width = sourceImage.width
let height = sourceImage.height
var bytes = [UInt8](repeating: 0, count: width * height * 4)
let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
    guard let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    context.interpolationQuality = .none
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard rendered else {
    fputs("could not render input image\n", stderr)
    exit(1)
}

func decode(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

func encode(_ value: Double) -> Double {
    let clipped = min(1, max(0, value))
    return clipped <= 0.0031308 ? clipped * 12.92 : 1.055 * pow(clipped, 1 / 2.4) - 0.055
}

for offset in stride(from: 0, to: bytes.count, by: 4) {
    for channel in 0..<3 {
        let centered = decode(Double(bytes[offset + channel]) / 255) - 0.5
        let linear = (0.5 + centered * contrast) * gain
        bytes[offset + channel] = UInt8((encode(linear) * 255).rounded())
    }
    bytes[offset + 3] = 255
}

guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let outputImage = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
      ),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL, "public.jpeg" as CFString, 1, nil
      ) else {
    fputs("could not encode output image\n", stderr)
    exit(1)
}

let properties = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
CGImageDestinationAddImage(destination, outputImage, properties)
guard CGImageDestinationFinalize(destination) else {
    fputs("could not finalize output image\n", stderr)
    exit(1)
}
