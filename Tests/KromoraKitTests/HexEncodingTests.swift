import XCTest
@testable import KromoraKit

final class HexEncodingTests: XCTestCase {
    private func slowHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func testHexStringMatchesReferenceForRandomBytes() {
        XCTAssertEqual([UInt8]().hexString, "")
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<1_000 {
            let length = Int.random(in: 0...64, using: &generator)
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
            XCTAssertEqual(bytes.hexString, slowHex(bytes))
        }
    }

    func testHexStringIsLowercaseWithoutSeparators() {
        XCTAssertEqual([0x00, 0x0a, 0xff, 0xab].hexString, "000affab")
    }
}
