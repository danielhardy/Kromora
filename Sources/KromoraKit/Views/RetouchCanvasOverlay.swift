import AppKit
import SwiftUI

/// Canvas guides and native pointer delivery for source-space retouch gestures.
struct RetouchCanvasOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var state: RetouchInteractionState
    let sourceSize: CGSize
    let crop: CropAdjustments
    let rotation: ImageRotation
    let navigation: CanvasNavigation
    let backingScale: CGFloat
    @State private var lastPointerPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let mapping = GeometryPointMapping(sourceSize: sourceSize, rotation: rotation, crop: crop)
            ZStack {
                Canvas { context, size in
                    draw(context: &context, size: size, mapping: mapping)
                }
                .allowsHitTesting(false)
                MaskPointerSurface(isInteractive: state.isArmed,
                                   cursor: state.isSpacePanning ? .openHand : .crosshair) { event in
                    handle(event, mapping: mapping, viewport: geometry.size)
                }
            }
        }
        .accessibilityLabel("Retouch canvas")
    }

    private func draw(context: inout GraphicsContext, size: CGSize, mapping: GeometryPointMapping) {
        func viewport(_ point: CGPoint) -> CGPoint? {
            mapping.viewportPoint(forRetouchPoint: point, navigation: navigation,
                                  viewportSize: size, backingScale: backingScale)
        }
        if let sample = state.draftSamples.first, let center = viewport(sample.point) {
            let radius = screenRadius(state.draftRadius, center: sample.point, size: size, mapping: mapping)
            let rect = CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.22 * state.opacity)))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            if state.draftSamples.count > 1 {
                var line = Path(); line.move(to: center)
                for sample in state.draftSamples.dropFirst() { if let p = viewport(sample.point) { line.addLine(to: p) } }
                context.stroke(line, with: .color(.white.opacity(0.72)), style: StrokeStyle(lineWidth: radius*2, lineCap: .round, lineJoin: .round))
            }
        }
        if state.isArmed, !state.hasDraft, let point = state.hoverPoint, let center = viewport(point) {
            let outer = screenRadius(state.radius, center: point, size: size, mapping: mapping)
            let inner = outer * max(0.02, 1 - state.feather)
            context.stroke(Path(ellipseIn: CGRect(x:center.x-outer,y:center.y-outer,width:outer*2,height:outer*2)), with: .color(.white.opacity(0.95)), lineWidth: 1)
            context.stroke(Path(ellipseIn: CGRect(x:center.x-inner,y:center.y-inner,width:inner*2,height:inner*2)), with: .color(.white.opacity(0.48)), lineWidth: 1)
            var crosshair = Path(); crosshair.move(to: CGPoint(x:center.x-5,y:center.y)); crosshair.addLine(to: CGPoint(x:center.x+5,y:center.y)); crosshair.move(to: CGPoint(x:center.x,y:center.y-5)); crosshair.addLine(to: CGPoint(x:center.x,y:center.y+5))
            context.stroke(crosshair, with: .color(.white), lineWidth: 1)
        }
        if state.shouldShowOverlay && state.visualizationEnabled {
            for candidate in state.visualizationCandidates {
                guard let center = viewport(candidate.point) else { continue }
                let r = screenRadius(candidate.radius, center: candidate.point, size: size, mapping: mapping)
                let rect = CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)
                context.fill(Path(ellipseIn: rect), with: .color(.orange.opacity(0.15 + candidate.confidence * 0.3)))
                context.stroke(Path(ellipseIn: rect), with: .color(.orange.opacity(0.8)), lineWidth: 1)
            }
        }
        if state.shouldShowOverlay {
            for suggestion in state.dustSuggestions {
                guard let center = viewport(suggestion.point) else { continue }
                let r = screenRadius(suggestion.radius, center: suggestion.point, size: size, mapping: mapping)
                let rect = CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)
                context.stroke(Path(ellipseIn: rect), with: .color(.mint),
                               style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                context.fill(Path(ellipseIn: CGRect(x: center.x-3, y: center.y-3, width: 6, height: 6)),
                             with: .color(.mint))
            }
        }
        guard state.shouldShowOverlay else { return }
        for spot in viewModel.document.retouch.spots where spot.isVisible {
            guard let point = spot.region.samples.first?.point, let center = viewport(point) else { continue }
            let r = screenRadius(spot.region.radius, center: point, size: size, mapping: mapping)
            let rect = CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)
            let selected = state.selectedSpotID == spot.id
            let hovered = state.hoveredSpotID == spot.id
            if selected || hovered {
                context.stroke(Path(ellipseIn: rect), with: .color(selected ? .yellow : .white.opacity(0.9)), lineWidth: selected ? 2 : 1.5)
            }
            if spot.region.samples.count > 1, selected || hovered {
                var outline = Path(); outline.move(to: center)
                for sample in spot.region.samples.dropFirst() { if let p = viewport(sample.point) { outline.addLine(to: p) } }
                context.stroke(outline, with: .color(selected ? .yellow : .white.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x:center.x-3,y:center.y-3,width:6,height:6)), with: .color(selected ? .yellow : .white))
            if selected, let source = spot.source {
                let offset = source.offset
                let src = CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
                if let sourceCenter = viewport(src) {
                    var arrow = Path(); arrow.move(to: sourceCenter); arrow.addLine(to: center)
                    context.stroke(arrow, with: .color(.yellow.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [4,3]))
                    let angle = atan2(center.y - sourceCenter.y, center.x - sourceCenter.x)
                    let tip = CGPoint(x: center.x - cos(angle) * max(r, 7), y: center.y - sin(angle) * max(r, 7))
                    let left = CGPoint(x: tip.x - cos(angle - .pi / 6) * 7, y: tip.y - sin(angle - .pi / 6) * 7)
                    let right = CGPoint(x: tip.x - cos(angle + .pi / 6) * 7, y: tip.y - sin(angle + .pi / 6) * 7)
                    var arrowHead = Path(); arrowHead.move(to: tip); arrowHead.addLine(to: left); arrowHead.addLine(to: right); arrowHead.closeSubpath()
                    context.fill(arrowHead, with: .color(.yellow))
                    let sr = screenRadius(spot.region.radius, center: src, size: size, mapping: mapping)
                    context.stroke(Path(ellipseIn: CGRect(x:sourceCenter.x-sr,y:sourceCenter.y-sr,width:sr*2,height:sr*2)), with: .color(.cyan), lineWidth: 1.5)
                }
            }
            if state.solvingSpotIDs.contains(spot.id) {
                let spinnerRect = rect.insetBy(dx: -5, dy: -5)
                var spinner = Path()
                spinner.addArc(center: CGPoint(x: spinnerRect.midX, y: spinnerRect.midY), radius: spinnerRect.width / 2,
                               startAngle: .degrees(-55), endAngle: .degrees(230), clockwise: false)
                context.stroke(spinner, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        if let hover = state.hoveredSpotID,
           let spot = viewModel.document.retouch.spots.first(where: {$0.id == hover}),
           let point = viewport(spot.region.samples.first?.point ?? .zero) {
            let r = max(3, screenRadius(state.radius, center: spot.region.samples.first?.point ?? .zero, size: size, mapping: mapping))
            context.stroke(Path(ellipseIn: CGRect(x:point.x-r,y:point.y-r,width:r*2,height:r*2)), with: .color(.white.opacity(0.75)), lineWidth: 1)
        }
    }

    private func screenRadius(_ normalized: Double, center: CGPoint, size: CGSize, mapping: GeometryPointMapping) -> CGFloat {
        let shortSide = min(sourceSize.width, sourceSize.height)
        guard let c = mapping.viewportPoint(forRetouchPoint: center, navigation: navigation, viewportSize: size, backingScale: backingScale),
              let x = mapping.viewportPoint(forRetouchPoint: CGPoint(x:center.x + normalized * shortSide / max(sourceSize.width,1),y:center.y), navigation: navigation, viewportSize: size, backingScale: backingScale) else { return 4 }
        return max(4, hypot(x.x-c.x,x.y-c.y))
    }

    private func handle(_ event: MaskNativePointerEvent, mapping: GeometryPointMapping, viewport: CGSize) {
        func sourcePoint(_ p: CGPoint) -> CGPoint? {
            mapping.retouchPoint(forViewport: p, navigation: navigation, viewportSize: viewport, backingScale: backingScale)
        }
        switch event {
        case .moved(let samples): if let p = samples.last?.point { if let source = sourcePoint(p) { viewModel.retouchWorkflow.hover(at: source) } }
        case .exited: state.hover(nil, at: nil)
        case .began(let samples):
            lastPointerPoint = samples.last?.point
            guard !state.isSpacePanning else { return }
            guard let sample = samples.last, let p = sourcePoint(sample.point) else { return }
            viewModel.retouchWorkflow.beginGesture(at: p, pressure: sample.pressure, modifiers: NSEvent.modifierFlags)
        case .dragged(let samples):
            for sample in samples {
                if state.isSpacePanning {
                    if let previous = lastPointerPoint {
                        viewModel.panCanvas(by: CGSize(width: sample.point.x-previous.x, height: sample.point.y-previous.y), viewportSize: viewport)
                    }
                    lastPointerPoint = sample.point
                } else if let p = sourcePoint(sample.point) {
                    viewModel.retouchWorkflow.updateGesture(to: p, pressure: sample.pressure)
                }
            }
        case .ended(let sample):
            if !state.isSpacePanning {
                if let sample, let p = sourcePoint(sample.point) { viewModel.retouchWorkflow.updateGesture(to: p, pressure: sample.pressure) }
                viewModel.retouchWorkflow.endGesture()
            }
            lastPointerPoint = nil
        case .scrolled(let scroll):
            if scroll.isOptionDown {
                state.radius = min(0.25, max(0.0005, state.radius + scroll.deltaY * -0.0002))
            } else {
                viewModel.zoomCanvas(by: 1 + scroll.deltaY * 0.002, at: scroll.point, viewportSize: viewport)
            }
        case .magnified(let value): viewModel.zoomCanvas(by: value.factor, at: value.point, viewportSize: viewport)
        }
    }
}
