import Foundation

/// Stateful quadrature FM demodulator. Keeping the filter and oscillator state
/// makes the output invariant to the input chunk boundaries used by AVAudioEngine.
struct SSTVFrequencyDemodulator: Sendable {
    let sampleRate: Int
    let latencySamples: Int

    private let centerFrequency = 1_900.0
    private let oscillatorStep: Double
    private let smoothing: Double

    private var oscillatorPhase = 0.0
    private var i1 = 0.0
    private var i2 = 0.0
    private var i3 = 0.0
    private var q1 = 0.0
    private var q2 = 0.0
    private var q3 = 0.0
    private var previousBasebandPhase = 0.0
    private var hasPreviousPhase = false

    init(sampleRate: Int) throws {
        guard sampleRate >= 6_000 else {
            throw SSTVDecodeError.invalidSampleRate(sampleRate)
        }
        self.sampleRate = sampleRate
        oscillatorStep = 2 * Double.pi * centerFrequency / Double(sampleRate)

        let cutoff = min(1_600.0, Double(sampleRate) * 0.2)
        smoothing = 1 - exp(-2 * Double.pi * cutoff / Double(sampleRate))
        latencySamples = max(0, Int((3 * (1 - smoothing) / smoothing).rounded()))
    }

    mutating func process(_ samples: [Float]) -> [Float] {
        var output: [Float] = []
        output.reserveCapacity(samples.count)

        for input in samples {
            let value = Double(input)
            let mixedI = 2 * value * cos(oscillatorPhase)
            let mixedQ = -2 * value * sin(oscillatorPhase)

            oscillatorPhase += oscillatorStep
            if oscillatorPhase >= 2 * Double.pi {
                oscillatorPhase.formTruncatingRemainder(dividingBy: 2 * Double.pi)
            }

            i1 += smoothing * (mixedI - i1)
            q1 += smoothing * (mixedQ - q1)
            i2 += smoothing * (i1 - i2)
            q2 += smoothing * (q1 - q2)
            i3 += smoothing * (i2 - i3)
            q3 += smoothing * (q2 - q3)

            let magnitudeSquared = i3 * i3 + q3 * q3
            guard magnitudeSquared > 0.000_000_01 else {
                hasPreviousPhase = false
                output.append(0)
                continue
            }

            let phase = atan2(q3, i3)
            guard hasPreviousPhase else {
                previousBasebandPhase = phase
                hasPreviousPhase = true
                output.append(Float(centerFrequency))
                continue
            }

            var phaseDelta = phase - previousBasebandPhase
            previousBasebandPhase = phase
            if phaseDelta > Double.pi {
                phaseDelta -= 2 * Double.pi
            } else if phaseDelta < -Double.pi {
                phaseDelta += 2 * Double.pi
            }

            let frequency = centerFrequency
                + phaseDelta * Double(sampleRate) / (2 * Double.pi)
            output.append(frequency.isFinite ? Float(frequency) : 0)
        }

        return output
    }
}
