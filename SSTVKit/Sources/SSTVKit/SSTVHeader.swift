import Foundation

public enum SSTVHeader {
    public static let duration = 0.910

    /// Seven VIS data bits, least-significant bit first, followed by even parity.
    public static func bits(visCode: Int) -> [Bool] {
        let dataBits = (0..<7).map { bit in
            (visCode & (1 << bit)) != 0
        }
        let parityBit = dataBits.filter { $0 }.count.isMultiple(of: 2) == false
        return dataBits + [parityBit]
    }

    public static func segments(visCode: Int) -> [ToneSegment] {
        var result = [
            ToneSegment(frequencyHz: 1900, duration: 0.300),
            ToneSegment(frequencyHz: 1200, duration: 0.010),
            ToneSegment(frequencyHz: 1900, duration: 0.300),
            ToneSegment(frequencyHz: 1200, duration: 0.030),
        ]
        result.append(contentsOf: bits(visCode: visCode).map {
            ToneSegment(frequencyHz: $0 ? 1100 : 1300, duration: 0.030)
        })
        result.append(ToneSegment(frequencyHz: 1200, duration: 0.030))
        return result
    }
}
