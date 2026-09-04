import CoreGraphics
import XCTest
@testable import SSTVEncoder

final class CropGeometryTests: XCTestCase {
    func testAspectFillScaleExpandsWideImageUntilCropHeightIsCovered() {
        let geometry = CropGeometry(
            imageSize: CGSize(width: 400, height: 200),
            cropSize: CGSize(width: 320, height: 240)
        )

        XCTAssertEqual(geometry.aspectFillScale, 1.2, accuracy: 0.000_001)

        let transform = geometry.clampedTransform(zoom: 1, offset: .zero)
        XCTAssertEqual(transform.zoom, 1, accuracy: 0.000_001)
        XCTAssertEqual(transform.offset.width, 0, accuracy: 0.000_001)
        XCTAssertEqual(transform.offset.height, 0, accuracy: 0.000_001)
    }

    func testAspectFillScaleExpandsTallImageUntilCropWidthIsCovered() {
        let geometry = CropGeometry(
            imageSize: CGSize(width: 200, height: 400),
            cropSize: CGSize(width: 320, height: 240)
        )

        XCTAssertEqual(geometry.aspectFillScale, 1.6, accuracy: 0.000_001)
    }

    func testZoomCannotGoBelowAspectFillAndOffsetUsesTheClampedZoom() {
        let geometry = CropGeometry(
            imageSize: CGSize(width: 400, height: 200),
            cropSize: CGSize(width: 320, height: 240)
        )

        let transform = geometry.clampedTransform(
            zoom: 0.25,
            offset: CGSize(width: 500, height: 500)
        )

        // At aspect fill the rendered image is 480 x 240. Its horizontal
        // overhang is 160 points total, and there is no vertical overhang.
        XCTAssertEqual(transform.zoom, 1, accuracy: 0.000_001)
        XCTAssertEqual(transform.offset.width, 80, accuracy: 0.000_001)
        XCTAssertEqual(transform.offset.height, 0, accuracy: 0.000_001)
    }

    func testOffsetIsClampedToEveryEdgeAtTheCurrentZoom() {
        let geometry = CropGeometry(
            imageSize: CGSize(width: 400, height: 200),
            cropSize: CGSize(width: 320, height: 240)
        )

        let positive = geometry.clampedTransform(
            zoom: 2,
            offset: CGSize(width: 1_000, height: 1_000)
        )
        let negative = geometry.clampedTransform(
            zoom: 2,
            offset: CGSize(width: -1_000, height: -1_000)
        )

        // 400 x 200, aspect-filled by 1.2 and zoomed by 2, renders as
        // 960 x 480. Half of the overflow is therefore 320 x 120.
        XCTAssertEqual(positive.offset.width, 320, accuracy: 0.000_001)
        XCTAssertEqual(positive.offset.height, 120, accuracy: 0.000_001)
        XCTAssertEqual(negative.offset.width, -320, accuracy: 0.000_001)
        XCTAssertEqual(negative.offset.height, -120, accuracy: 0.000_001)
    }

    func testExactAspectRatioStillAllowsPanningAfterZooming() {
        let geometry = CropGeometry(
            imageSize: CGSize(width: 640, height: 480),
            cropSize: CGSize(width: 320, height: 240)
        )

        XCTAssertEqual(geometry.aspectFillScale, 0.5, accuracy: 0.000_001)

        let transform = geometry.clampedTransform(
            zoom: 1.5,
            offset: CGSize(width: 1_000, height: -1_000)
        )

        XCTAssertEqual(transform.offset.width, 80, accuracy: 0.000_001)
        XCTAssertEqual(transform.offset.height, -60, accuracy: 0.000_001)
    }
}
