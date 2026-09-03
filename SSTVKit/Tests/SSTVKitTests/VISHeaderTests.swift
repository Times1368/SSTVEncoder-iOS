import XCTest
@testable import SSTVKit

final class VISHeaderTests: XCTestCase {
    func testVISBitsAreLeastSignificantFirstWithEvenParity() {
        let bits = SSTVHeader.bits(visCode: 44)

        XCTAssertEqual(bits, [false, false, true, true, false, true, false, true])
        XCTAssertEqual(bits.filter { $0 }.count % 2, 0)
    }

    func testEachModeProducesTheExpectedHeaderFrequencies() {
        for mode in SSTVMode.allCases {
            let segments = SSTVHeader.segments(visCode: mode.visCode)
            XCTAssertEqual(segments.count, 13)
            XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1900, duration: 0.300))
            XCTAssertEqual(segments[1], ToneSegment(frequencyHz: 1200, duration: 0.010))
            XCTAssertEqual(segments[2], ToneSegment(frequencyHz: 1900, duration: 0.300))
            XCTAssertEqual(segments[3], ToneSegment(frequencyHz: 1200, duration: 0.030))
            XCTAssertEqual(segments[12], ToneSegment(frequencyHz: 1200, duration: 0.030))
            XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.910, accuracy: 0.000_000_1)
        }
    }

    func testVISDataFrequenciesForRobot36() {
        let segments = SSTVHeader.segments(visCode: SSTVMode.robot36Color.visCode)
        let dataAndParity = Array(segments[4...11].map(\.frequencyHz))

        // 8 decimal = 0001000 binary; LSB first and then a one parity bit.
        XCTAssertEqual(dataAndParity, [1300, 1300, 1300, 1100, 1300, 1300, 1300, 1100])
    }
}

