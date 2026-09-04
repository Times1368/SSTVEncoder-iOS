import Foundation

final class HFFaxAssembler {
    let profile: HFFaxProfile
    let sampleRate: Int
    let latencySamples: Int

    private var rows: [[UInt8]] = []
    private var accumulatedBrightness: [Double]
    private var horizontalShift = 0

    init(profile: HFFaxProfile, sampleRate: Int, latencySamples: Int) {
        self.profile = profile
        self.sampleRate = sampleRate
        self.latencySamples = latencySamples
        accumulatedBrightness = Array(repeating: 0, count: profile.width)
    }

    var completedRows: Int { rows.count }
    var isComplete: Bool { rows.count >= profile.maximumRows }

    func decodeAvailable(frequencies: [Float]) throws -> Bool {
        let sampler = SSTVToneSampler(
            frequencies: frequencies,
            sampleRate: sampleRate,
            latencySamples: latencySamples
        )
        let lineSamples = sampler.samples(for: profile.lineDuration)
        guard profile.width > 0, lineSamples > 0 else { return false }
        var changed = false

        while rows.count < profile.maximumRows {
            try Task.checkCancellation()
            let lineStart = rows.count * lineSamples
            guard lineStart + lineSamples <= sampler.availableRawSampleCount else {
                break
            }

            var row: [UInt8] = []
            row.reserveCapacity(profile.width)
            for x in 0..<profile.width {
                let level = sampler.component(
                    scanStart: lineStart,
                    scanDuration: profile.lineDuration,
                    pixel: x,
                    width: profile.width,
                    frequencyOffset: 0
                )
                let value = UInt8(min(255, max(0, Int(level.rounded()))))
                row.append(value)
                accumulatedBrightness[x] = accumulatedBrightness[x] * 0.99
                    + Double(value) / 255 * 0.01
            }
            rows.append(row)
            updateHorizontalShiftIfStable()
            changed = true
        }

        return changed
    }

    func snapshot() throws -> SSTVDecodedFrame {
        guard !rows.isEmpty else { throw SSTVDecodeError.noImageData }
        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(profile.width * rows.count)
        for row in rows {
            for outputX in 0..<profile.width {
                let sourceX = (outputX + horizontalShift) % profile.width
                let value = row[sourceX]
                pixels.append(RGBPixel(red: value, green: value, blue: value))
            }
        }
        return SSTVDecodedFrame(
            image: try RGBImage(width: profile.width, height: rows.count, pixels: pixels),
            mode: .hfFax(profile),
            detectionSource: .manual,
            completedRows: rows.count,
            totalRows: nil,
            isComplete: isComplete,
            frequencyOffsetHz: 0
        )
    }

    private func updateHorizontalShiftIfStable() {
        guard rows.count >= 20,
              let maximum = accumulatedBrightness.max(),
              maximum > 0 else { return }
        let mean = accumulatedBrightness.reduce(0, +)
            / Double(accumulatedBrightness.count)
        guard maximum > mean + 0.12 else { return }
        horizontalShift = accumulatedBrightness.firstIndex(of: maximum) ?? 0
    }
}
