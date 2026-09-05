import Foundation

/// Stateful quadrature FM demodulator with a linear-phase image-rejection FIR.
/// The old three single-pole filters left enough double-carrier ripple to turn
/// a constant tone into different colors inside short Robot/PD pixel windows.
/// Filter history and the oscillator persist across audio chunk boundaries.
struct SSTVFrequencyDemodulator: Sendable {
    let sampleRate: Int
    let latencySamples: Int

    private let centerFrequency = 1_900.0
    private let oscillatorStep: Double
    private let coefficients: [Double]

    private var oscillatorPhase = 0.0
    private var inPhase: [Double]
    private var quadrature: [Double]
    private var writeIndex = 0
    private var previousBasebandPhase = 0.0
    private var hasPreviousPhase = false

    init(sampleRate: Int) throws {
        guard sampleRate >= 6_000, sampleRate <= 384_000 else {
            throw SSTVDecodeError.invalidSampleRate(sampleRate)
        }
        self.sampleRate = sampleRate
        oscillatorStep = 2 * Double.pi * centerFrequency / Double(sampleRate)

        // An odd, symmetric Blackman-windowed sinc has an exact integer group
        // delay. At 48 kHz this is 161 taps / 80 samples; it rejects the mixer
        // image without estimating a tone-dependent IIR delay. Narrow the cutoff
        // for low sample rates, where the sum-frequency image folds back down.
        let half = max(15, Int(ceil(Double(sampleRate) / 600)))
        let cutoff = min(1_600.0, Double(sampleRate) / 2 - 2_000) / Double(sampleRate)
        var taps: [Double] = []
        taps.reserveCapacity(2 * half + 1)
        for index in 0...(2 * half) {
            let offset = Double(index - half)
            let sinc = offset == 0 ? 2 * cutoff
                : sin(2 * Double.pi * cutoff * offset) / (Double.pi * offset)
            let angle = Double.pi * Double(index) / Double(half)
            let window = 0.42 - 0.5 * cos(angle) + 0.08 * cos(2 * angle)
            taps.append(sinc * window)
        }
        let gain = taps.reduce(0, +)
        coefficients = taps.map { $0 / gain }
        latencySamples = half
        inPhase = Array(repeating: 0, count: taps.count)
        quadrature = Array(repeating: 0, count: taps.count)
    }

    mutating func process(_ samples: [Float]) -> [Float] {
        var output: [Float] = []
        output.reserveCapacity(samples.count)

        for input in samples {
            let value = input.isFinite ? Double(input) : 0
            inPhase[writeIndex] = 2 * value * cos(oscillatorPhase)
            quadrature[writeIndex] = -2 * value * sin(oscillatorPhase)

            oscillatorPhase += oscillatorStep
            if oscillatorPhase >= 2 * Double.pi {
                oscillatorPhase.formTruncatingRemainder(dividingBy: 2 * Double.pi)
            }

            // Exploit coefficient symmetry and wrap indices without division
            // inside the convolution. No allocations occur per input sample.
            var left = writeIndex
            var right = writeIndex + 1
            if right == coefficients.count { right = 0 }
            var filteredI = 0.0
            var filteredQ = 0.0
            for tap in 0..<latencySamples {
                let coefficient = coefficients[tap]
                filteredI += coefficient * (inPhase[left] + inPhase[right])
                filteredQ += coefficient * (quadrature[left] + quadrature[right])
                left = left == 0 ? coefficients.count - 1 : left - 1
                right += 1
                if right == coefficients.count { right = 0 }
            }
            filteredI += coefficients[latencySamples] * inPhase[left]
            filteredQ += coefficients[latencySamples] * quadrature[left]
            writeIndex += 1
            if writeIndex == coefficients.count { writeIndex = 0 }

            let magnitudeSquared = filteredI * filteredI + filteredQ * filteredQ
            guard magnitudeSquared > 0.000_000_01 else {
                hasPreviousPhase = false
                output.append(0)
                continue
            }

            let phase = atan2(filteredQ, filteredI)
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
