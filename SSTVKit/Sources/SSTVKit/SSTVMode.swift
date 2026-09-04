import Foundation

public enum SSTVModeFamily: String, CaseIterable, Sendable, Hashable {
    case robot
    case pd
    case martin
    case scottie
    case wraase

    public var displayName: String {
        switch self {
        case .robot: return "Robot"
        case .pd: return "PD"
        case .martin: return "Martin"
        case .scottie: return "Scottie"
        case .wraase: return "Wraase"
        }
    }

    public var modes: [SSTVMode] {
        switch self {
        case .robot:
            return [.robot36Color, .robot72Color]
        case .pd:
            return [.pd50, .pd90, .pd120, .pd160, .pd180, .pd240, .pd290]
        case .martin:
            return [.martinM1, .martinM2]
        case .scottie:
            return [.scottieS1, .scottieS2, .scottieDX]
        case .wraase:
            return [.wraaseSC2180]
        }
    }
}

public enum SSTVMode: String, CaseIterable, Sendable, Hashable {
    case robot36Color
    case robot72Color
    case pd50
    case pd90
    case pd120
    case pd160
    case pd180
    case pd240
    case pd290
    case martinM1
    case martinM2
    case scottieS1
    case scottieS2
    case scottieDX
    case wraaseSC2180

    public init?(visCode: Int) {
        guard let mode = Self.allCases.first(where: { $0.visCode == visCode }) else {
            return nil
        }
        self = mode
    }

    public var family: SSTVModeFamily { specification.family }
    public var displayName: String { specification.displayName }
    public var visCode: Int { specification.visCode }
    public var width: Int { specification.width }
    public var height: Int { specification.height }

    /// Number of scan lines transmitted over audio. PD lines carry two raster rows.
    public var scanLineCount: Int { specification.scanLineCount }

    /// Duration of one regular radio scan line, excluding a Scottie starting sync.
    public var lineDuration: Double { specification.lineDuration }

    /// Duration of the picture body, including Scottie's one-time starting sync.
    public var pictureDuration: Double {
        specification.framePrefixDuration
            + lineDuration * Double(scanLineCount)
    }

    public var totalDuration: Double {
        SSTVHeader.duration + pictureDuration
    }

    /// The sample count produced by the cumulative-time clock.
    public func sampleCount(at sampleRate: Int) -> Int {
        guard sampleRate > 0 else { return 0 }
        return SampleClock.roundedCount(duration: totalDuration, sampleRate: sampleRate)
            ?? Int.max
    }

    var channelScanDuration: Double { specification.channelScanDuration }
    var framePrefixDuration: Double { specification.framePrefixDuration }

    private var specification: Specification {
        switch self {
        case .robot36Color:
            return Specification(
                family: .robot,
                displayName: "Robot 36 Color",
                visCode: 8,
                width: 320,
                height: 240,
                scanLineCount: 240,
                lineDuration: 0.150,
                channelScanDuration: 0.088
            )
        case .robot72Color:
            return Specification(
                family: .robot,
                displayName: "Robot 72 Color",
                visCode: 12,
                width: 320,
                height: 240,
                scanLineCount: 240,
                lineDuration: 0.300,
                channelScanDuration: 0.138
            )
        case .pd50:
            return Specification.pd("PD 50", visCode: 93, width: 320, height: 256, scan: 0.091520)
        case .pd90:
            return Specification.pd("PD 90", visCode: 99, width: 320, height: 256, scan: 0.170240)
        case .pd120:
            return Specification.pd("PD 120", visCode: 95, width: 640, height: 496, scan: 0.121600)
        case .pd160:
            return Specification.pd("PD 160", visCode: 98, width: 512, height: 400, scan: 0.195584)
        case .pd180:
            return Specification.pd("PD 180", visCode: 96, width: 640, height: 496, scan: 0.183040)
        case .pd240:
            return Specification.pd("PD 240", visCode: 97, width: 640, height: 496, scan: 0.244480)
        case .pd290:
            return Specification.pd("PD 290", visCode: 94, width: 800, height: 616, scan: 0.228800)
        case .martinM1:
            return Specification.martin("Martin M1", visCode: 44, scan: 0.146432)
        case .martinM2:
            return Specification.martin("Martin M2", visCode: 40, scan: 0.073216)
        case .scottieS1:
            return Specification.scottie("Scottie S1", visCode: 60, scan: 0.138240)
        case .scottieS2:
            return Specification.scottie("Scottie S2", visCode: 56, scan: 0.088064)
        case .scottieDX:
            return Specification.scottie("Scottie DX", visCode: 76, scan: 0.345600)
        case .wraaseSC2180:
            return Specification(
                family: .wraase,
                displayName: "Wraase SC2-180",
                visCode: 55,
                width: 320,
                height: 256,
                scanLineCount: 256,
                lineDuration: 0.0055225 + 0.0005 + 3 * 0.235,
                channelScanDuration: 0.235
            )
        }
    }
}

private struct Specification: Sendable {
    let family: SSTVModeFamily
    let displayName: String
    let visCode: Int
    let width: Int
    let height: Int
    let scanLineCount: Int
    let lineDuration: Double
    let channelScanDuration: Double
    var framePrefixDuration: Double { family == .scottie ? 0.009 : 0 }

    static func pd(
        _ displayName: String,
        visCode: Int,
        width: Int,
        height: Int,
        scan: Double
    ) -> Specification {
        Specification(
            family: .pd,
            displayName: displayName,
            visCode: visCode,
            width: width,
            height: height,
            scanLineCount: height / 2,
            lineDuration: 0.020 + 0.00208 + 4 * scan,
            channelScanDuration: scan
        )
    }

    static func martin(
        _ displayName: String,
        visCode: Int,
        scan: Double
    ) -> Specification {
        Specification(
            family: .martin,
            displayName: displayName,
            visCode: visCode,
            width: 320,
            height: 256,
            scanLineCount: 256,
            lineDuration: 0.004862 + 0.000572 + 3 * (scan + 0.000572),
            channelScanDuration: scan
        )
    }

    static func scottie(
        _ displayName: String,
        visCode: Int,
        scan: Double
    ) -> Specification {
        Specification(
            family: .scottie,
            displayName: displayName,
            visCode: visCode,
            width: 320,
            height: 256,
            scanLineCount: 256,
            lineDuration: 0.009 + 3 * (scan + 0.0015),
            channelScanDuration: scan
        )
    }
}
