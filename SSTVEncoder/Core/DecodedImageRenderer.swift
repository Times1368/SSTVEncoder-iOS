import CoreGraphics
import Foundation
import SSTVKit
import UIKit

enum DecodedImageRenderer {
    static func image(from raster: RGBImage) throws -> UIImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(raster.pixels.count * 4)
        for pixel in raster.pixels {
            bytes.append(pixel.redValue)
            bytes.append(pixel.greenValue)
            bytes.append(pixel.blueValue)
            bytes.append(255)
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: raster.width,
                  height: raster.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: raster.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw DecodedImageRenderingError.couldNotCreateImage
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

enum DecodedImageRenderingError: LocalizedError {
    case couldNotCreateImage

    var errorDescription: String? {
        "无法生成解码图像预览。"
    }
}
