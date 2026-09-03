import XCTest
@testable import SSTVKit

final class ColorConversionTests: XCTestCase {
    func testVideoLevelMapsLinearlyToSSTVFrequencies() {
        XCTAssertEqual(SSTVModulation.frequency(for: 0), 1500, accuracy: 0.000_001)
        XCTAssertEqual(SSTVModulation.frequency(for: 127.5), 1900, accuracy: 0.000_001)
        XCTAssertEqual(SSTVModulation.frequency(for: 255), 2300, accuracy: 0.000_001)
    }

    func testBT601BlackWhiteAndPrimaryComponents() {
        let black = SSTVColor.robotComponents(for: .black)
        XCTAssertEqual(black.y, 16, accuracy: 0.01)
        XCTAssertEqual(black.redDifference, 128, accuracy: 0.01)
        XCTAssertEqual(black.blueDifference, 128, accuracy: 0.01)

        let white = SSTVColor.robotComponents(for: .white)
        XCTAssertEqual(white.y, 235.05, accuracy: 0.1)
        XCTAssertEqual(white.redDifference, 128, accuracy: 0.1)
        XCTAssertEqual(white.blueDifference, 128, accuracy: 0.1)

        let red = SSTVColor.robotComponents(for: .red)
        XCTAssertEqual(red.y, 81.48, accuracy: 0.1)
        XCTAssertEqual(red.redDifference, 240.0, accuracy: 0.1)
        XCTAssertEqual(red.blueDifference, 90.20, accuracy: 0.1)
    }

    func testRobot36AveragesChromaAcrossTwoByTwoBlocks() throws {
        let mode = SSTVMode.robot36Color
        let raster = image(width: mode.width, height: mode.height) { x, y in
            switch (x, y) {
            case (0, 0): return .red
            case (1, 0): return .green
            case (0, 1): return .blue
            case (1, 1): return .white
            default: return .black
            }
        }
        let redSegments = try SSTVLineEncoder.segments(for: raster, mode: mode, row: 0)
        let blueSegments = try SSTVLineEncoder.segments(for: raster, mode: mode, row: 1)
        let pixels: [RGBPixel] = [.red, .green, .blue, .white]
        let expectedRed = pixels.map { SSTVColor.robotComponents(for: $0).redDifference }
            .reduce(0, +) / 4
        let expectedBlue = pixels.map { SSTVColor.robotComponents(for: $0).blueDifference }
            .reduce(0, +) / 4

        XCTAssertEqual(
            redSegments[324].frequencyHz,
            SSTVModulation.frequency(for: expectedRed),
            accuracy: 0.001
        )
        XCTAssertEqual(redSegments[324].frequencyHz, redSegments[325].frequencyHz, accuracy: 0.001)
        XCTAssertEqual(
            blueSegments[324].frequencyHz,
            SSTVModulation.frequency(for: expectedBlue),
            accuracy: 0.001
        )
        XCTAssertEqual(blueSegments[324].frequencyHz, blueSegments[325].frequencyHz, accuracy: 0.001)
    }

    func testRobot72AveragesChromaAcrossHorizontalPairs() throws {
        let mode = SSTVMode.robot72Color
        let raster = image(width: mode.width, height: mode.height) { x, _ in
            x == 0 ? .red : (x == 1 ? .blue : .black)
        }
        let segments = try SSTVLineEncoder.segments(for: raster, mode: mode, row: 0)
        let components = [RGBPixel.red, .blue].map { SSTVColor.robotComponents(for: $0) }
        let expectedRed = components.map(\.redDifference).reduce(0, +) / 2
        let expectedBlue = components.map(\.blueDifference).reduce(0, +) / 2

        XCTAssertEqual(
            segments[324].frequencyHz,
            SSTVModulation.frequency(for: expectedRed),
            accuracy: 0.001
        )
        XCTAssertEqual(segments[324].frequencyHz, segments[325].frequencyHz, accuracy: 0.001)
        XCTAssertEqual(
            segments[646].frequencyHz,
            SSTVModulation.frequency(for: expectedBlue),
            accuracy: 0.001
        )
        XCTAssertEqual(segments[646].frequencyHz, segments[647].frequencyHz, accuracy: 0.001)
    }
}

