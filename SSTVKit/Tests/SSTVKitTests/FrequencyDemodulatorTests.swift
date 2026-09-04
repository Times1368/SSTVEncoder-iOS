import XCTest
@testable import SSTVKit

final class FrequencyDemodulatorTests: XCTestCase {
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
    }
}
