import SSTVKit

/// Test-only input: native-size, row-major pixels without image IO or resizing.
public enum CoordinateFixture {
    public static let identifier = "coordinate-rgb-v1"
    public static let formula = "r=(x*8)%256;g=(y*8)%256;b=((x+y)*4)%256"

    public static func image(for mode: SSTVMode) throws -> RGBImage {
        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(mode.width * mode.height)
        for y in 0..<mode.height {
            for x in 0..<mode.width {
                pixels.append(RGBPixel(
                    red: UInt8((x &* 8) % 256),
                    green: UInt8((y &* 8) % 256),
                    blue: UInt8(((x &+ y) &* 4) % 256)
                ))
            }
        }
        return try RGBImage(width: mode.width, height: mode.height, pixels: pixels)
    }
}

public enum RowOrderStatus: String, Encodable {
    case consistent
    case reversed
    case inconclusive
}

public enum RowOrderError: Error {
    case mismatchedDimensions
}

/// A codec-only diagnostic, not a test of UIKit, PNG loading, or the App preview.
public struct RowOrderMeasurement: Encodable {
    public let status: RowOrderStatus
    public let sameOrderMeanAbsoluteError: Double
    public let reversedOrderMeanAbsoluteError: Double

    public static func compare(source: RGBImage, decoded: RGBImage) throws -> Self {
        guard source.width == decoded.width, source.height == decoded.height else {
            throw RowOrderError.mismatchedDimensions
        }
        var sameError = 0.0
        var reversedError = 0.0
        for y in 0..<source.height {
            for x in 0..<source.width {
                let pixel = decoded[x, y]
                sameError += distance(pixel, source[x, y])
                reversedError += distance(pixel, source[x, source.height - 1 - y])
            }
        }
        let count = Double(source.pixels.count) * 3
        sameError /= count
        reversedError /= count

        // Analog decoding is lossy. Require both a usable match and a clear
        // advantage over its reversed-row alternative; ambiguous data is not a pass.
        let status: RowOrderStatus
        if sameError < 48, sameError + 5 < reversedError {
            status = .consistent
        } else if reversedError < 48, reversedError + 5 < sameError {
            status = .reversed
        } else {
            status = .inconclusive
        }
        return Self(
            status: status,
            sameOrderMeanAbsoluteError: sameError,
            reversedOrderMeanAbsoluteError: reversedError
        )
    }

    private static func distance(_ lhs: RGBPixel, _ rhs: RGBPixel) -> Double {
        Double(abs(Int(lhs.redValue) - Int(rhs.redValue)))
            + Double(abs(Int(lhs.greenValue) - Int(rhs.greenValue)))
            + Double(abs(Int(lhs.blueValue) - Int(rhs.blueValue)))
    }
}
