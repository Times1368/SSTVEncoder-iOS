import Foundation

struct SSTVTimingDetection {
    let firstLineStartSample: Int
    let frequencyOffsetHz: Double
}

enum SSTVTimingDetector {
    static func detect(
        frequencies: [Float],
        sampleRate: Int,
        latencySamples: Int,
        mode: SSTVMode,
        searchStart: Int
    ) -> SSTVTimingDetection? {
        let sampler = SSTVToneSampler(
            frequencies: frequencies,
            sampleRate: sampleRate,
            latencySamples: latencySamples
        )
        let lineSamples = sampler.samples(for: mode.lineDuration)
        let syncDuration = syncPulseDuration(for: mode)
        let syncSamples = sampler.samples(for: syncDuration)
        let latestFirst = sampler.availableRawSampleCount - 2 * lineSamples - syncSamples
        guard lineSamples > 0, latestFirst >= max(0, searchStart) else { return nil }

        let coarseStep = max(1, sampleRate / 1_000)
        let pairTolerance = sampler.samples(for: syncTolerance(for: mode))
        var candidate = max(0, searchStart)
        while candidate <= latestFirst {
            guard let first = sampler.toneScore(
                rawStart: candidate,
                duration: syncDuration,
                targetFrequency: 1_200
            ), abs(first.mean - 1_200) <= 260 else {
                candidate += coarseStep
                continue
            }

            let target = first.mean
            guard let second = sampler.bestToneStart(
                near: candidate + lineSamples,
                tolerance: pairTolerance,
                duration: syncDuration,
                targetFrequency: target
            ), second.score <= 190,
                  let third = sampler.bestToneStart(
                      near: second.start + lineSamples,
                      tolerance: pairTolerance,
                      duration: syncDuration,
                      targetFrequency: target
                  ), third.score <= 190,
                  abs(second.mean - first.mean) <= 70,
                  abs(third.mean - first.mean) <= 70 else {
                candidate += coarseStep
                continue
            }

            let refinedFirst = sampler.bestToneStart(
                near: candidate,
                tolerance: sampler.samples(for: syncDuration),
                duration: syncDuration,
                targetFrequency: (first.mean + second.mean + third.mean) / 3
            )
            let syncStart = refinedFirst?.start ?? candidate
            let firstLineStart: Int
            if mode.family == .scottie {
                let syncOffset = sampler.samples(
                    for: 2 * (mode.channelScanDuration + 0.0015)
                )
                firstLineStart = syncStart - syncOffset
            } else {
                firstLineStart = syncStart
            }
            guard firstLineStart >= 0 else {
                candidate += coarseStep
                continue
            }

            return SSTVTimingDetection(
                firstLineStartSample: firstLineStart,
                frequencyOffsetHz: (first.mean + second.mean + third.mean) / 3 - 1_200
            )
        }
        return nil
    }

    private static func syncPulseDuration(for mode: SSTVMode) -> Double {
        switch mode.family {
        case .robot, .scottie: return 0.009
        case .pd: return 0.020
        case .martin: return 0.004862
        case .wraase: return 0.0055225
        }
    }

    private static func syncTolerance(for mode: SSTVMode) -> Double {
        switch mode.family {
        case .pd: return 0.014
        case .robot, .scottie: return 0.009
        case .martin, .wraase: return 0.005
        }
    }
}
