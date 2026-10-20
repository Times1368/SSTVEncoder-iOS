import Foundation
import SSTVKit

/// Rotates the DSP decoder after each complete picture while the audio stream stays open.
final class ContinuousStreamDecoder {
    private let sampleRate: Int
    private let selection: SSTVReceiveSelection
    private var decoder: SSTVStreamDecoder
    private(set) var completedFrameCount = 0

    init(sampleRate: Int, selection: SSTVReceiveSelection) throws {
        self.sampleRate = sampleRate
        self.selection = selection
        decoder = try SSTVStreamDecoder(sampleRate: sampleRate, selection: selection)
    }

    func append(_ samples: [Float]) async throws -> SSTVDecodedFrame? {
        guard let frame = try await decoder.append(samples) else { return nil }
        if frame.isComplete {
            completedFrameCount += 1
            let next = try SSTVStreamDecoder(sampleRate: sampleRate, selection: selection)
            // A microphone chunk may contain the end of one picture and the
            // start of the next VIS header. Replay this one chunk so no header
            // samples are discarded at the boundary.
            switch selection {
            case .hfFax:
                // HF Fax has no header; a full page starts a fresh page.
                break
            case .automatic, .mode:
                _ = try await next.append(samples)
            }
            decoder = next
        }
        return frame
    }

    func finish() async throws -> SSTVDecodedFrame {
        try await decoder.finish()
    }
}
