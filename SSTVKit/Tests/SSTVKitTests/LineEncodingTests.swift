import XCTest
@testable import SSTVKit

final class LineEncodingTests: XCTestCase {
    func testMartinM1SequenceIsSyncPorchGreenBlueRedWithSeparators() throws {
        let pixel = RGBPixel(red: 255, green: 127, blue: 31)
        let image = solidImage(for: .martinM1, pixel: pixel)
        let segments = try SSTVLineEncoder.segments(for: image, mode: .martinM1, row: 0)

        XCTAssertEqual(segments.count, 965)
        XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1200, duration: 0.004862))
        XCTAssertEqual(segments[1], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments[2].frequencyHz, 1898.431_373, accuracy: 0.001)
        XCTAssertEqual(segments[322], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments[323].frequencyHz, 1597.254_902, accuracy: 0.001)
        XCTAssertEqual(segments[643], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments[644].frequencyHz, 2300, accuracy: 0.001)
        XCTAssertEqual(segments[964], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.446446, accuracy: 0.000_000_1)
    }

    func testMartinM2UsesTheShorterPublishedChannelScan() throws {
        let pixel = RGBPixel(red: 255, green: 127, blue: 31)
        let image = solidImage(for: .martinM2, pixel: pixel)
        let segments = try SSTVLineEncoder.segments(for: image, mode: .martinM2, row: 0)

        XCTAssertEqual(segments.count, 965)
        XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1200, duration: 0.004862))
        XCTAssertEqual(segments[1], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments[2].duration, 0.073216 / 320, accuracy: 0.000_000_001)
        XCTAssertEqual(segments[322], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments[643], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments[964], ToneSegment(frequencyHz: 1500, duration: 0.000572))
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.226798, accuracy: 0.000_000_1)
    }

    func testScottieS1HasOneStartingSyncAndMidLineRegularSync() throws {
        XCTAssertEqual(
            SSTVLineEncoder.framePrefix(for: .scottieS1),
            [ToneSegment(frequencyHz: 1200, duration: 0.009)]
        )

        let pixel = RGBPixel(red: 255, green: 127, blue: 31)
        let image = solidImage(for: .scottieS1, pixel: pixel)
        let segments = try SSTVLineEncoder.segments(for: image, mode: .scottieS1, row: 0)
        XCTAssertEqual(segments.count, 964)
        XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1500, duration: 0.0015))
        XCTAssertEqual(segments[1].frequencyHz, 1898.431_373, accuracy: 0.001)
        XCTAssertEqual(segments[321], ToneSegment(frequencyHz: 1500, duration: 0.0015))
        XCTAssertEqual(segments[322].frequencyHz, 1597.254_902, accuracy: 0.001)
        XCTAssertEqual(segments[642], ToneSegment(frequencyHz: 1200, duration: 0.009))
        XCTAssertEqual(segments[643], ToneSegment(frequencyHz: 1500, duration: 0.0015))
        XCTAssertEqual(segments[644].frequencyHz, 2300, accuracy: 0.001)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.42822, accuracy: 0.000_000_1)
    }

    func testEveryScottieVariantUsesItsPublishedScanTime() throws {
        let expected: [(SSTVMode, Double, Double)] = [
            (.scottieS1, 0.138240, 0.428220),
            (.scottieS2, 0.088064, 0.277692),
            (.scottieDX, 0.345600, 1.050300),
        ]

        for (mode, channelDuration, lineDuration) in expected {
            XCTAssertEqual(
                SSTVLineEncoder.framePrefix(for: mode),
                [ToneSegment(frequencyHz: 1200, duration: 0.009)]
            )
            let segments = try SSTVLineEncoder.segments(
                for: solidImage(for: mode),
                mode: mode,
                row: 0
            )
            XCTAssertEqual(segments.count, 964)
            XCTAssertEqual(segments[1].duration, channelDuration / 320, accuracy: 0.000_000_001)
            XCTAssertEqual(segments[642], ToneSegment(frequencyHz: 1200, duration: 0.009))
            XCTAssertEqual(
                segments.reduce(0) { $0 + $1.duration },
                lineDuration,
                accuracy: 0.000_000_1,
                mode.displayName
            )
        }
    }

    func testRobot36AlternatesSeparatorAndChromaChannel() throws {
        let image = solidImage(for: .robot36Color, pixel: .red)
        let even = try SSTVLineEncoder.segments(for: image, mode: .robot36Color, row: 0)
        let odd = try SSTVLineEncoder.segments(for: image, mode: .robot36Color, row: 1)

        XCTAssertEqual(even.count, 644)
        XCTAssertEqual(even[322], ToneSegment(frequencyHz: 1500, duration: 0.0045))
        XCTAssertEqual(odd[322], ToneSegment(frequencyHz: 2300, duration: 0.0045))
        XCTAssertEqual(even[323], ToneSegment(frequencyHz: 1900, duration: 0.0015))
        XCTAssertGreaterThan(even[324].frequencyHz, odd[324].frequencyHz)
        XCTAssertEqual(even.reduce(0) { $0 + $1.duration }, 0.150, accuracy: 0.000_000_1)
    }

    func testRobot72SequenceAndLineDuration() throws {
        let image = solidImage(for: .robot72Color, pixel: .blue)
        let segments = try SSTVLineEncoder.segments(for: image, mode: .robot72Color, row: 0)

        XCTAssertEqual(segments.count, 966)
        XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1200, duration: 0.009))
        XCTAssertEqual(segments[1], ToneSegment(frequencyHz: 1500, duration: 0.003))
        XCTAssertEqual(segments[322], ToneSegment(frequencyHz: 1500, duration: 0.0045))
        XCTAssertEqual(segments[323], ToneSegment(frequencyHz: 1900, duration: 0.0015))
        XCTAssertEqual(segments[644], ToneSegment(frequencyHz: 2300, duration: 0.0045))
        XCTAssertEqual(segments[645], ToneSegment(frequencyHz: 1500, duration: 0.0015))
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.300, accuracy: 0.000_000_1)
    }

    func testPDRadioLineCarriesTwoLumaRowsAndTheirAveragedChroma() throws {
        let mode = SSTVMode.pd50
        let raster = image(width: mode.width, height: mode.height) { x, y in
            if x == 0, y == 0 { return .red }
            if x == 0, y == 1 { return .blue }
            return .black
        }
        let segments = try SSTVLineEncoder.segments(for: raster, mode: mode, row: 0)
        let red = SSTVColor.robotComponents(for: .red)
        let blue = SSTVColor.robotComponents(for: .blue)

        XCTAssertEqual(segments.count, 1_282)
        XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1200, duration: 0.020))
        XCTAssertEqual(segments[1], ToneSegment(frequencyHz: 1500, duration: 0.00208))
        XCTAssertEqual(
            segments[2].frequencyHz,
            SSTVModulation.frequency(for: red.y),
            accuracy: 0.001
        )
        XCTAssertEqual(
            segments[322].frequencyHz,
            SSTVModulation.frequency(for: (red.redDifference + blue.redDifference) / 2),
            accuracy: 0.001
        )
        XCTAssertEqual(
            segments[642].frequencyHz,
            SSTVModulation.frequency(for: (red.blueDifference + blue.blueDifference) / 2),
            accuracy: 0.001
        )
        XCTAssertEqual(
            segments[962].frequencyHz,
            SSTVModulation.frequency(for: blue.y),
            accuracy: 0.001
        )
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.388160, accuracy: 0.000_000_1)
    }

    func testEveryPDVariantUsesFourEqualScansPerRadioLine() throws {
        let modes: [SSTVMode] = [.pd50, .pd90, .pd120, .pd160, .pd180, .pd240, .pd290]

        for mode in modes {
            let segments = try SSTVLineEncoder.segments(
                for: solidImage(for: mode),
                mode: mode,
                row: 0
            )
            XCTAssertEqual(segments.count, 2 + 4 * mode.width, mode.displayName)
            XCTAssertEqual(
                segments.reduce(0) { $0 + $1.duration },
                mode.lineDuration,
                accuracy: 0.000_000_1,
                mode.displayName
            )
        }
    }

    func testWraaseSequenceIsSyncPorchRedGreenBlueWithoutSeparators() throws {
        let pixel = RGBPixel(red: 255, green: 127, blue: 31)
        let image = solidImage(for: .wraaseSC2180, pixel: pixel)
        let segments = try SSTVLineEncoder.segments(
            for: image,
            mode: .wraaseSC2180,
            row: 0
        )

        XCTAssertEqual(segments.count, 962)
        XCTAssertEqual(segments[0], ToneSegment(frequencyHz: 1200, duration: 0.0055225))
        XCTAssertEqual(segments[1], ToneSegment(frequencyHz: 1500, duration: 0.0005))
        XCTAssertEqual(segments[2].frequencyHz, 2300, accuracy: 0.001)
        XCTAssertEqual(segments[322].frequencyHz, 1898.431_373, accuracy: 0.001)
        XCTAssertEqual(segments[642].frequencyHz, 1597.254_902, accuracy: 0.001)
        XCTAssertEqual(segments[2].duration, 0.235 / 320, accuracy: 0.000_000_001)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.duration }, 0.7110225, accuracy: 0.000_000_1)
    }

    func testPDRowParameterCountsRadioLinesRatherThanRasterRows() throws {
        let image = solidImage(for: .pd50)

        XCTAssertNoThrow(
            try SSTVLineEncoder.segments(for: image, mode: .pd50, row: 127)
        )
        XCTAssertThrowsError(
            try SSTVLineEncoder.segments(for: image, mode: .pd50, row: 128)
        )
    }

    func testRejectsMismatchedImageDimensionsAndInvalidRows() {
        let wrong = try! RGBImage(width: 1, height: 1, pixels: [.black])

        XCTAssertThrowsError(
            try SSTVLineEncoder.segments(for: wrong, mode: .robot36Color, row: 0)
        )
        XCTAssertThrowsError(
            try SSTVLineEncoder.segments(
                for: solidImage(for: .robot36Color),
                mode: .robot36Color,
                row: 240
            )
        )
    }
}
