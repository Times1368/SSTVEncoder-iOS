import Foundation

public enum SSTVEncodingError: Error, Sendable, Equatable {
    case invalidSampleRate(Int)
    case invalidAmplitude(Double)
    case imageSizeMismatch(
        expectedWidth: Int,
        expectedHeight: Int,
        actualWidth: Int,
        actualHeight: Int
    )
    case rowOutOfRange(row: Int, height: Int)
}

public enum SSTVLineEncoder {
    public static func framePrefix(for mode: SSTVMode) -> [ToneSegment] {
        switch mode {
        case .scottieS1:
            return [ToneSegment(frequencyHz: 1200, duration: 0.009)]
        case .robot36Color, .robot72Color, .martinM1:
            return []
        }
    }

    public static func segments(
        for image: RGBImage,
        mode: SSTVMode,
        row: Int
    ) throws -> [ToneSegment] {
        try validate(image: image, mode: mode, row: row)

        switch mode {
        case .robot36Color:
            return robot36Segments(for: image, row: row)
        case .robot72Color:
            return robot72Segments(for: image, row: row)
        case .martinM1:
            return martinSegments(for: image, row: row)
        case .scottieS1:
            return scottieSegments(for: image, row: row)
        }
    }

    private static func validate(image: RGBImage, mode: SSTVMode, row: Int) throws {
        guard image.width == mode.width, image.height == mode.height else {
            throw SSTVEncodingError.imageSizeMismatch(
                expectedWidth: mode.width,
                expectedHeight: mode.height,
                actualWidth: image.width,
                actualHeight: image.height
            )
        }
        guard row >= 0, row < mode.height else {
            throw SSTVEncodingError.rowOutOfRange(row: row, height: mode.height)
        }
    }

    private static func robot36Segments(for image: RGBImage, row: Int) -> [ToneSegment] {
        var result: [ToneSegment] = []
        result.reserveCapacity(644)
        result.append(ToneSegment(frequencyHz: 1200, duration: 0.009))
        result.append(ToneSegment(frequencyHz: 1500, duration: 0.003))

        let luminanceDuration = 0.088 / Double(image.width)
        for x in 0..<image.width {
            let component = SSTVColor.robotComponents(for: image[x, row]).y
            result.append(ToneSegment(
                frequencyHz: SSTVModulation.frequency(for: component),
                duration: luminanceDuration
            ))
        }

        let usesRedDifference = row.isMultiple(of: 2)
        result.append(ToneSegment(
            frequencyHz: usesRedDifference ? 1500 : 2300,
            duration: 0.0045
        ))
        result.append(ToneSegment(frequencyHz: 1900, duration: 0.0015))

        let chromaDuration = 0.044 / Double(image.width)
        let topRow = row - row % 2
        for left in stride(from: 0, to: image.width, by: 2) {
            let topLeft = SSTVColor.robotComponents(for: image[left, topRow])
            let topRight = SSTVColor.robotComponents(for: image[left + 1, topRow])
            let bottomLeft = SSTVColor.robotComponents(for: image[left, topRow + 1])
            let bottomRight = SSTVColor.robotComponents(for: image[left + 1, topRow + 1])
            let value: Double
            if usesRedDifference {
                value = (
                    topLeft.redDifference + topRight.redDifference
                        + bottomLeft.redDifference + bottomRight.redDifference
                ) / 4
            } else {
                value = (
                    topLeft.blueDifference + topRight.blueDifference
                        + bottomLeft.blueDifference + bottomRight.blueDifference
                ) / 4
            }
            let segment = ToneSegment(
                frequencyHz: SSTVModulation.frequency(for: value),
                duration: chromaDuration
            )
            result.append(segment)
            result.append(segment)
        }
        return result
    }

