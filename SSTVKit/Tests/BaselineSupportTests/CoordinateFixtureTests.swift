import XCTest
import SSTVKit
@testable import BaselineSupport

final class CoordinateFixtureTests: XCTestCase {
    func testFixtureUsesTheCoordinateFormulaAtEveryNativePixel() throws {
        for mode in [SSTVMode.robot36Color, .martinM1, .pd120] {
            let image = try CoordinateFixture.image(for: mode)
            XCTAssertEqual(image.width, mode.width)
            XCTAssertEqual(image.height, mode.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    XCTAssertEqual(image[x, y], RGBPixel(
                        red: UInt8((x &* 8) % 256),
                        green: UInt8((y &* 8) % 256),
                        blue: UInt8(((x &+ y) &* 4) % 256)
                    ))
                }
            }
        }
    }

    func testFixtureIsDeterministic() throws {
        XCTAssertEqual(
            try CoordinateFixture.image(for: .robot36Color),
            try CoordinateFixture.image(for: .robot36Color)
        )
    }

    func testRowOrderRecognizesTheUnmodifiedRaster() throws {
        let image = try CoordinateFixture.image(for: .martinM1)
        let result = try RowOrderMeasurement.compare(source: image, decoded: image)
        XCTAssertEqual(result.status, .consistent)
        XCTAssertEqual(result.sameOrderMeanAbsoluteError, 0)
        XCTAssertGreaterThan(result.reversedOrderMeanAbsoluteError, 0)
    }

    func testRowOrderRecognizesAVerticallyReversedRaster() throws {
        let image = try CoordinateFixture.image(for: .pd120)
        let pixels = (0..<image.height).flatMap { y in
            (0..<image.width).map { x in image[x, image.height - 1 - y] }
        }
        let reversed = try RGBImage(width: image.width, height: image.height, pixels: pixels)
        let result = try RowOrderMeasurement.compare(source: image, decoded: reversed)
        XCTAssertEqual(result.status, .reversed)
        XCTAssertEqual(result.reversedOrderMeanAbsoluteError, 0)
    }

    func testAmbiguousRasterDoesNotClaimAConfirmedOrientation() throws {
        let image = try RGBImage(width: 8, height: 8, pixels: Array(repeating: .black, count: 64))
        let result = try RowOrderMeasurement.compare(source: image, decoded: image)
        XCTAssertEqual(result.status, .inconclusive)
    }

    func testMismatchedDimensionsAreRejected() throws {
        let source = try CoordinateFixture.image(for: .robot36Color)
        let decoded = try CoordinateFixture.image(for: .martinM1)
        XCTAssertThrowsError(try RowOrderMeasurement.compare(source: source, decoded: decoded))
    }
}
