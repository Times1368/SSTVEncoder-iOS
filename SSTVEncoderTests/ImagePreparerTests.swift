import SSTVKit
import UIKit
import XCTest
@testable import SSTVEncoder

@MainActor
final class ImagePreparerTests: XCTestCase {
    func testPreparedPreviewAndRasterUseTheSameExactRobotPixels() throws {
        let size = CGSize(width: 320, height: 240)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 120))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 120, width: 320, height: 120))
        }

        let prepared = try ImagePreparer.prepare(
            image: source,
            mode: .robot36Color,
            selection: .identity
        )

        XCTAssertEqual(prepared.preview.cgImage?.width, 320)
        XCTAssertEqual(prepared.preview.cgImage?.height, 240)
        XCTAssertEqual(prepared.raster.width, 320)
        XCTAssertEqual(prepared.raster.height, 240)
        XCTAssertEqual(prepared.raster[10, 10], .red)
        XCTAssertEqual(prepared.raster[10, 230], .blue)
    }

    func testModeChangeProducesTheExactMartinRasterSize() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 640, height: 480),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }

        let prepared = try ImagePreparer.prepare(
            image: source,
            mode: .martinM1,
            selection: .identity
        )

        XCTAssertEqual(prepared.preview.cgImage?.width, 320)
        XCTAssertEqual(prepared.preview.cgImage?.height, 256)
        XCTAssertEqual(prepared.raster.width, 320)
        XCTAssertEqual(prepared.raster.height, 256)
        XCTAssertEqual(prepared.raster[160, 128], .white)
    }
}

