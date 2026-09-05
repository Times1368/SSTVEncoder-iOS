import Foundation

/// A second-order line clock: follow sustained sample-clock error without
/// copying every noisy pulse position into the raster. State is committed by
/// the assembler only after the corresponding complete line is available.
struct SSTVLineClock {
    let nominalPeriod: Double
    private(set) var nextStart: Double
    private var period: Double
    private var acquired = false
    private var periodAcquired = false
    private var lineIndex = 0
    private var previousObservation: (line: Int, start: Double)?

    init(nominalPeriod: Double, firstStart: Double) {
        self.nominalPeriod = nominalPeriod
        period = nominalPeriod
        nextStart = firstStart
    }

    var timingScale: Double { period / nominalPeriod }

    mutating func advance(observedStart: Double?) -> Double {
        defer { lineIndex += 1 }
        var start = nextStart
        if let observedStart, observedStart.isFinite {
            if !acquired {
                start = observedStart
                acquired = true
            } else {
                var initialPeriod: Double?
                if !periodAcquired, let previousObservation {
                    let elapsedLines = lineIndex - previousObservation.line
                    if elapsedLines > 0 {
                        let measuredPeriod = (observedStart - previousObservation.start) / Double(elapsedLines)
                        if (nominalPeriod * 0.995...nominalPeriod * 1.005).contains(measuredPeriod) {
                            initialPeriod = measuredPeriod
                        }
                    }
                }
                if let initialPeriod {
                    // Seed the sample-clock ratio from two real edges before
                    // narrow-band tracking. Starting that loop at the nominal
                    // rate otherwise bends the first dozen rows while it settles.
                    period = initialPeriod
                    start = observedStart
                    periodAcquired = true
                } else {
                    let error = observedStart - nextStart
                    start += 0.2 * error
                    period = min(nominalPeriod * 1.005, max(nominalPeriod * 0.995, period + 0.01 * error))
                }
            }
            previousObservation = (lineIndex, observedStart)
        }
        nextStart = start + period
        return start
    }
}
