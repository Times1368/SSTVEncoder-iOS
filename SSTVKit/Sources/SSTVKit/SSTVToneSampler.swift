import Foundation

struct SSTVToneSampler {
    let frequencies: [Float]
    let sampleRate: Int
    let latencySamples: Int
    var timingScale: Double = 1

    var availableRawSampleCount: Int {
        max(0, frequencies.count - latencySamples)
    }

    func samples(for duration: Double) -> Int {
        max(0, Int((duration * Double(sampleRate) * timingScale).rounded()))
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
                  maximumSamples: 47
              ) else { return nil }

        // The quadrature demodulator leaves a small double-carrier ripple. Its
        // mean is centered on the tone, so score the measured mean instead of
        // treating each instantaneous ripple sample as a frequency error.
        return (abs(average - targetFrequency), average)
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
            if let measurement = syncPulseScore(
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
            guard let measurement = syncPulseScore(
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

    private func syncPulseScore(
        rawStart: Int,
        duration: Double,
        targetFrequency: Double
    ) -> (score: Double, mean: Double)? {
        let length = samples(for: duration)
        let end = rawStart + length
        guard rawStart >= 0, end <= availableRawSampleCount, length >= 6 else { return nil }
        // Frequency correction must come from settled sync, not transition
        // samples mixed with the preceding pixel or following porch.
        let trim = min(length / 4, max(2, samples(for: 0.001)))
        let coreStart = rawStart + trim
        let coreEnd = end - trim
        let step = max(1, (coreEnd - coreStart) / 47)
        var core: [Double] = []
        for index in stride(from: coreStart, to: coreEnd, by: step) {
            let value = Double(frequencies[index + latencySamples])
            guard value.isFinite, value >= 700, value <= 3_000 else { return nil }
            core.append(value)
        }
        guard core.count >= 3 else { return nil }
        core.sort()
        let median = core[core.count / 2]
        let deviation = core.reduce(0) { $0 + abs($1 - median) } / Double(core.count)
        // Opposite frequency errors can average to 1200 Hz without being a
        // sync pulse. Require a stable, predominantly on-frequency interior.
        guard abs(median - targetFrequency) <= 180, deviation <= 80 else { return nil }
        let inliers = core.filter { abs($0 - median) <= 100 }
        guard inliers.count * 5 >= core.count * 4 else { return nil }
        let settledMean = inliers.reduce(0, +) / Double(inliers.count)

        func support(from start: Int, to finish: Int) -> Double? {
            guard start >= 0, finish <= availableRawSampleCount, finish > start else { return nil }
            let strideSize = max(1, (finish - start) / 47)
            var total = 0.0
            var count = 0
            for index in stride(from: start, to: finish, by: strideSize) {
                let value = Double(frequencies[index + latencySamples])
                if value.isFinite {
                    total += max(0, 1 - abs(value - settledMean) / 180)
                }
                count += 1
            }
            return total / Double(max(1, count))
        }
        let inside = support(from: rawStart, to: end) ?? 0
        guard inside >= 0.6 else { return nil }
        // Missing samples are not evidence of silence. In particular, VIS
        // removal can leave a truncated first sync at raw sample zero. Taking
        // that boundary as a measured edge biases the clock's initial phase.
        // Both transitions must be observed before a pulse can steer the clock.
        guard let before = support(from: rawStart - trim, to: rawStart),
              let after = support(from: end, to: end + trim),
              before < 0.8, after < 0.8 else { return nil }
        let outside = before + after
        let score = 100 * (1 - inside) + 25 * outside
            + 0.1 * abs(settledMean - targetFrequency) + 0.2 * deviation
        return (score, settledMean)
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
            + scanDuration * Double(sampleRate) * timingScale * Double(pixel) / Double(width)
        let exactEnd = Double(scanStart)
            + scanDuration * Double(sampleRate) * timingScale * Double(pixel + 1) / Double(width)
        let center = (exactStart + exactEnd) / 2
        let halfWindow = max(2, Int(((exactEnd - exactStart) * 0.3).rounded()))
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
