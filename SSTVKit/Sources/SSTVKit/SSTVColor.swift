import Foundation

public struct RobotColorComponents: Sendable, Equatable {
    public let y: Double
    public let redDifference: Double
    public let blueDifference: Double

    public init(y: Double, redDifference: Double, blueDifference: Double) {
        self.y = y
        self.redDifference = redDifference
        self.blueDifference = blueDifference
    }
}

public enum SSTVModulation {
    public static func frequency(for component: Double) -> Double {
        1500 + clamped(component) * 800 / 255
    }

    private static func clamped(_ value: Double) -> Double {
        min(255, max(0, value))
    }
}

public enum SSTVColor {
    public static func robotComponents(for pixel: RGBPixel) -> RobotColorComponents {
        let red = Double(pixel.redValue)
        let green = Double(pixel.greenValue)
        let blue = Double(pixel.blueValue)

        return RobotColorComponents(
            y: clamp(16 + (65.738 * red + 129.057 * green + 25.064 * blue) / 256),
            redDifference: clamp(128 + (112.439 * red - 94.154 * green - 18.285 * blue) / 256),
            blueDifference: clamp(128 + (-37.945 * red - 74.494 * green + 112.439 * blue) / 256)
        )
    }

    static func frequency(for channel: RGBChannel, pixel: RGBPixel) -> Double {
        let component: UInt8
        switch channel {
        case .red: component = pixel.redValue
        case .green: component = pixel.greenValue
        case .blue: component = pixel.blueValue
        }
        return SSTVModulation.frequency(for: Double(component))
    }

    private static func clamp(_ value: Double) -> Double {
        min(255, max(0, value))
    }
}

enum RGBChannel {
    case red
    case green
    case blue
}
