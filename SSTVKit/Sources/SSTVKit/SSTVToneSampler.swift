import Foundation

struct SSTVToneSampler {
    let frequencies: [Float]
    let sampleRate: Int
    let latencySamples: Int

    var availableRawSampleCount: Int {
        max(0, frequencies.count - latencySamples)
    }

    func samples(for duration: Double) -> Int {
        max(0, Int((duration * Double(sampleRate)).rounded()))
    }

    func mean(
        rawStart: Int,
        rawEnd: Int,
        maximumSamples: Int = 64
    ) -> Double? {
        guard rawStart >= 0, rawEnd > rawStart else { return nil }
        let start = rawStart + latencySamples
        let end = rawEnd + latencySamples
        guard start >= 0, end <= frequencies.count else { return nil }

        let step = max(1, (end - start) / max(1, maximumSamples))
        var total = 0.0
        var count = 0
        var index = start + min(step / 2, max(0, end - start - 1))
        while index < end {
            let value = Double(frequencies[index])
            if value.isFinite, value >= 700, value <= 3_000 {
                total += value
                count += 1
            }
            index += step
        }
        guard count >= min(3, max(1, (end - start) / step)) else { return nil }
        return total / Double(count)
    }

    func toneScore(
        rawStart: Int,
        duration: Double,
        targetFrequency: Double
    ) -> (score: Double, mean: Double)? {
        let length = samples(for: duration)
        guard length > 0,
              let average = mean(
                  rawStart: rawStart,
                  rawEnd: rawStart + length,
                  maximumSamples: 48
              ) else { return nil }

        let start = rawStart + latencySamples
        let end = start + length
        let step = max(1, length / 48)
        var absoluteError = 0.0
        var count = 0
        var index = start + min(step / 2, max(0, length - 1))
        while index < end, index < frequencies.count {
            let value = Double(frequencies[index])
            if value.isFinite, value >= 700, value <= 3_000 {
                absoluteError += abs(value - targetFrequency)
                count += 1
            }
            index += step
        }
        guard count >= 3 else { return nil }
        return (absoluteError / Double(count), average)
    }

    func bestToneStart(
        near expectedStart: Int,
        tolerance: Int,
        duration: Double,
        targetFrequency: Double
    ) -> (start: Int, mean: Double, score: Double)? {
        let durationSamples = samples(for: duration)
        let lower = max(0, expectedStart - tolerance)
        let upper = min(
            availableRawSampleCount - durationSamples,
            expectedStart + tolerance
        )
        guard upper >= lower else { return nil }

        let coarseStep = max(1, sampleRate / 4_000)
        var best: (start: Int, mean: Double, score: Double)?
        var candidate = lower
        while candidate <= upper {
            if let measurement = toneScore(
                rawStart: candidate,
                duration: duration,
                targetFrequency: targetFrequency
            ) {
                let distancePenalty = Double(abs(candidate - expectedStart))
                    / Double(max(1, tolerance))
                let score = measurement.score + distancePenalty
                if best == nil || score < best!.score {
                    best = (candidate, measurement.mean, score)
                }
            }
            candidate += coarseStep
        }

        guard let coarse = best else { return nil }
        let refineLower = max(lower, coarse.start - coarseStep)
        let refineUpper = min(upper, coarse.start + coarseStep)
        for refined in refineLower...refineUpper {
            guard let measurement = toneScore(
                rawStart: refined,
                duration: duration,
                targetFrequency: targetFrequency
            ) else { continue }
            let distancePenalty = Double(abs(refined - expectedStart))
                / Double(max(1, tolerance))
            let score = measurement.score + distancePenalty
            if score < best!.score {
                best = (refined, measurement.mean, score)
            }
        }
        return best
    }

    func component(
        scanStart: Int,
        scanDuration: Double,
        pixel: Int,
        width: Int,
        frequencyOffset: Double
    ) -> Double {
        guard width > 0, pixel >= 0, pixel < width else { return 0 }
        let exactStart = Double(scanStart)
            + scanDuration * Double(sampleRate) * Double(pixel) / Double(width)
        let exactEnd = Double(scanStart)
            + scanDuration * Double(sampleRate) * Double(pixel + 1) / Double(width)
        let center = (exactStart + exactEnd) / 2
        let halfWindow = max(1, Int(((exactEnd - exactStart) * 0.3).rounded()))
        let start = Int(center.rounded()) - halfWindow
        let end = Int(center.rounded()) + halfWindow + 1
        guard let frequency = mean(
            rawStart: start,
            rawEnd: end,
            maximumSamples: 16
        ) else { return 0 }
        return min(255, max(0, (frequency - frequencyOffset - 1_500) * 255 / 800))
    }
}
