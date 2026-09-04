import XCTest
@testable import SSTVKit

final class RGBImageTests: XCTestCase {
    func testRejectsNonPositiveDimensionsAndWrongPixelCount() {
        XCTAssertThrowsError(try RGBImage(width: 0, height: 1, pixels: []))
        XCTAssertThrowsError(try RGBImage(width: 1, height: -1, pixels: []))
        XCTAssertThrowsError(try RGBImage(width: 2, height: 2, pixels: [.black]))
    }

    func testRejectsDimensionMultiplicationOverflowWithoutAllocating() {
        XCTAssertThrowsError(
            try RGBImage(width: .max, height: 2, pixels: [])
        ) { error in
            XCTAssertEqual(
                error as? RGBImageError,
                RGBImageError.invalidDimensions(width: .max, height: 2)
            )
        }
    }
}
