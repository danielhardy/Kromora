import XCTest
@testable import KromoraKit

final class InfoInspectorViewTests: XCTestCase {
    func testInspectorStaysMountedWhileNavigationLoadsWithoutPixelsOrHistogram() {
        XCTAssertFalse(
            InfoInspectorView.shouldShowEmptyState(
                sourceImageAvailable: false,
                histogramAvailable: false,
                isNavigationLoading: true
            )
        )
        XCTAssertTrue(
            InfoInspectorView.shouldShowEmptyState(
                sourceImageAvailable: false,
                histogramAvailable: false,
                isNavigationLoading: false
            )
        )
        XCTAssertFalse(
            InfoInspectorView.shouldShowEmptyState(
                sourceImageAvailable: true,
                histogramAvailable: false,
                isNavigationLoading: false
            )
        )
        XCTAssertFalse(
            InfoInspectorView.shouldShowEmptyState(
                sourceImageAvailable: false,
                histogramAvailable: true,
                isNavigationLoading: false
            )
        )
    }
}
