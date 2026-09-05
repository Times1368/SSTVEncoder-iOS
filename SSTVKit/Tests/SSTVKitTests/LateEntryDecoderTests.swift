import Foundation
import XCTest
@testable import SSTVKit

final class LateEntryDecoderTests: XCTestCase {
    func testAutomaticReceptionCanJoinEveryModeInsideItsPicture() async throws {
        for mode in SSTVMode.allCases {
            let audio = try signal(mode: mode, sampleRate: 12_000, skippedLines: 8.37)
            let frame = try await SSTVDecoder(sampleRate: 12_000).decode(audio)
            check(frame, mode: mode)
        }
    }

    func testRobot36RecoversColorPairsAfterEvenAndOddEntryPoints() async throws {
        for skippedLines in [8.37, 9.37] {
            let audio = try signal(mode: .robot36Color, sampleRate: 48_000, skippedLines: skippedLines)
            let frame = try await SSTVDecoder(sampleRate: 48_000).decode(audio)
            check(frame, mode: .robot36Color)
        }
    }

    func testLateRobot72ReceptionToleratesFrequencyAndSampleClockOffset() async throws {
        for (scale, offset) in [(0.999, -100.0), (1.001, 120.0)] {
            // 17.37 lines enters more than five seconds into Robot 72's picture.
            let audio = try signal(
                mode: .robot72Color, sampleRate: 48_000, skippedLines: 17.37,
                clockScale: scale, frequencyOffset: offset, frequencyDriftPerLine: 0.5
            )
            let frame = try await SSTVDecoder(sampleRate: 48_000).decode(audio)
            check(frame, mode: .robot72Color)
        }
    }

    func testLateEntryDoesNotDependOnAppendChunkBoundaries() async throws {
        let audio = try signal(mode: .robot72Color, sampleRate: 12_000, skippedLines: 8.37)
        let whole = try SSTVStreamDecoder(sampleRate: 12_000)
        _ = try await whole.append(audio.samples)
        let expected = try await whole.finish()
        let chunked = try SSTVStreamDecoder(sampleRate: 12_000)
        let sizes = [137, 4_093, 701, 2_048]
        var offset = 0
        var index = 0
        while offset < audio.samples.count {
            let end = min(offset + sizes[index % sizes.count], audio.samples.count)
            _ = try await chunked.append(Array(audio.samples[offset..<end]))
            offset = end
            index += 1
        }
        let actual = try await chunked.finish()
        XCTAssertEqual(actual.mode, expected.mode)
        XCTAssertEqual(actual.completedRows, expected.completedRows)
        XCTAssertEqual(actual.image, expected.image)
    }

    func testAutomaticLateEntrySurvivesWaitingBufferTrims() async throws {
        let body = try signal(mode: .scottieDX, sampleRate: 12_000, skippedLines: 8.37)
        let audio = try PCMBuffer(sampleRate: 12_000, samples: [Float](repeating: 0, count: 12_000 * 12) + body.samples)
        let frame = try await SSTVDecoder(sampleRate: 12_000).decode(audio)
        check(frame, mode: .scottieDX)
    }

    func testSilenceContinuousCarrierAndNoiseCannotProduceAnAutomaticImage() async throws {
        var carrier = ToneWriter(sampleRate: 12_000, amplitude: 0.8)
        carrier.append(frequencyHz: 1_200, duration: 6)
        var random: UInt64 = 0x1A7E_2026
        let noise: [Float] = (0..<(12_000 * 6)).map { _ in
            random = random &* 6_364_136_223_846_793_005 &+ 1
            return Float(Double(random >> 32) / Double(UInt32.max) * 2 - 1) * 0.1
        }
        for samples in [[Float](repeating: 0, count: 12_000 * 6), carrier.samples, noise] {
            do {
                _ = try await SSTVDecoder(sampleRate: 12_000).decode(samples)
                XCTFail("Non-SSTV input must not acquire a mode")
            } catch let error as SSTVDecodeError {
                XCTAssertEqual(error, .headerNotFound)
            }
        }
    }

    private func signal(
        mode: SSTVMode, sampleRate: Int, skippedLines: Double,
        clockScale: Double = 1, frequencyOffset: Double = 0,
        frequencyDriftPerLine: Double = 0
    ) throws -> PCMBuffer {
        print("Late-entry fixture: \(mode.rawValue), \(sampleRate) Hz, skippedLines=\(skippedLines), clockScale=\(clockScale), frequencyOffset=\(frequencyOffset), driftPerLine=\(frequencyDriftPerLine)")
        let palette = bars
        let source = image(width: mode.width, height: mode.height) { x, _ in
            palette[min(7, x * 8 / mode.width)]
        }
        let lineCount = Int(skippedLines) + 20
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(contentsOf: SSTVHeader.segments(visCode: mode.visCode).map {
            ToneSegment(frequencyHz: $0.frequencyHz / clockScale + frequencyOffset, duration: $0.duration * clockScale)
        })
        writer.append(contentsOf: SSTVLineEncoder.framePrefix(for: mode).map {
            ToneSegment(frequencyHz: $0.frequencyHz / clockScale + frequencyOffset, duration: $0.duration * clockScale)
        })
        for row in 0..<lineCount {
            writer.append(contentsOf: try SSTVLineEncoder.segments(for: source, mode: mode, row: row).map {
                ToneSegment(
                    frequencyHz: $0.frequencyHz / clockScale + frequencyOffset + Double(row) * frequencyDriftPerLine,
                    duration: $0.duration * clockScale
                )
            })
        }
        let cut = Int(((SSTVHeader.duration + mode.framePrefixDuration + skippedLines * mode.lineDuration)
            * clockScale * Double(sampleRate)).rounded())
        return try PCMBuffer(sampleRate: sampleRate, samples: Array(writer.samples.dropFirst(cut)))
    }

    private var bars: [RGBPixel] {
        [.white, RGBPixel(red: 255, green: 255, blue: 0), RGBPixel(red: 0, green: 255, blue: 255),
         .green, RGBPixel(red: 255, green: 0, blue: 255), .red, .black, RGBPixel(red: 128, green: 128, blue: 128)]
    }

    private func check(_ frame: SSTVDecodedFrame, mode: SSTVMode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frame.mode, .sstv(mode), mode.displayName, file: file, line: line)
        XCTAssertEqual(frame.detectionSource, .lateEntry, mode.displayName, file: file, line: line)
        XCTAssertNil(frame.progress, "Missing VIS cannot establish whole-image progress", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.completedRows, 14, mode.displayName, file: file, line: line)
        XCTAssertFalse(frame.isComplete, mode.displayName, file: file, line: line)
        for y in 2..<min(frame.completedRows, 10) {
            for bar in 0..<8 {
                let actual = frame.image[(2 * bar + 1) * mode.width / 16, y]
                let expected = bars[bar]
                for error in [abs(Int(actual.redValue) - Int(expected.redValue)),
                              abs(Int(actual.greenValue) - Int(expected.greenValue)),
                              abs(Int(actual.blueValue) - Int(expected.blueValue))] {
                    XCTAssertLessThanOrEqual(error, 24, "\(mode.displayName), row=\(y), bar=\(bar)", file: file, line: line)
                }
            }
        }
    }
}
