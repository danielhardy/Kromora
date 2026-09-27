import CoreGraphics
import XCTest
@testable import KromoraKit

final class RetouchDustDetectorTests: XCTestCase {
    func testThresholdFiltersWeakResponsesAndResultsAreDeterministic() {
        let proxy = proxy(background: "sky", defect: "soft dust 5px")
        let permissive = RetouchDustDetector.detect(in: proxy, threshold: 0.005)
        let strict = RetouchDustDetector.detect(in: proxy, threshold: 0.12)
        XCTAssertTrue(strict.count <= permissive.count)
        XCTAssertEqual(permissive, RetouchDustDetector.detect(in: proxy, threshold: 0.005))
    }

    func testDetectionRestrictionsAndPrecisionRecallReport() {
        var truePositive = 0, falsePositive = 0, defectFrames = 0, foundFrames = 0
        for background in RetouchQualityFixtures.backgrounds {
            for defect in ["soft dust 5px", "hard speck"] {
                let fixture = RetouchQualityFixtures.make(background: background, defect: defect)
                let candidates = RetouchDustDetector.detect(in: proxy(fixture.damaged), threshold: 0.025)
                let found = candidates.contains { candidate in
                    let x = min(fixture.width - 1, max(0, Int((candidate.point.x * CGFloat(fixture.width)).rounded())))
                    let y = min(fixture.height - 1, max(0, Int((candidate.point.y * CGFloat(fixture.height)).rounded())))
                    return fixture.mask[y * fixture.width + x]
                }
                defectFrames += 1
                if found { foundFrames += 1 }
                truePositive += candidates.filter { candidate in
                    let x = min(fixture.width - 1, max(0, Int((candidate.point.x * CGFloat(fixture.width)).rounded())))
                    let y = min(fixture.height - 1, max(0, Int((candidate.point.y * CGFloat(fixture.height)).rounded())))
                    return fixture.mask[y * fixture.width + x]
                }.count
                falsePositive += candidates.filter { candidate in
                    let x = min(fixture.width - 1, max(0, Int((candidate.point.x * CGFloat(fixture.width)).rounded())))
                    let y = min(fixture.height - 1, max(0, Int((candidate.point.y * CGFloat(fixture.height)).rounded())))
                    return !fixture.mask[y * fixture.width + x]
                }.count
            }
        }
        let precision = Double(truePositive) / Double(max(1, truePositive + falsePositive))
        let recall = Double(foundFrames) / Double(max(1, defectFrames))
        print(String(format: "Retouch dust detector threshold=0.025 pixel_precision=%.3f fixture_recall=%.3f fixtures=%d", precision, recall, defectFrames))
        XCTAssertGreaterThan(precision, 0)
        XCTAssertGreaterThan(recall, 0)
    }

    func testSmoothRegionGateSuppressesFoliageCandidates() {
        let smooth = RetouchDustDetector.detect(in: proxy(background: "sky", defect: "soft dust 5px"), threshold: 0.02)
        let textured = RetouchDustDetector.detect(in: proxy(background: "foliage", defect: "soft dust 5px"), threshold: 0.02)
        XCTAssertLessThanOrEqual(textured.count, smooth.count + 2)
    }

    private func proxy(background: String, defect: String) -> RetouchAnalysisProxy {
        let fixture = RetouchQualityFixtures.make(background: background, defect: defect)
        return proxy(fixture.damaged)
    }

    private func proxy(_ image: CGImage) -> RetouchAnalysisProxy {
        let data = image.dataProvider!.data! as Data
        return RetouchAnalysisProxy.fromRGBA8(data, width: image.width, height: image.height)
    }
}
