import AVFoundation
import Foundation

struct MicrophoneCapture: Sendable {
    let sampleRate: Int
    let chunks: AsyncThrowingStream<MicrophoneAudioChunk, Error>
}

@MainActor
final class MicrophoneReceiver {
    private var engine: AVAudioEngine?
    private var captureBuffer: MicrophoneCaptureBuffer?
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else {
                    return
                }
                Task { @MainActor [weak self] in self?.stop() }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                      reason == .oldDeviceUnavailable
                        || reason == .noSuitableRouteForCategory else {
                    return
                }
                Task { @MainActor [weak self] in self?.stop() }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            }
        )
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func start() async throws -> MicrophoneCapture {
        stop()
        guard await AVAudioApplication.requestRecordPermission() else {
            throw MicrophoneReceiverError.permissionDenied
        }
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate >= 6_000, format.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw MicrophoneReceiverError.inputUnavailable
        }

        let capturedBuffer = MicrophoneCaptureBuffer()

        input.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: format
        ) { buffer, time in
            guard let channels = buffer.floatChannelData else {
                capturedBuffer.finish(throwing: .unreadableBuffer)
                return
            }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frameCount > 0, channelCount > 0 else { return }

            var mono = Array(repeating: Float.zero, count: frameCount)
            for frame in 0..<frameCount {
                var value: Float = 0
                for channel in 0..<channelCount {
                    value += channels[channel][frame]
                }
                mono[frame] = value / Float(channelCount)
            }
            capturedBuffer.yield(mono, sampleTime: time.isSampleTimeValid ? time.sampleTime : nil)
        }

        do {
            engine.prepare()
            try engine.start()
            try Task.checkCancellation()
        } catch {
            input.removeTap(onBus: 0)
            capturedBuffer.finish()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        self.engine = engine
        captureBuffer = capturedBuffer
        return MicrophoneCapture(
            sampleRate: Int(format.sampleRate.rounded()),
            chunks: capturedBuffer.stream
        )
    }

    func stop() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        captureBuffer?.finish()
        captureBuffer = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

enum MicrophoneReceiverError: LocalizedError {
    case permissionDenied
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得麦克风权限。请在系统设置中允许 SSTV Encoder 使用麦克风。"
        case .inputUnavailable:
            return "当前没有可用的音频输入设备。"
        }
    }
}
