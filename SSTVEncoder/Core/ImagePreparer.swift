import CoreGraphics
import SSTVKit
import UIKit

struct PreparedImage {
    let preview: UIImage
    let raster: RGBImage
}

enum ImagePreparationError: LocalizedError {
    case emptyImage
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "所选图片没有可用的像素。"
        case .renderingFailed:
            return "无法为当前 SSTV 模式准备图片。"
        }
    }
}

enum ImagePreparer {
    static func prepare(
        image: UIImage,
        mode: SSTVMode,
        selection: CropSelection,
        overlays: [TransmitTextOverlay] = []
    ) throws -> PreparedImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw ImagePreparationError.emptyImage
        }

        let targetSize = CGSize(width: mode.width, height: mode.height)
        let geometry = CropGeometry(imageSize: sourceSize, cropSize: targetSize)
        let requestedOffset = CGSize(
            width: selection.normalizedOffset.width * targetSize.width,
            height: selection.normalizedOffset.height * targetSize.height
        )
        let transform = geometry.clampedTransform(
            zoom: selection.zoom,
            offset: requestedOffset
        )
        let scale = geometry.aspectFillScale * transform.zoom
        let drawSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let drawRect = CGRect(
            x: (targetSize.width - drawSize.width) / 2 + transform.offset.width,
            y: (targetSize.height - drawSize.height) / 2 + transform.offset.height,
            width: drawSize.width,
            height: drawSize.height
        )

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        rendererFormat.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
            for overlay in overlays where !overlay.text.isEmpty {
                draw(overlay, in: targetSize)
            }
        }

        guard let sourceCGImage = rendered.cgImage else {
            throw ImagePreparationError.renderingFailed
        }

        let width = mode.width
        let height = mode.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var previewCGImage: CGImage?
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        rgba.withUnsafeMutableBytes { bytes in
            guard let colorSpace,
                  let context = CGContext(
                      data: bytes.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                          | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return
            }
            context.draw(
                sourceCGImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            previewCGImage = context.makeImage()
        }

        guard let previewCGImage else {
            throw ImagePreparationError.renderingFailed
        }

        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(width * height)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            pixels.append(
                RGBPixel(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
            )
        }

        return PreparedImage(
            preview: UIImage(cgImage: previewCGImage, scale: 1, orientation: .up),
            raster: try RGBImage(width: width, height: height, pixels: pixels)
        )
    }

    private static func draw(_ overlay: TransmitTextOverlay, in size: CGSize) {
        let text = String(overlay.text.prefix(32)) as NSString
        var pointSize = min(max(size.width * 0.075, 16), 30)
        var attributes: [NSAttributedString.Key: Any] = [:]
        var textSize = CGSize.zero
        repeat {
            attributes = [
                .font: UIFont.systemFont(ofSize: pointSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -14,
            ]
            textSize = text.size(withAttributes: attributes)
            pointSize -= 1
        } while textSize.width > size.width - 12 && pointSize >= 12

        let x = min(max(overlay.position.x * size.width - textSize.width / 2, 6),
                    max(6, size.width - textSize.width - 6))
        let y = min(max(overlay.position.y * size.height - textSize.height / 2, 6),
                    max(6, size.height - textSize.height - 6))
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
}
