import Foundation
import XCTest
@testable import SSTVKit

final class ToneWriterTests: XCTestCase {
    func testCumulativeRoundingDoesNotAccumulatePerSegmentError() {
        var writer = ToneWriter(sampleRate: 48_000, amplitude: 1, capacity: 4)

        for _ in 0..<4 {
            writer.append(frequencyHz: 1900, duration: 0.000_010)
        }

        XCTAssertEqual(writer.samples.count, 2)
        XCTAssertEqual(writer.elapsedDuration, 0.000_040, accuracy: 0.000_000_001)
    }

    func testOscillatorMaintainsPhaseAcrossToneBoundary() {
        var writer = ToneWriter(sampleRate: 48_000, amplitude: 0.8, capacity: 2_000)
        writer.append(frequencyHz: 1900, duration: 0.013)
        let boundary = writer.samples.count
        let phase = writer.phase
        writer.append(frequencyHz: 2300, duration: 0.017)

        XCTAssertEqual(
            writer.samples[boundary],
            Float(sin(phase) * 0.8),
            accuracy: 0.000_001
        )
    }

    func testGeneratedToneHasExpectedFrequencyAndAmplitude() {
        var writer = ToneWriter(sampleRate: 48_000, amplitude: 0.75, capacity: 4_800)
        writer.append(frequencyHz: 1900, duration: 0.100)
        let samples = writer.samples
        var positiveCrossings = 0
        for index in 1..<samples.count where samples[index - 1] <= 0 && samples[index] > 0 {
            positiveCrossings += 1
        }
        let estimated = Double(positiveCrossings) / 0.100

        XCTAssertEqual(samples.count, 4_800)
        XCTAssertEqual(estimated, 1900, accuracy: 10)
        XCTAssertLessThanOrEqual(samples.map { abs($0) }.max()!, 0.750_001)
    }
}