    private static func robot72Segments(for image: RGBImage, row: Int) -> [ToneSegment] {
        var result: [ToneSegment] = []
        result.reserveCapacity(966)
        result.append(ToneSegment(frequencyHz: 1200, duration: 0.009))
        result.append(ToneSegment(frequencyHz: 1500, duration: 0.003))

        let luminanceDuration = 0.138 / Double(image.width)
        for x in 0..<image.width {
            let component = SSTVColor.robotComponents(for: image[x, row]).y
            result.append(ToneSegment(
                frequencyHz: SSTVModulation.frequency(for: component),
                duration: luminanceDuration
            ))
        }

        result.append(ToneSegment(frequencyHz: 1500, duration: 0.0045))
        result.append(ToneSegment(frequencyHz: 1900, duration: 0.0015))
        appendRobot72Chroma(
            to: &result,
            image: image,
            row: row,
            keyPath: \.redDifference
        )

        result.append(ToneSegment(frequencyHz: 2300, duration: 0.0045))
        result.append(ToneSegment(frequencyHz: 1500, duration: 0.0015))
        appendRobot72Chroma(
            to: &result,
            image: image,
            row: row,
            keyPath: \.blueDifference
        )
        return result
    }

    private static func appendRobot72Chroma(
        to result: inout [ToneSegment],
        image: RGBImage,
        row: Int,
        keyPath: KeyPath<RobotColorComponents, Double>
    ) {
        let duration = 0.069 / Double(image.width)
        for left in stride(from: 0, to: image.width, by: 2) {
            let first = SSTVColor.robotComponents(for: image[left, row])[keyPath: keyPath]
            let second = SSTVColor.robotComponents(for: image[left + 1, row])[keyPath: keyPath]
            let segment = ToneSegment(
                frequencyHz: SSTVModulation.frequency(for: (first + second) / 2),
                duration: duration
            )
            result.append(segment)
            result.append(segment)
        }
    }

    private static func martinSegments(for image: RGBImage, row: Int) -> [ToneSegment] {
        var result: [ToneSegment] = []
        result.reserveCapacity(965)
        result.append(ToneSegment(frequencyHz: 1200, duration: 0.004862))
        result.append(ToneSegment(frequencyHz: 1500, duration: 0.000572))

        let pixelDuration = 0.146432 / Double(image.width)
        for channel in [RGBChannel.green, .blue, .red] {
            appendRGBScan(
                to: &result,
                image: image,
                row: row,
                channel: channel,
                pixelDuration: pixelDuration
            )
            result.append(ToneSegment(frequencyHz: 1500, duration: 0.000572))
        }
        return result
    }

    private static func scottieSegments(for image: RGBImage, row: Int) -> [ToneSegment] {
        var result: [ToneSegment] = []
        result.reserveCapacity(964)
        let pixelDuration = 0.138240 / Double(image.width)

        result.append(ToneSegment(frequencyHz: 1500, duration: 0.0015))
        appendRGBScan(
            to: &result,
            image: image,
            row: row,
            channel: .green,
            pixelDuration: pixelDuration
        )
        result.append(ToneSegment(frequencyHz: 1500, duration: 0.0015))
        appendRGBScan(
            to: &result,
            image: image,
            row: row,
            channel: .blue,
            pixelDuration: pixelDuration
        )
        result.append(ToneSegment(frequencyHz: 1200, duration: 0.009))
        result.append(ToneSegment(frequencyHz: 1500, duration: 0.0015))
        appendRGBScan(
            to: &result,
            image: image,
            row: row,
            channel: .red,
            pixelDuration: pixelDuration
        )
        return result
    }

    private static func appendRGBScan(
        to result: inout [ToneSegment],
        image: RGBImage,
        row: Int,
        channel: RGBChannel,
        pixelDuration: Double
    ) {
        for x in 0..<image.width {
            result.append(ToneSegment(
                frequencyHz: SSTVColor.frequency(for: channel, pixel: image[x, row]),
                duration: pixelDuration
            ))
        }
    }
}
