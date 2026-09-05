import Foundation

struct SSTVLateEntryDetection {
    let mode: SSTVMode
    let firstLineStartSample: Int
    let frequencyOffsetHz: Double
}

/// A conservative fallback when VIS was missed. Each mode keeps its own search
/// cursor, so a waiting stream does not repeatedly rescan all retained samples.
struct SSTVLateEntryDetector {
    private var searchStarts: [SSTVMode: Int] = [:]

    mutating func removeFirst(_ sampleCount: Int) {
        for mode in SSTVMode.allCases {
            searchStarts[mode] = max(0, (searchStarts[mode] ?? 0) - sampleCount)
        }
    }

    mutating func detect(
        frequencies: [Float], sampleRate: Int, latencySamples: Int
    ) -> SSTVLateEntryDetection? {
        let sampler = SSTVToneSampler(frequencies: frequencies, sampleRate: sampleRate, latencySamples: latencySamples)
        var matches: [SSTVLateEntryDetection] = []
        for mode in SSTVMode.allCases {
            let result = candidate(mode: mode, sampler: sampler, searchStart: searchStarts[mode] ?? 0)
            searchStarts[mode] = result.nextSearch
            if let detection = result.detection { matches.append(detection) }
        }
        // Do not turn an ambiguous cadence into a falsely certain mode label.
        return matches.count == 1 ? matches[0] : nil
    }

    private func candidate(
        mode: SSTVMode, sampler: SSTVToneSampler, searchStart: Int
    ) -> (detection: SSTVLateEntryDetection?, nextSearch: Int) {
        let period = mode.lineDuration * Double(sampler.sampleRate)
        let syncDuration = pulseDuration(for: mode)
        let syncSamples = sampler.samples(for: syncDuration)
        // Include the fourth pulse's falling edge and maximum allowed drift.
        let required = Int((3 * period * 1.005).rounded(.up)) + syncSamples + sampler.samples(for: 0.004)
        let latestFirst = sampler.availableRawSampleCount - required
        let step = max(1, sampler.sampleRate / 1_000)
        let guardSamples = sampler.samples(for: 0.001)
        var start = max(guardSamples, searchStart)
        while start <= latestFirst {
            defer { start += step }
            guard let rough = sampler.toneScore(
                rawStart: start + sampler.samples(for: syncDuration / 4),
                duration: syncDuration / 2, targetFrequency: 1_200
            ),
                  abs(rough.mean - 1_200) <= 260,
                  let before = sampler.mean(rawStart: start - guardSamples, rawEnd: start, maximumSamples: 11),
                  before > rough.mean + 100,
                  let first = sampler.bestToneStart(
                      near: start, tolerance: step, duration: syncDuration, targetFrequency: rough.mean
                  ), abs(first.mean - 1_200) <= 250, first.score <= 100 else { continue }

            var pulses: [(start: Int, mean: Double)] = [(first.start, first.mean)]
            for index in 1...3 {
                let expected = first.start + Int((Double(index) * period).rounded())
                let tolerance = Int((Double(index) * period * 0.005).rounded(.up)) + step
                guard let pulse = sampler.bestToneStart(
                    near: expected, tolerance: tolerance, duration: syncDuration, targetFrequency: first.mean
                ), pulse.score <= 100, abs(pulse.mean - first.mean) <= 70 else { break }
                let interval = Double(pulse.start - pulses[index - 1].start)
                guard abs(interval / period - 1) <= 0.005 else { break }
                pulses.append((pulse.start, pulse.mean))
            }
            guard pulses.count == 4 else { continue }
            let measuredPeriod = Double(pulses[3].start - pulses[0].start) / 3
            let maximumResidual = pulses.enumerated().map {
                abs(Double($0.element.start - first.start) - Double($0.offset) * measuredPeriod)
            }.max() ?? .infinity
            guard maximumResidual <= Double(sampler.samples(for: 0.00075)) else { continue }
            let frequencyOffset = pulses.map { $0.mean }.reduce(0, +) / 4 - 1_200
            var timedSampler = sampler
            timedSampler.timingScale = measuredPeriod / period
            var syncStart = first.start

            if mode == .robot36Color {
                // Infer pair phase from the chroma marker, not from where the
                // recording happened to begin. An unpaired B-Y line is omitted.
                let markers = pulses.prefix(3).map {
                    robotMarker(sampler: timedSampler, lineStart: $0.start, offset: 0.1, frequencyOffset: $0.mean - 1_200)
                }
                guard let firstRed = markers[0], let secondRed = markers[1], let thirdRed = markers[2],
                      firstRed != secondRed, firstRed == thirdRed else { continue }
                if !firstRed { syncStart = pulses[1].start }
            } else if mode == .robot72Color {
                // Robot 36 syncs also recur every 300 ms. The two intra-line
                // chroma markers prevent mistaking that subharmonic for Robot 72.
                let correctMarkers = pulses.prefix(2).allSatisfy {
                    robotMarker(sampler: timedSampler, lineStart: $0.start, offset: 0.150, frequencyOffset: $0.mean - 1_200) == true
                        && robotMarker(sampler: timedSampler, lineStart: $0.start, offset: 0.225, frequencyOffset: $0.mean - 1_200) == false
                }
                guard correctMarkers else { continue }
            }

            let syncOffset = mode.family == .scottie
                ? timedSampler.samples(for: 2 * (mode.channelScanDuration + 0.0015)) : 0
            let lineStart = syncStart - syncOffset
            guard lineStart >= 0 else { continue }
            return (SSTVLateEntryDetection(mode: mode, firstLineStartSample: lineStart, frequencyOffsetHz: frequencyOffset), start)
        }
        return (nil, max(searchStart, start))
    }

    private func robotMarker(
        sampler: SSTVToneSampler, lineStart: Int, offset: Double, frequencyOffset: Double
    ) -> Bool? {
        guard let frequency = sampler.mean(
            rawStart: lineStart + sampler.samples(for: offset + 0.00125),
            rawEnd: lineStart + sampler.samples(for: offset + 0.00325), maximumSamples: 31
        ) else { return nil }
        if abs(frequency - frequencyOffset - 1_500) <= 120 { return true }
        if abs(frequency - frequencyOffset - 2_300) <= 120 { return false }
        return nil
    }

    private func pulseDuration(for mode: SSTVMode) -> Double {
        switch mode.family {
        case .robot, .scottie: return 0.009
        case .pd: return 0.020
        case .martin: return 0.004862
        case .wraase: return 0.0055225
        }
    }
}
