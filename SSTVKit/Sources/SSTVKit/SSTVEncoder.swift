import Foundation

public struct PCMBuffer: Sendable, Equatable {
    public let sampleRate: Int
    public let samples: [Float]

    public init(sampleRate: Int, samples: [Float]) throws {
        guard sampleRate > 0 else {
            throw SSTVEncodingError.invalidSampleRate(sampleRate)
        }
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var duration: Double {
        Double(samples.count) / Double(sampleRate)
    }
}

public struct SSTVEncoder: Sendable {
    public let sampleRate: Int
    public let amplitude: Double

    public init(sampleRate: Int = 48_000, amplitude: Double = 0.8) throws {
        guard sampleRate > 0 else {
            throw SSTVEncodingError.invalidSampleRate(sampleRate)
        }
        guard amplitude.isFinite, amplitude >= 0, amplitude <= 1 else {
            throw SSTVEncodingError.invalidAmplitude(amplitude)
        }
        self.sampleRate = sampleRate
        self.amplitude = amplitude
    }

    public func encode(
        _ image: RGBImage,
        mode: SSTVMode,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> PCMBuffer {
        try Task.checkCancellation()
        guard image.width == mode.width, image.height == mode.height else {
            throw SSTVEncodingError.imageSizeMismatch(
                expectedWidth: mode.width,
                expectedHeight: mode.height,
                actualWidth: image.width,
                actualHeight: image.height
            )
        }

        var writer = ToneWriter(
            sampleRate: sampleRate,
            amplitude: amplitude,
            capacity: mode.sampleCount(at: sampleRate)
        )
        writer.append(contentsOf: SSTVHeader.segments(visCode: mode.visCode))
        writer.append(contentsOf: SSTVLineEncoder.framePrefix(for: mode))

        for row in 0..<mode.height {
            try Task.checkCancellation()
            let segments = try SSTVLineEncoder.segments(for: image, mode: mode, row: row)
            writer.append(contentsOf: segments)
            if let progress {
                await progress(Double(row + 1) / Double(mode.height))
            }
        }
        try Task.checkCancellation()

        return try PCMBuffer(sampleRate: sampleRate, samples: writer.samples)
    }
}
