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
        XCTAssertEqual(previewPixel(in: prepared.preview, x: 10, y: 10), prepared.raster[10, 10])
        XCTAssertEqual(previewPixel(in: prepared.preview, x: 10, y: 230), prepared.raster[10, 230])
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

    func testHighestResolutionPDModeProducesItsExactRasterSize() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 100, height: 100),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let prepared = try ImagePreparer.prepare(
            image: source,
            mode: .pd290,
            selection: .identity
        )

        XCTAssertEqual(prepared.preview.cgImage?.width, 800)
        XCTAssertEqual(prepared.preview.cgImage?.height, 616)
        XCTAssertEqual(prepared.raster.width, 800)
        XCTAssertEqual(prepared.raster.height, 616)
        XCTAssertEqual(prepared.raster[400, 308], .white)
    }

    private func previewPixel(in image: UIImage, x: Int, y: Int) -> RGBPixel? {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              x >= 0,
              y >= 0,
              x < cgImage.width,
              y < cgImage.height else {
            return nil
        }

        let offset = y * cgImage.bytesPerRow + x * 4
        return RGBPixel(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2]
        )
    }
}
