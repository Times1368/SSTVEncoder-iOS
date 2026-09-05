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

    func testTruncatedSyncAtBufferStartCannotAcquireTheLineClock() {
        for sampleRate in [12_000, 48_000] {
            // Header removal left only 7.5 ms of a 9 ms sync. There is no
            // observed leading edge, even if a candidate is shifted right.
            let remainingSync = sampleRate * 75 / 10_000
            let frequencies = [Float](repeating: 1_200, count: remainingSync)
                + [Float](repeating: 1_900, count: sampleRate / 25)
            let sampler = SSTVToneSampler(frequencies: frequencies, sampleRate: sampleRate, latencySamples: 0)
            XCTAssertNil(sampler.bestToneStart(
                near: 0, tolerance: sampleRate / 100, duration: 0.009, targetFrequency: 1_200
            ))
        }
    }

    func testTruncatedSyncAtBufferEndRequiresItsFallingEdge() {
        let frequencies = [Float](repeating: 1_900, count: 200)
            + [Float](repeating: 1_200, count: 90)
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

    func testClockAcquiresPeriodFromTheFirstTwoCompleteSyncs() {
        for scale in [0.999, 1.001] {
            let nominal = 14_400.0 // Robot 72 at 48 kHz.
            var clock = SSTVLineClock(nominalPeriod: nominal, firstStart: 0)
            for row in 0..<64 {
                // The initial VIS-derived origin is not an observed sync edge.
                let ideal = -150 + Double(row) * nominal * scale
                let start = clock.advance(observedStart: row == 0 ? nil : ideal)
                if row >= 2 {
                    XCTAssertEqual(start, ideal, accuracy: 0.001)
                    XCTAssertEqual(clock.timingScale, scale, accuracy: 0.00001)
                }
            }
        }
    }

    func testPeriodAcquisitionCountsLinesWithMissingSync() {
        var clock = SSTVLineClock(nominalPeriod: 14_400, firstStart: 0)
        _ = clock.advance(observedStart: nil)
        _ = clock.advance(observedStart: 14_414.4)
        _ = clock.advance(observedStart: nil)
        let start = clock.advance(observedStart: 43_243.2)
        XCTAssertEqual(start, 43_243.2, accuracy: 0.001)
        XCTAssertEqual(clock.timingScale, 1.001, accuracy: 0.00001)
    }

    func testImplausibleStartupSpacingCannotSeedThePeriod() {
        var clock = SSTVLineClock(nominalPeriod: 3_600, firstStart: 0)
        _ = clock.advance(observedStart: 0)
        _ = clock.advance(observedStart: 3_672) // 2% is outside the allowed clock range.
        XCTAssertEqual(clock.timingScale, 1, accuracy: 0.001)
    }

    func testMissingSyncDoesNotRoundAndAccumulateTheNominalPeriod() {
        var clock = SSTVLineClock(nominalPeriod: 5_357.352, firstStart: 0)
        for row in 0..<256 {
            XCTAssertEqual(clock.advance(observedStart: nil), Double(row) * 5_357.352, accuracy: 0.0001)
        }
    }
}
