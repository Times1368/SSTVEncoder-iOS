import XCTest
@testable import SSTVKit

final class ModeTests: XCTestCase {
    func testPublishedModeMetadata() {
        let expected: [(SSTVMode, String, Int, Int, Int, Double, Double)] = [
            (.robot36Color, "Robot 36 Color", 8, 320, 240, 0.150, 36.000),
            (.robot72Color, "Robot 72 Color", 12, 320, 240, 0.300, 72.000),
            (.martinM1, "Martin M1", 44, 320, 256, 0.446446, 114.290176),
            (.scottieS1, "Scottie S1", 60, 320, 256, 0.428220, 109.633320),
        ]

        for (mode, name, vis, width, height, line, picture) in expected {
            XCTAssertEqual(mode.displayName, name)
            XCTAssertEqual(mode.visCode, vis)
            XCTAssertEqual(mode.width, width)
            XCTAssertEqual(mode.height, height)
            XCTAssertEqual(mode.lineDuration, line, accuracy: 0.000_000_1)
            XCTAssertEqual(mode.pictureDuration, picture, accuracy: 0.000_000_1)
        }
    }

    func testTotalDurationsIncludeHeaderAndScottieStartingSync() {
        XCTAssertEqual(SSTVMode.robot36Color.totalDuration, 36.910, accuracy: 0.000_000_1)
        XCTAssertEqual(SSTVMode.robot72Color.totalDuration, 72.910, accuracy: 0.000_000_1)
        XCTAssertEqual(SSTVMode.martinM1.totalDuration, 115.200176, accuracy: 0.000_000_1)
        XCTAssertEqual(SSTVMode.scottieS1.totalDuration, 110.543320, accuracy: 0.000_000_1)
    }

    func testExpected48kHzSampleCounts() {
        XCTAssertEqual(SSTVMode.robot36Color.sampleCount(at: 48_000), 1_771_680)
        XCTAssertEqual(SSTVMode.robot72Color.sampleCount(at: 48_000), 3_499_680)
        XCTAssertEqual(SSTVMode.martinM1.sampleCount(at: 48_000), 5_529_608)
        XCTAssertEqual(SSTVMode.scottieS1.sampleCount(at: 48_000), 5_306_079)
    }

    func testAllCasesAreExactlyTheVersionOneModes() {
        XCTAssertEqual(
            SSTVMode.allCases,
            [.robot36Color, .robot72Color, .martinM1, .scottieS1]
        )
    }
}

