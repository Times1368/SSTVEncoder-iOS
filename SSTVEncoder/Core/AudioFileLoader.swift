import AVFoundation
import Foundation
import SSTVKit

enum AudioFileLoader {
    static func load(
        from url: URL,
        manageSecurityScope: Bool = true
    ) throws -> PCMBuffer {
        let accessed = manageSecurityScope
            ? url.startAccessingSecurityScopedResource()
            : false
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var coordinationError: NSError?
        var result: Result<PCMBuffer, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try readAudio(at: coordinatedURL) }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw AudioFileLoadingError.noPCMData
        }
        return try result.get()
    }

    private static func readAudio(at url: URL) throws -> PCMBuffer {
        let file = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = file.processingFormat
        let sampleRateValue = format.sampleRate
        let sampleRate = Int(sampleRateValue.rounded())
        guard sampleRateValue.isFinite,
              abs(sampleRateValue - Double(sampleRate)) < 0.01,
              sampleRate >= 6_000 else {
            throw AudioFileLoadingError.unsupportedSampleRate(sampleRateValue)
        }

        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else {
            throw AudioFileLoadingError.noPCMData
        }
        let maximumSamples = sampleRate * 60 * 20
        var samples: [Float] = []
        samples.reserveCapacity(min(maximumSamples, max(0, Int(file.length))))

        let frameCapacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else {
            throw AudioFileLoadingError.noPCMData
        }

        while true {
            try file.read(into: buffer, frameCount: frameCapacity)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else {
                throw AudioFileLoadingError.noPCMData
            }
            guard samples.count + frameLength <= maximumSamples else {
                throw AudioFileLoadingError.tooLong(maximumMinutes: 20)
            }

            for frame in 0..<frameLength {
                var mono: Float = 0
                for channel in 0..<channelCount {
                    mono += channels[channel][frame]
                }
                samples.append(mono / Float(channelCount))
            }
        }

        guard !samples.isEmpty else { throw AudioFileLoadingError.noPCMData }
        return try PCMBuffer(sampleRate: sampleRate, samples: samples)
    }
}

enum AudioFileLoadingError: LocalizedError {
    case noPCMData
    case unsupportedSampleRate(Double)
    case tooLong(maximumMinutes: Int)

    var errorDescription: String? {
        switch self {
        case .noPCMData:
            return "所选文件没有可读取的 PCM 音频。"
        case let .unsupportedSampleRate(sampleRate):
            return "不支持该音频采样率：\(sampleRate.formatted()) Hz。"
        case let .tooLong(maximumMinutes):
            return "音频超过 \(maximumMinutes) 分钟的本机处理上限。"
        }
    }
}
