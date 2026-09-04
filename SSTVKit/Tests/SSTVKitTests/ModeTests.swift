import XCTest
@testable import SSTVKit

final class ModeTests: XCTestCase {
    func testPublishedModeMetadata() {
        let expected: [(
            mode: SSTVMode,
            name: String,
            family: SSTVModeFamily,
            vis: Int,
            width: Int,
            height: Int,
            radioLines: Int,
            line: Double,
            picture: Double
        )] = [
            (.robot36Color, "Robot 36 Color", .robot, 8, 320, 240, 240, 0.150, 36.000),
            (.robot72Color, "Robot 72 Color", .robot, 12, 320, 240, 240, 0.300, 72.000),
            (.pd50, "PD 50", .pd, 93, 320, 256, 128, 0.388160, 49.684480),
            (.pd90, "PD 90", .pd, 99, 320, 256, 128, 0.703040, 89.989120),
            (.pd120, "PD 120", .pd, 95, 640, 496, 248, 0.508480, 126.103040),
            (.pd160, "PD 160", .pd, 98, 512, 400, 200, 0.804416, 160.883200),
            (.pd180, "PD 180", .pd, 96, 640, 496, 248, 0.754240, 187.051520),
            (.pd240, "PD 240", .pd, 97, 640, 496, 248, 1.000000, 248.000000),
            (.pd290, "PD 290", .pd, 94, 800, 616, 308, 0.937280, 288.682240),
            (.martinM1, "Martin M1", .martin, 44, 320, 256, 256, 0.446446, 114.290176),
            (.martinM2, "Martin M2", .martin, 40, 320, 256, 256, 0.226798, 58.060288),
            (.scottieS1, "Scottie S1", .scottie, 60, 320, 256, 256, 0.428220, 109.633320),
            (.scottieS2, "Scottie S2", .scottie, 56, 320, 256, 256, 0.277692, 71.098152),
            (.scottieDX, "Scottie DX", .scottie, 76, 320, 256, 256, 1.050300, 268.885800),
            (.wraaseSC2180, "Wraase SC2-180", .wraase, 55, 320, 256, 256, 0.7110225, 182.021760),
        ]

        for item in expected {
            XCTAssertEqual(item.mode.displayName, item.name)
            XCTAssertEqual(item.mode.family, item.family)
            XCTAssertEqual(item.mode.visCode, item.vis)
            XCTAssertEqual(item.mode.width, item.width)
            XCTAssertEqual(item.mode.height, item.height)
            XCTAssertEqual(item.mode.scanLineCount, item.radioLines)
            XCTAssertEqual(item.mode.lineDuration, item.line, accuracy: 0.000_000_1)
            XCTAssertEqual(item.mode.pictureDuration, item.picture, accuracy: 0.000_000_1)
            XCTAssertEqual(
                item.mode.totalDuration,
                SSTVHeader.duration + item.picture,
                accuracy: 0.000_000_1
            )
        }
    }

    func testExpected48kHzSampleCounts() {
        let expected: [SSTVMode: Int] = [
            .robot36Color: 1_771_680,
            .robot72Color: 3_499_680,
            .pd50: 2_428_535,
            .pd90: 4_363_158,
            .pd120: 6_096_626,
            .pd160: 7_766_074,
            .pd180: 9_022_153,
            .pd240: 11_947_680,
            .pd290: 13_900_428,
            .martinM1: 5_529_608,
            .martinM2: 2_830_574,
            .scottieS1: 5_306_079,
            .scottieS2: 3_456_391,
            .scottieDX: 12_950_198,
            .wraaseSC2180: 8_780_724,
        ]

        XCTAssertEqual(expected.count, SSTVMode.allCases.count)
        for mode in SSTVMode.allCases {
            XCTAssertEqual(mode.sampleCount(at: 48_000), expected[mode], mode.displayName)
        }
    }

    func testSampleCountSaturatesInsteadOfOverflowing() {
        XCTAssertEqual(SSTVMode.pd290.sampleCount(at: .max), .max)
    }

    func testAllCasesUseStableFamilyOrder() {
        XCTAssertEqual(
            SSTVMode.allCases,
            [
                .robot36Color,
                .robot72Color,
                .pd50,
                .pd90,
                .pd120,
                .pd160,
                .pd180,
                .pd240,
                .pd290,
                .martinM1,
                .martinM2,
                .scottieS1,
                .scottieS2,
                .scottieDX,
                .wraaseSC2180,
            ]
        )
    }

    func testFamiliesExposeOnlyTheirModes() {
        XCTAssertEqual(SSTVModeFamily.allCases, [.robot, .pd, .martin, .scottie, .wraase])
        for family in SSTVModeFamily.allCases {
            XCTAssertFalse(family.modes.isEmpty)
            XCTAssertTrue(family.modes.allSatisfy { $0.family == family })
        }
        XCTAssertEqual(SSTVModeFamily.pd.modes.count, 7)
    }
}
