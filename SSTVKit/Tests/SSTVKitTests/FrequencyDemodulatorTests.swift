import XCTest
@testable import SSTVKit

final class FrequencyDemodulatorTests: XCTestCase {
    func testAudioHarmonicsDoNotBecomeFalsePixelColors() throws {
        for sampleRate in [12_000, 44_100, 48_000] {
            for tone in [1_500.0, 1_700, 1_900, 2_137, 2_300] {
                let samples = (0..<Int(Double(sampleRate) * 0.035)).map { index -> Float in
                    let phase = 2 * Double.pi * tone * Double(index) / Double(sampleRate) + 0.37
                    return Float(0.6 * sin(phase) + 0.12 * sin(2 * phase + 0.4) + 0.06 * sin(3 * phase + 0.8))
                }
                var demodulator = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
                let frequencies = demodulator.process(samples)
                let sampler = SSTVToneSampler(
                    frequencies: frequencies, sampleRate: sampleRate, latencySamples: demodulator.latencySamples
                )
                let width = max(3, Int((Double(sampleRate) * 0.00019).rounded()))
                var maximumError = 0.0
                for start in Int(Double(sampleRate) * 0.015)..<Int(Double(sampleRate) * 0.028) {
                    let measured = try XCTUnwrap(sampler.mean(rawStart: start, rawEnd: start + width))
                    maximumError = max(maximumError, abs(measured - tone))
                }
                XCTAssertLessThanOrEqual(maximumError, 5, "\(sampleRate) Hz / \(tone) Hz with 20% second and 10% third harmonic")
            }
        }
    }

    func testShortPixelWindowsRecoverSteadyTonesWithoutColorRipple() throws {
        for sampleRate in [6_000, 12_000, 44_100, 48_000] {
            for tone in [1_200.0, 1_500, 1_700, 1_900, 2_137, 2_300] {
                let samples = (0..<Int(Double(sampleRate) * 0.035)).map { index in
                    Float(0.8 * sin(2 * Double.pi * tone * Double(index) / Double(sampleRate) + 0.37))
                }
                var demodulator = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
                let frequencies = demodulator.process(samples)
                let sampler = SSTVToneSampler(
                    frequencies: frequencies,
                    sampleRate: sampleRate,
                    latencySamples: demodulator.latencySamples
                )
                let width = max(3, Int((Double(sampleRate) * 0.00019).rounded()))
                var maximumError = 0.0
                for start in Int(Double(sampleRate) * 0.015)..<Int(Double(sampleRate) * 0.028) {
                    let measured = try XCTUnwrap(sampler.mean(rawStart: start, rawEnd: start + width))
                    maximumError = max(maximumError, abs(measured - tone))
                }
                XCTAssertLessThanOrEqual(maximumError, 2, "\(sampleRate) Hz / \(tone) Hz")
            }
        }
    }

    func testNonFiniteInputDoesNotPoisonFollowingAudio() throws {
        let sampleRate = 12_000
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(frequencyHz: 1_700, duration: 0.08)
        var demodulator = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        _ = demodulator.process([.nan, .infinity, -.infinity])
        let frequencies = demodulator.process(writer.samples)
        XCTAssertTrue(frequencies.allSatisfy(\.isFinite))
        for frequency in frequencies.suffix(sampleRate / 100) {
            XCTAssertEqual(frequency, 1_700, accuracy: 2)
        }
    }

    func testToneScoreIgnoresPhaseAlignedResidualCarrierRipple() throws {
        let sampleRate = 12_000
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(frequencyHz: 1_200, duration: 0.009)

        var demodulator = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        var frequencies = demodulator.process(writer.samples)
        frequencies.append(contentsOf: demodulator.process(
            [Float](repeating: 0, count: demodulator.latencySamples + 2)
        ))
        let sampler = SSTVToneSampler(
            frequencies: frequencies,
            sampleRate: sampleRate,
            latencySamples: demodulator.latencySamples
        )

        let measurement = try XCTUnwrap(sampler.toneScore(
            rawStart: 0,
            duration: 0.009,
            targetFrequency: 1_200
        ))

        XCTAssertEqual(measurement.mean, 1_200, accuracy: 12)
        XCTAssertLessThanOrEqual(measurement.score, 12)
    }

    func testPureToneIsRecoveredWithinTenHertz() throws {
        let sampleRate = 12_000
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(frequencyHz: 2_137, duration: 0.2)

        var demodulator = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        let frequencies = demodulator.process(writer.samples)
        let settled = frequencies.dropFirst(sampleRate / 20).dropLast(sampleRate / 50)
        let mean = settled.reduce(0.0) { $0 + Double($1) } / Double(settled.count)

        XCTAssertEqual(mean, 2_137, accuracy: 10)
    }

    func testChunkingDoesNotChangeDemodulatedSamples() throws {
        let sampleRate = 12_000
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(frequencyHz: 1_900, duration: 0.08)
        writer.append(frequencyHz: 1_200, duration: 0.03)
        writer.append(frequencyHz: 2_300, duration: 0.08)

        var contiguous = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        let expected = contiguous.process(writer.samples)

        var chunked = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        var actual: [Float] = []
        var position = 0
        let chunkSizes = [1, 17, 257, 31, 1_024]
        var chunkIndex = 0
        while position < writer.samples.count {
            let end = min(position + chunkSizes[chunkIndex % chunkSizes.count], writer.samples.count)
            actual.append(contentsOf: chunked.process(Array(writer.samples[position..<end])))
            position = end
            chunkIndex += 1
        }

        XCTAssertEqual(actual.count, expected.count)
        for (left, right) in zip(actual, expected) {
            XCTAssertEqual(left, right, accuracy: 0.000_001)
        }
    }

    func testInvalidSampleRateIsRejected() {
        XCTAssertThrowsError(try SSTVFrequencyDemodulator(sampleRate: 0))
        XCTAssertThrowsError(try SSTVFrequencyDemodulator(sampleRate: 5_000))
        XCTAssertThrowsError(try SSTVFrequencyDemodulator(sampleRate: 384_001))
        XCTAssertThrowsError(try SSTVFrequencyDemodulator(sampleRate: Int.max))
    }
}
