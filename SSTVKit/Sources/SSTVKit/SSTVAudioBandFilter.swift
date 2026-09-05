import Foundation

/// Reject upper audio harmonics before quadrature mixing. A 1500 Hz tone's
/// second harmonic otherwise lands at +1100 Hz after the 1900 Hz mixer, inside
/// its low-pass band, and corrupts the instantaneous pixel frequency.
struct SSTVAudioBandFilter: Sendable {
    let latencySamples: Int
    private let coefficients: [Double]
    private var history: [Double]
    private var cursor = 0

    init(sampleRate: Int) {
        let half = max(15, Int(ceil(Double(sampleRate) / 480)))
        let cutoff = 2_500.0 / Double(sampleRate)
        var taps: [Double] = []
        taps.reserveCapacity(2 * half + 1)
        for index in 0...(2 * half) {
            let offset = Double(index - half)
            let sinc = offset == 0 ? 2 * cutoff
                : sin(2 * Double.pi * cutoff * offset) / (Double.pi * offset)
            let angle = Double.pi * Double(index) / Double(half)
            taps.append(sinc * (0.42 - 0.5 * cos(angle) + 0.08 * cos(2 * angle)))
        }
        let gain = taps.reduce(0, +)
        coefficients = taps.map { $0 / gain }
        history = Array(repeating: 0, count: taps.count)
        latencySamples = half
    }

    mutating func process(_ value: Double) -> Double {
        history[cursor] = value
        var left = cursor
        var right = cursor + 1
        if right == history.count { right = 0 }
        var result = 0.0
        for tap in 0..<latencySamples {
            result += coefficients[tap] * (history[left] + history[right])
            left = left == 0 ? history.count - 1 : left - 1
            right += 1
            if right == history.count { right = 0 }
        }
        result += coefficients[latencySamples] * history[left]
        cursor += 1
        if cursor == history.count { cursor = 0 }
        return result
    }
}
