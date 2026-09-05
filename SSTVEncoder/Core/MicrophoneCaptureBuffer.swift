import Foundation

struct MicrophoneAudioChunk: Sendable {
    let samples: [Float]
    let sampleTime: Int64?
}

/// The continuation is thread-safe; this wrapper has no mutable shared state.
/// Keep the contiguous prefix on overflow, then fail rather than dropping old
/// samples and stitching unrelated portions of a radio line together.
final class MicrophoneCaptureBuffer: Sendable {
    let stream: AsyncThrowingStream<MicrophoneAudioChunk, Error>
    private let continuation: AsyncThrowingStream<MicrophoneAudioChunk, Error>.Continuation

    init(capacity: Int = 32) {
        let pair = AsyncThrowingStream<MicrophoneAudioChunk, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(capacity)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    func yield(_ samples: [Float], sampleTime: Int64?) {
        switch continuation.yield(MicrophoneAudioChunk(samples: samples, sampleTime: sampleTime)) {
        case .dropped:
            continuation.finish(throwing: MicrophoneCaptureError.bufferOverflow)
        case .enqueued, .terminated:
            break
        @unknown default:
            continuation.finish(throwing: MicrophoneCaptureError.bufferOverflow)
        }
    }

    func finish(throwing error: MicrophoneCaptureError? = nil) { continuation.finish(throwing: error) }
}

struct MicrophoneContinuityChecker {
    private var expectedSampleTime: Int64?

    mutating func accept(_ chunk: MicrophoneAudioChunk) throws {
        guard let sampleTime = chunk.sampleTime else {
            expectedSampleTime = nil
            return
        }
        if let expectedSampleTime, sampleTime != expectedSampleTime {
            throw MicrophoneCaptureError.discontinuousAudio
        }
        let (next, overflow) = sampleTime.addingReportingOverflow(Int64(chunk.samples.count))
        guard !overflow else { throw MicrophoneCaptureError.discontinuousAudio }
        expectedSampleTime = next
    }
}

enum MicrophoneCaptureError: Error, LocalizedError, Equatable {
    case bufferOverflow
    case discontinuousAudio
    case unreadableBuffer

    var errorDescription: String? {
        switch self {
        case .bufferOverflow:
            return "音频处理未能跟上输入，已停止接收并保留部分图像。请关闭其他高负载应用后重新接收。"
        case .discontinuousAudio:
            return "音频输入出现缺口或设备时钟重置，已停止接收并保留部分图像。请检查输入设备后重新接收。"
        case .unreadableBuffer:
            return "音频设备返回了无法读取的采样数据，已停止接收。请检查输入设备后重试。"
        }
    }
}
