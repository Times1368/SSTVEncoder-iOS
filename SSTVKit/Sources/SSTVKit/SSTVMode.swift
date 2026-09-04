import Foundation

public enum SSTVMode: String, CaseIterable, Sendable, Hashable {
    case robot36Color
    case robot72Color
    case martinM1
    case scottieS1

    public var displayName: String {
        switch self {
        case .robot36Color: return "Robot 36 Color"
        case .robot72Color: return "Robot 72 Color"
        case .martinM1: return "Martin M1"
        case .scottieS1: return "Scottie S1"
        }
    }

    public var visCode: Int {
        switch self {
        case .robot36Color: return 8
        case .robot72Color: return 12
        case .martinM1: return 44
        case .scottieS1: return 60
        }
    }

    public var width: Int { 320 }

    public var height: Int {
        switch self {
        case .robot36Color, .robot72Color: return 240
        case .martinM1, .scottieS1: return 256
        }
    }

    /// Duration of one regular picture line, excluding Scottie's one-time prefix.
    public var lineDuration: Double {
        switch self {
        case .robot36Color: return 0.150
        case .robot72Color: return 0.300
        case .martinM1: return 0.446446
        case .scottieS1: return 0.428220
        }
    }

    /// Duration of the picture body, including Scottie S1's initial sync pulse.
    public var pictureDuration: Double {
        switch self {
        case .robot36Color: return 36.000
        case .robot72Color: return 72.000
        case .martinM1: return 114.290176
        case .scottieS1: return 109.633320
        }
    }

    public var totalDuration: Double {
        SSTVHeader.duration + pictureDuration
    }

    /// The sample count produced by the cumulative-time clock.
    public func sampleCount(at sampleRate: Int) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int((totalDuration * Double(sampleRate)).rounded())
    }
}
