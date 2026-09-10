import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

#if DEBUG
@MainActor
final class AnalysisDebugPanelTests: XCTestCase {
    func testDebugPanelConstructsWithoutEagerAnalysis() {
        let coordinator = PhotoAnalysisCoordinator(stages: [:])
        let source = ImageSource(
            backing: .data(Data([7, 8, 9])), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let panel = AnalysisDebugPanel(
            coordinator: coordinator,
            assetID: PhotoAssetID.data(Data([7, 8, 9])),
            source: source,
            surface: PreviewSurface()
        )

        XCTAssertNotNil(panel.body)
    }
}
#endif
