import Foundation

enum SampleClock {
    static func roundedCount(duration: Double, sampleRate: Int) -> Int? {
        guard duration.isFinite,
              duration >= 0,
              sampleRate > 0 else {
            return nil
        }

        let rounded = (duration * Double(sampleRate)).rounded()
        // Double(Int.max) rounds up to 2^63 on 64-bit platforms, so equality
        // must also be rejected before converting to Int.
        guard rounded.isFinite,
              rounded >= 0,
              rounded < Double(Int.max) else {
            return nil
        }
        return Int(rounded)
    }
}
