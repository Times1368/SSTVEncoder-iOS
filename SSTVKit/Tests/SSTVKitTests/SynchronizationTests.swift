import XCTest
@testable import SSTVKit

final class SynchronizationTests: XCTestCase {
    func testContinuousCarrierIsNotALineSyncPulse() {
        let sampler = SSTVToneSampler(
            frequencies: [Float](repeating: 1_200, count: 600), sampleRate: 12_000, latencySamples: 0
        )
        XCTAssertNil(sampler.bestToneStart(near: 200, tolerance: 100, duration: 0.009, targetFrequency: 1_200))
    }

    func testBalancedInterferenceIsNotAStableSyncPulse() {
        let frequencies: [Float] = (0..<600).map { $0.isMultiple(of: 2) ? 900 : 1_500 }
        let sampler = SSTVToneSampler(frequencies: frequencies, sampleRate: 12_000, latencySamples: 0)
        XCTAssertNil(sampler.bestToneStart(near: 200, tolerance: 100, duration: 0.009, targetFrequency: 1_200))
    }

    func testFrequencyOffsetUsesSettledSyncInteriorNotItsEdges() throws {
        var frequencies = [Float](repeating: 1_900, count: 600)
        for index in 200..<308 { frequencies[index] = 1_245 }
        // Deterministic boundary contamination; the stable carrier is +45 Hz.
        for index in 200..<208 { frequencies[index] = 1_365 }
        for index in 300..<308 { frequencies[index] = 1_365 }
        let sampler = SSTVToneSampler(frequencies: frequencies, sampleRate: 12_000, latencySamples: 0)
        let pulse = try XCTUnwrap(sampler.bestToneStart(
            near: 200, tolerance: 24, duration: 0.009, targetFrequency: 1_245
        ))
        XCTAssertEqual(pulse.mean, 1_245, accuracy: 1)
        XCTAssertEqual(Double(pulse.start), 200, accuracy: 4)
    }

    func testClockRejectsAlternatingPulseJitterWithoutAccumulatingSlant() {
        var clock = SSTVLineClock(nominalPeriod: 3_600, firstStart: 0)
        var errors: [Double] = []
        for row in 0..<240 {
            let ideal = Double(row) * 3_600
            let jitter = row == 0 ? 0.0 : (row.isMultiple(of: 2) ? 24.0 : -24.0)
            let start = clock.advance(observedStart: ideal + jitter)
            if row >= 40 { errors.append(start - ideal) }
        }
        XCTAssertLessThanOrEqual((errors.max() ?? 0) - (errors.min() ?? 0), 6)
        XCTAssertEqual(clock.timingScale, 1, accuracy: 0.0001)
    }

    func testClockRecoversSampleRateErrorAndCoastsAcrossMissingSync() {
        for scale in [0.999, 1.001] {
            var clock = SSTVLineClock(nominalPeriod: 3_600, firstStart: 0)
            for row in 0..<240 {
                let ideal = Double(row) * 3_600 * scale
                let missing = (160..<165).contains(row)
                let start = clock.advance(observedStart: missing ? nil : ideal)
                if row >= 120 { XCTAssertEqual(start, ideal, accuracy: 1) }
            }
            XCTAssertEqual(clock.timingScale, scale, accuracy: 0.00001)
        }
    }

    func testMissingSyncDoesNotRoundAndAccumulateTheNominalPeriod() {
        var clock = SSTVLineClock(nominalPeriod: 5_357.352, firstStart: 0)
        for row in 0..<256 {
            XCTAssertEqual(clock.advance(observedStart: nil), Double(row) * 5_357.352, accuracy: 0.0001)
        }
    }
}
