import XCTest
@testable import SSTVKit

final class LateEntryTimingTests: XCTestCase {
    func testFourSyncsAreRequiredToInferAnAutomaticMode() {
        for count in [1, 2, 3, 4] {
            var detector = SSTVLateEntryDetector()
            let detection = detector.detect(frequencies: pulses(count: count), sampleRate: 12_000, latencySamples: 0)
            if count == 4 {
                XCTAssertEqual(detection?.mode, .pd50)
            } else {
                XCTAssertNil(detection)
            }
        }
    }

    func testPeriodAndFrequencyOffsetAreMeasuredIndependently() throws {
        for scale in [0.999, 1.001] {
            var detector = SSTVLateEntryDetector()
            let detection = try XCTUnwrap(detector.detect(
                frequencies: pulses(count: 4, scale: scale, frequencyOffset: 120), sampleRate: 12_000, latencySamples: 0
            ))
            XCTAssertEqual(detection.mode, .pd50)
            XCTAssertEqual(detection.frequencyOffsetHz, 120, accuracy: 1)
        }
    }

    func testOutOfRangePeriodIsNotLabeledAsAValidMode() {
        var detector = SSTVLateEntryDetector()
        XCTAssertNil(detector.detect(frequencies: pulses(count: 4, scale: 1.01), sampleRate: 12_000, latencySamples: 0))
    }

    func testFilledLateEntryRasterDoesNotInventWholeImageProgress() throws {
        let frame = SSTVDecodedFrame(
            image: solidImage(for: .robot72Color), mode: .sstv(.robot72Color), detectionSource: .lateEntry,
            completedRows: 240, totalRows: 240, isComplete: true, frequencyOffsetHz: 0
        )
        XCTAssertNil(frame.progress)
    }

    private func pulses(count: Int, scale: Double = 1, frequencyOffset: Double = 0) -> [Float] {
        let sampleRate = 12_000.0
        let period = SSTVMode.pd50.lineDuration * sampleRate * scale
        let first = 1_200
        var frequencies = [Float](repeating: Float(1_900 + frequencyOffset), count: first + Int(period * 4.5))
        for pulse in 0..<count {
            let start = first + Int((Double(pulse) * period).rounded())
            let end = start + Int((0.020 * sampleRate * scale).rounded())
            for index in start..<end { frequencies[index] = Float(1_200 + frequencyOffset) }
        }
        return frequencies
    }
}
