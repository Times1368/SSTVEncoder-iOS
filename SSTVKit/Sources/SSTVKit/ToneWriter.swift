import Foundation

public struct ToneSegment: Sendable, Equatable {
    public let frequencyHz: Double
    public let duration: Double

    public init(frequencyHz: Double, duration: Double) {
        self.frequencyHz = frequencyHz
        self.duration = duration
    }
}

/// Writes tones on a cumulative sample clock while preserving oscillator phase.
public struct ToneWriter: Sendable {
    public let sampleRate: Int
    public let amplitude: Double
    public private(set) var samples: [Float]
    public private(set) var elapsedDuration: Double = 0
    public private(set) var phase: Double = 0

    public init(sampleRate: Int, amplitude: Double, capacity: Int = 0) {
        self.sampleRate = sampleRate
        self.amplitude = amplitude
        self.samples = []
        self.samples.reserveCapacity(max(0, capacity))
    }

    public mutating func append(_ segment: ToneSegment) {
        append(frequencyHz: segment.frequencyHz, duration: segment.duration)
    }

    public mutating func append<S: Sequence>(contentsOf segments: S) where S.Element == ToneSegment {
        for segment in segments {
            append(segment)
        }
    }

    public mutating func append(frequencyHz: Double, duration: Double) {
        guard sampleRate > 0,
              amplitude.isFinite,
              duration.isFinite,
              duration >= 0,
              frequencyHz.isFinite else { return }

        elapsedDuration += duration
        let targetCount = Int((elapsedDuration * Double(sampleRate)).rounded())
        let count = max(0, targetCount - samples.count)
        guard count > 0 else { return }

        let phaseIncrement = 2 * Double.pi * frequencyHz / Double(sampleRate)
        var currentPhase = phase
        for _ in 0..<count {
            samples.append(Float(sin(currentPhase) * amplitude))
            currentPhase += phaseIncrement
        }

        phase = currentPhase.truncatingRemainder(dividingBy: 2 * Double.pi)
        if phase < 0 {
            phase += 2 * Double.pi
        }
    }
}
