import Foundation

public enum SSTVHeaderDetector {
    public static func detect(in buffer: PCMBuffer) -> SSTVHeaderDetection? {
        guard var demodulator = try? SSTVFrequencyDemodulator(
            sampleRate: buffer.sampleRate
        ) else { return nil }
        var frequencies = demodulator.process(buffer.samples)
        frequencies.append(contentsOf: demodulator.process(
            Array(repeating: 0, count: demodulator.latencySamples + 2)
        ))
        return detect(
            frequencies: frequencies,
            sampleRate: buffer.sampleRate,
            latencySamples: demodulator.latencySamples,
            searchStart: 0
        )
    }

    static func detect(
        frequencies: [Float],
        sampleRate: Int,
        latencySamples: Int,
        searchStart: Int
    ) -> SSTVHeaderDetection? {
        let sampler = SSTVToneSampler(
            frequencies: frequencies,
            sampleRate: sampleRate,
            latencySamples: latencySamples
        )
        let requiredDuration = 0.905
        let requiredSamples = sampler.samples(for: requiredDuration)
        let latestStart = sampler.availableRawSampleCount - requiredSamples
        guard latestStart >= max(0, searchStart) else { return nil }

        let coarseStep = max(1, sampleRate / 500)
        var best: Candidate?
        var start = max(0, searchStart)
        while start <= latestStart {
            if let candidate = evaluate(start: start, sampler: sampler),
               best == nil || candidate.score < best!.score {
                best = candidate
            }
            start += coarseStep
        }

        guard let coarse = best else { return nil }
        let refineLower = max(max(0, searchStart), coarse.start - coarseStep)
        let refineUpper = min(latestStart, coarse.start + coarseStep)
        var refinedBest = coarse
        for refinedStart in refineLower...refineUpper {
            if let candidate = evaluate(start: refinedStart, sampler: sampler),
               candidate.score < refinedBest.score {
                refinedBest = candidate
            }
        }

        return SSTVHeaderDetection(
            mode: refinedBest.mode,
            headerStartSample: refinedBest.start,
            pictureStartSample: refinedBest.start
                + sampler.samples(for: SSTVHeader.duration),
            frequencyOffsetHz: refinedBest.frequencyOffset
        )
    }

    private struct Candidate {
        let start: Int
        let mode: SSTVMode
        let frequencyOffset: Double
        let score: Double
    }

    private static func evaluate(
        start: Int,
        sampler: SSTVToneSampler
    ) -> Candidate? {
        guard let firstLeader = mean(
            sampler,
            start: start,
            from: 0.035,
            to: 0.275
        ), let secondLeader = mean(
            sampler,
            start: start,
            from: 0.345,
            to: 0.585
        ) else { return nil }

        guard abs(firstLeader - secondLeader) <= 70 else { return nil }
        let frequencyOffset = (firstLeader + secondLeader) / 2 - 1_900
        guard abs(frequencyOffset) <= 250 else { return nil }

        var score = abs(firstLeader - (1_900 + frequencyOffset))
            + abs(secondLeader - (1_900 + frequencyOffset))
        guard let breakTone = mean(
            sampler,
            start: start,
            from: 0.302,
            to: 0.308
        ), let startTone = mean(
            sampler,
            start: start,
            from: 0.616,
            to: 0.634
        ), abs(breakTone - (1_200 + frequencyOffset)) <= 115,
              abs(startTone - (1_200 + frequencyOffset)) <= 100 else {
            return nil
        }
        score += abs(breakTone - (1_200 + frequencyOffset))
            + abs(startTone - (1_200 + frequencyOffset))

        var bits: [Bool] = []
        bits.reserveCapacity(8)
        for bit in 0..<8 {
            let segmentStart = 0.640 + Double(bit) * 0.030
            guard let frequency = mean(
                sampler,
                start: start,
                from: segmentStart + 0.006,
                to: segmentStart + 0.024
            ) else { return nil }
            let oneError = abs(frequency - (1_100 + frequencyOffset))
            let zeroError = abs(frequency - (1_300 + frequencyOffset))
            let error = min(oneError, zeroError)
            guard error <= 105 else { return nil }
            bits.append(oneError < zeroError)
            score += error
        }

        guard bits.filter({ $0 }).count.isMultiple(of: 2) else { return nil }
        var visCode = 0
        for bit in 0..<7 where bits[bit] {
            visCode |= 1 << bit
        }
        guard let mode = SSTVMode(visCode: visCode),
              let stopTone = mean(
                  sampler,
                  start: start,
                  from: 0.886,
                  to: 0.904
              ), abs(stopTone - (1_200 + frequencyOffset)) <= 100 else {
            return nil
        }
        score += abs(stopTone - (1_200 + frequencyOffset))

        return Candidate(
            start: start,
            mode: mode,
            frequencyOffset: frequencyOffset,
            score: score
        )
    }

    private static func mean(
        _ sampler: SSTVToneSampler,
        start: Int,
        from: Double,
        to: Double
    ) -> Double? {
        sampler.mean(
            rawStart: start + sampler.samples(for: from),
            rawEnd: start + sampler.samples(for: to),
            // A prime-sized budget prevents regular sampling from phase-locking
            // to the demodulator's residual double-carrier ripple.
            maximumSamples: 47
        )
    }
}
