import Foundation

public struct HFFaxProfile: Sendable, Equatable, Hashable {
    public let displayName: String
    public let ioc: Int
    public let linesPerMinute: Int
    public let width: Int
    public let maximumRows: Int

    public init(
        displayName: String,
        ioc: Int,
        linesPerMinute: Int,
        width: Int,
        maximumRows: Int
    ) {
        self.displayName = displayName
        self.ioc = ioc
        self.linesPerMinute = linesPerMinute
        self.width = width
        self.maximumRows = maximumRows
    }

    public var lineDuration: Double {
        60 / Double(linesPerMinute)
    }

    public static let ioc576_120 = HFFaxProfile(
        displayName: "Contrib / HF Fax",
        ioc: 576,
        linesPerMinute: 120,
        width: 1_808,
        maximumRows: 1_200
    )
}

public enum SSTVReceiveSelection: Sendable, Equatable, Hashable {
    case automatic
    case mode(SSTVMode)
    case hfFax(HFFaxProfile)

    public var displayName: String {
        switch self {
        case .automatic:
            return "自动识别 SSTV"
        case let .mode(mode):
            return mode.displayName
        case let .hfFax(profile):
            return profile.displayName
        }
    }
}

public enum SSTVDecodedMode: Sendable, Equatable, Hashable {
    case sstv(SSTVMode)
    case hfFax(HFFaxProfile)

    public var displayName: String {
        switch self {
        case let .sstv(mode): return mode.displayName
        case let .hfFax(profile): return profile.displayName
        }
    }
}

public enum SSTVDetectionSource: String, Sendable, Equatable, Hashable {
    case vis
    case manual
    case timing
}

public struct SSTVHeaderDetection: Sendable, Equatable {
    public let mode: SSTVMode
    public let headerStartSample: Int
    public let pictureStartSample: Int
    public let frequencyOffsetHz: Double

    public init(
        mode: SSTVMode,
        headerStartSample: Int,
        pictureStartSample: Int,
        frequencyOffsetHz: Double
    ) {
        self.mode = mode
        self.headerStartSample = headerStartSample
        self.pictureStartSample = pictureStartSample
        self.frequencyOffsetHz = frequencyOffsetHz
    }
}

public struct SSTVDecodedFrame: Sendable, Equatable {
    public let image: RGBImage
    public let mode: SSTVDecodedMode
    public let detectionSource: SSTVDetectionSource
    public let completedRows: Int
    public let totalRows: Int?
    public let isComplete: Bool
    public let frequencyOffsetHz: Double

    public init(
        image: RGBImage,
        mode: SSTVDecodedMode,
        detectionSource: SSTVDetectionSource,
        completedRows: Int,
        totalRows: Int?,
        isComplete: Bool,
        frequencyOffsetHz: Double
    ) {
        self.image = image
        self.mode = mode
        self.detectionSource = detectionSource
        self.completedRows = completedRows
        self.totalRows = totalRows
        self.isComplete = isComplete
        self.frequencyOffsetHz = frequencyOffsetHz
    }

    public var progress: Double? {
        guard let totalRows, totalRows > 0 else { return nil }
        return min(1, Double(completedRows) / Double(totalRows))
    }
}

public enum SSTVDecodeError: Error, Sendable, Equatable, LocalizedError {
    case invalidSampleRate(Int)
    case emptyAudio
    case headerNotFound
    case noImageData

    public var errorDescription: String? {
        switch self {
        case let .invalidSampleRate(sampleRate):
            return "不支持的音频采样率：\(sampleRate) Hz。"
        case .emptyAudio:
            return "音频中没有可解码的采样数据。"
        case .headerNotFound:
            return "未检测到有效的 SSTV VIS 头。请从完整录音开始导入，或检查信号电平。"
        case .noImageData:
            return "已识别接收模式，但还没有收到完整扫描行。"
        }
    }
}
