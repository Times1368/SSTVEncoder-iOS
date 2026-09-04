import AVFoundation
import Combine
import Foundation
import SSTVKit

@MainActor
final class PlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress = 0.0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
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
                      reason == .oldDeviceUnavailable || reason == .noSuitableRouteForCategory else {
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
        progressTimer?.invalidate()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func play(_ buffer: PCMBuffer) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try? session.setPreferredSampleRate(Double(buffer.sampleRate))
        try session.setActive(true)

        let audioPlayer = try AVAudioPlayer(data: WAVEncoder.encode(buffer))
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        guard audioPlayer.play() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw PlaybackError.couldNotStart
        }

        player = audioPlayer
        isPlaying = true
        progress = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateProgress() }
        }
        timer.tolerance = 0.02
        progressTimer = timer
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in self?.finishPlayback() }
    }

    private func updateProgress() {
        guard let player, player.duration > 0 else { return }
        progress = min(max(player.currentTime / player.duration, 0), 1)
    }

    private func finishPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        player = nil
        isPlaying = false
        progress = 1
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

enum PlaybackError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "无法开始本机音频播放。"
    }
}

