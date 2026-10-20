import SSTVKit
import XCTest
@testable import SSTVEncoder

final class ContinuousStreamDecoderTests: XCTestCase {
    func testTwoCompletePicturesUseOneAudioStream() async throws {
        let mode = SSTVMode.robot36Color
        let image = try RGBImage(
            width: mode.width,
            height: mode.height,
            pixels: Array(repeating: .green, count: mode.width * mode.height)
        )
        let sampleRate = 12_000
        let pcm = try await SSTVKit.SSTVEncoder(sampleRate: sampleRate).encode(image, mode: mode)
        let silence = Array(repeating: Float.zero, count: sampleRate / 2)
        let samples = pcm.samples + silence + pcm.samples + silence
        let decoder = try ContinuousStreamDecoder(sampleRate: sampleRate, selection: .automatic)
        var completedModes: [SSTVDecodedMode] = []

        for start in stride(from: 0, to: samples.count, by: 2_048) {
            let end = min(start + 2_048, samples.count)
            if let frame = try await decoder.append(Array(samples[start..<end])), frame.isComplete {
                completedModes.append(frame.mode)
            }
        }

        XCTAssertEqual(completedModes, [.sstv(mode), .sstv(mode)])
        XCTAssertEqual(decoder.completedFrameCount, 2)
    }
}
