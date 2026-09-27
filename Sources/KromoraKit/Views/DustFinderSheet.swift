import AppKit
import CoreImage
import SwiftUI

/// High-contrast pixel-size retouch workspace. The source is the latest published preview, so the
/// finder stays cheap and follows the normal render publication lifecycle.
struct DustFinderSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var finderImage: CGImage?
    @State private var selectedIndex = 0

    private var spots: [RetouchSpot] { viewModel.document.retouch.spots }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Dust Finder").font(.headline)
                Text("High contrast · 1:1 preview pixels").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(spots.isEmpty)
                    .help("Previous spot")
                Text(spots.isEmpty ? "No spots" : "Spot \(selectedIndex + 1) of \(spots.count)")
                    .font(.caption.monospacedDigit()).frame(minWidth: 96)
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(spots.isEmpty)
                    .help("Next spot")
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 12).padding(.top, 12)
            Divider()
            if let finderImage {
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Image(decorative: finderImage, scale: 1)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: CGFloat(finderImage.width), height: CGFloat(finderImage.height))
                            ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                                if spot.isVisible {
                                let center = markerCenter(for: spot, imageSize: CGSize(
                                    width: finderImage.width, height: finderImage.height
                                ))
                                Circle()
                                    .stroke(index == selectedIndex ? Color.yellow : Color.red, lineWidth: 2)
                                    .frame(width: max(12, CGFloat(spot.radius) * CGFloat(finderImage.width) * 2),
                                           height: max(12, CGFloat(spot.radius) * CGFloat(finderImage.height) * 2))
                                    .position(center)
                                    .id(spot.id)
                                }
                            }
                        }
                        .frame(width: CGFloat(finderImage.width), height: CGFloat(finderImage.height))
                    }
                    .background(.black)
                    .onChange(of: selectedIndex) { _, index in
                        guard spots.indices.contains(index) else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(spots[index].id, anchor: .center)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: "photo", description: Text("Wait for an image preview, then open Dust Finder again."))
            }
        }
        .task(id: viewModel.previewSurface.revision) { makeFinderImage() }
    }

    private func makeFinderImage() {
        guard let source = viewModel.previewSurface.image else { finderImage = nil; return }
        let mono = source.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 2.4,
            kCIInputBrightnessKey: 0.04
        ])
        let sharpened = mono.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.2,
            kCIInputIntensityKey: 1.6
        ]).cropped(to: source.extent)
        finderImage = RenderEngineResources.makeOneShotContext().createCGImage(
            sharpened, from: source.extent.integral, format: .RGBA8, colorSpace: viewModel.previewSurface.space.cgColorSpace
        )
    }

    private func markerCenter(for spot: RetouchSpot, imageSize: CGSize) -> CGPoint {
        let point: CGPoint
        switch spot.shape {
        case .circle(let center): point = center
        case .stroke(let points): point = points.first ?? .zero
        }
        let crop = viewModel.document.crop.normalizedRect ?? CropAdjustments.unitRect
        let mapping = GeometryPointMapping(
            sourceSize: viewModel.sourceSize, rotation: .zero, crop: viewModel.document.crop
        )
        guard let mapped = mapping.forward(point), crop.width > 0, crop.height > 0 else { return .zero }
        return CGPoint(
            x: (mapped.x - crop.minX) / crop.width * imageSize.width,
            y: (mapped.y - crop.minY) / crop.height * imageSize.height
        )
    }

    private func move(_ step: Int) {
        guard !spots.isEmpty else { return }
        selectedIndex = (selectedIndex + step + spots.count) % spots.count
    }
}
