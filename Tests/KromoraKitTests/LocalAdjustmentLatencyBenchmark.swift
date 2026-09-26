import AppKit
import Metal
import XCTest

@testable import KromoraKit

/// Hardware-backed Brush + local Exposure timing for the KRMA-582 preview scheduling fix.
/// Values are diagnostic because Core Image, Metal, power state, and OS scheduling vary by host.
@MainActor
final class LocalAdjustmentLatencyBenchmark: TempDirectoryTestCase {
    private struct Sample {
        let firstInteractiveFrameMS: Double
        let settledPreviewMS: Double
        let repeatedFirstInteractiveFrameMS: Double
        let repeatedSettledPreviewMS: Double
    }

    private let imageWidth = 1600
    private let imageHeight = 1200

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 60,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "preview did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func maskDocument() -> EditDocument {
        let stroke = BrushStroke(
            samples: [
                BrushSample(point: CGPoint(x: 0.32, y: 0.48), pressure: 1),
                BrushSample(point: CGPoint(x: 0.40, y: 0.46), pressure: 1),
                BrushSample(point: CGPoint(x: 0.48, y: 0.51), pressure: 0.9),
                BrushSample(point: CGPoint(x: 0.56, y: 0.49), pressure: 1),
                BrushSample(point: CGPoint(x: 0.64, y: 0.52), pressure: 1),
            ],
            radius: 0.06, feather: 0.45, flow: 0.8, density: 1
        )
        let component = MaskComponent(
            name: "Brush",
            source: .brush(BrushMaskDefinition(strokes: [stroke]))
        )
        let layer = LocalAdjustmentLayer(
            name: "Brush exposure", components: [component],
            adjustments: LocalAdjustments(exposure: 0)
        )
        return EditDocument(localAdjustments: [layer])
    }

    private func measureIteration(_ iteration: Int) async throws -> Sample {
        let directory = tempDirectory.appendingPathComponent("iteration-\(iteration)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try Fixtures.writeGradientPNG(
            width: imageWidth, height: imageHeight, named: "brush-source.png", in: directory
        )
        let viewModel = makeAppViewModel(
            engine: RenderEngine(),
            libraryFolderURL: directory.appendingPathComponent("managed-library", isDirectory: true)
        )
        viewModel.openImage(url: source)
        try await waitUntil("source image") { viewModel.sourceImage != nil }
        try await waitUntil("initial masked preview") {
            viewModel.previewState == .ready && viewModel.previewSurface.image != nil
        }
        let openingRevision = viewModel.previewSurface.revision
        viewModel.updateDocument { $0 = maskDocument() }
        try await waitUntil("brush mask preview") {
            viewModel.previewSurface.revision > openingRevision
                && viewModel.document.localAdjustments.count == 1
        }
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)
        let exposure = viewModel.localAdjustmentBinding(.exposure, in: layerID)

        // Simulate a continuous slider drag. The synchronous value writes are the same binding
        // updates SwiftUI sends; short pauses allow the interactive scheduler and GPU to publish.
        viewModel.beginPreviewInteraction()
        let firstBaseRevision = viewModel.previewSurface.revision
        let firstStart = DispatchTime.now().uptimeNanoseconds
        exposure.wrappedValue = -0.25
        var firstInteractiveMS: Double?
        for step in 2...20 {
            exposure.wrappedValue = -Double(step) * 0.25
            try await Task.sleep(for: .milliseconds(16))
            if firstInteractiveMS == nil, viewModel.previewSurface.revision > firstBaseRevision {
                firstInteractiveMS = elapsedMilliseconds(since: firstStart)
            }
        }
        try await waitUntil("first interactive frame") {
            viewModel.previewSurface.revision > firstBaseRevision
        }
        let measuredFirstInteractiveMS = firstInteractiveMS ?? elapsedMilliseconds(since: firstStart)
        let dragEnd = DispatchTime.now().uptimeNanoseconds
        viewModel.endPreviewInteraction()
        let interactiveRevision = viewModel.previewSurface.revision
        try await waitUntil("settled preview after first drag") {
            viewModel.previewState == .ready && viewModel.previewSurface.revision > interactiveRevision
        }
        let settledMS = elapsedMilliseconds(since: dragEnd)

        // Repeat on the same brush definition so its raster is warm. A second drag is short but
        // still uses the interactive path and has a separately observed settled result.
        viewModel.beginPreviewInteraction()
        let repeatedBaseRevision = viewModel.previewSurface.revision
        let repeatedStart = DispatchTime.now().uptimeNanoseconds
        exposure.wrappedValue = -4.75
        try await waitUntil("repeated interactive frame") {
            viewModel.previewSurface.revision > repeatedBaseRevision
        }
        let repeatedInteractiveMS = elapsedMilliseconds(since: repeatedStart)
        let repeatedDragEnd = DispatchTime.now().uptimeNanoseconds
        viewModel.endPreviewInteraction()
        let repeatedInteractiveRevision = viewModel.previewSurface.revision
        try await waitUntil("settled preview after repeated drag") {
            viewModel.previewState == .ready
                && viewModel.previewSurface.revision > repeatedInteractiveRevision
        }
        let repeatedSettledMS = elapsedMilliseconds(since: repeatedDragEnd)

        return Sample(
            firstInteractiveFrameMS: measuredFirstInteractiveMS, settledPreviewMS: settledMS,
            repeatedFirstInteractiveFrameMS: repeatedInteractiveMS,
            repeatedSettledPreviewMS: repeatedSettledMS
        )
    }

    private func percentile(_ samples: [Double], _ quantile: Double) -> Double {
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(quantile * Double(sorted.count))) - 1))
        return sorted[index]
    }

    private func machineModel() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "hw.model"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let model = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty
            else { return "unknown" }
            return model
        } catch {
            return "unknown"
        }
    }

    func testOptInBrushLocalExposurePreviewLatency() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_LOCAL_ADJUSTMENT_BENCHMARK"] == "1",
            "set KROMORA_LOCAL_ADJUSTMENT_BENCHMARK=1 to run the real-engine brush benchmark"
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let iterations = max(
            3,
            Int(ProcessInfo.processInfo.environment["KROMORA_LOCAL_ADJUSTMENT_ITERATIONS"] ?? "5") ?? 5
        )
        var samples: [Sample] = []
        for iteration in 0..<iterations {
            samples.append(try await measureIteration(iteration))
        }

        let firstInteractive = samples.map(\.firstInteractiveFrameMS)
        let settled = samples.map(\.settledPreviewMS)
        let repeatedInteractive = samples.map(\.repeatedFirstInteractiveFrameMS)
        let repeatedSettled = samples.map(\.repeatedSettledPreviewMS)
        #if DEBUG
        let buildConfiguration = "Debug"
        #else
        let buildConfiguration = "Release"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion

        print("\n=== KRMA-587 Brush + local Exposure latency (after KRMA-582) ===")
        print(
            "image=\(imageWidth)x\(imageHeight) synthetic=gradient-png machine=\(machineModel()) " +
                "chip=\(device.name) os=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion) " +
                "build=\(buildConfiguration) iterations=\(iterations) exposure_end_ev=-5.00"
        )
        for (name, values) in [
            ("first_interactive_frame", firstInteractive),
            ("settled_after_drag", settled),
            ("repeated_interactive_frame", repeatedInteractive),
            ("repeated_settled_after_drag", repeatedSettled),
        ] {
            print(
                String(
                    format: "%@_ms p50=%.2f p95=%.2f samples=%@",
                    name, percentile(values, 0.50), percentile(values, 0.95),
                    values.map { String(format: "%.2f", $0) }.joined(separator: ",")
                )
            )
        }
    }
}
