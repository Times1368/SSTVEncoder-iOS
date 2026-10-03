import Foundation
import SSTVKit

/// Maps audio playback onto the picture body after the VIS header has finished.
enum TransmitPlaybackProgress {
    static func pictureFraction(
        playbackProgress: Double,
        totalDuration: Double,
        headerDuration: Double = SSTVHeader.duration
    ) -> Double {
        guard playbackProgress.isFinite, totalDuration.isFinite, headerDuration.isFinite,
              headerDuration >= 0, totalDuration > headerDuration else { return 0 }
        let elapsed = min(max(playbackProgress, 0), 1) * totalDuration
        return min(max((elapsed - headerDuration) / (totalDuration - headerDuration), 0), 1)
    }
}
