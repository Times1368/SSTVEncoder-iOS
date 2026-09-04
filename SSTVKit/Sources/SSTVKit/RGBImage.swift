import Foundation

/// One 8-bit sRGB pixel.
public struct RGBPixel: Sendable, Equatable, Hashable {
    public let redValue: UInt8
    public let greenValue: UInt8
    public let blueValue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.redValue = red
        self.greenValue = green
        self.blueValue = blue
    }

    public static let black = RGBPixel(red: 0, green: 0, blue: 0)
    public static let white = RGBPixel(red: 255, green: 255, blue: 255)
    public static let red = RGBPixel(red: 255, green: 0, blue: 0)
    public static let green = RGBPixel(red: 0, green: 255, blue: 0)
    public static let blue = RGBPixel(red: 0, green: 0, blue: 255)
}

public enum RGBImageError: Error, Sendable, Equatable {
    case invalidDimensions(width: Int, height: Int)
    case pixelCountMismatch(expected: Int, actual: Int)
}

/// A validated, row-major RGB raster.
public struct RGBImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let pixels: [RGBPixel]

    public init(width: Int, height: Int, pixels: [RGBPixel]) throws {
        guard width > 0, height > 0 else {
            throw RGBImageError.invalidDimensions(width: width, height: height)
        }

        let (expectedCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw RGBImageError.invalidDimensions(width: width, height: height)
        }
        guard pixels.count == expectedCount else {
            throw RGBImageError.pixelCountMismatch(expected: expectedCount, actual: pixels.count)
        }

        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> RGBPixel {
        pixels[y * width + x]
    }
}
