import Foundation

/// A second-order line clock: follow sustained sample-clock error without
/// copying every noisy pulse position into the raster. State is committed by
/// the assembler only after the corresponding complete line is available.
struct SSTVLineClock {
    let nominalPeriod: Double
    private(set) var nextStart: Double
    private var period: Double
    private var acquired = false

    init(nominalPeriod: Double, firstStart: Double) {
        self.nominalPeriod = nominalPeriod
        period = nominalPeriod
        nextStart = firstStart
    }

    var timingScale: Double { period / nominalPeriod }

    mutating func advance(observedStart: Double?) -> Double {
        var start = nextStart
        if let observedStart, observedStart.isFinite {
            if !acquired {
                start = observedStart
                acquired = true
            } else {
                let error = observedStart - nextStart
                start += 0.2 * error
                period = min(nominalPeriod * 1.005, max(nominalPeriod * 0.995, period + 0.01 * error))
            }
        }
        nextStart = start + period
        return start
    }
}
