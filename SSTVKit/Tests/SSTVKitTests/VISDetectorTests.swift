import XCTest
@testable import SSTVKit

final class VISDetectorTests: XCTestCase {
    func testDetectsEverySupportedVISCodeWithSilenceAndFrequencyOffset() throws {
        let sampleRate = 12_000
        let leadingSilence = sampleRate / 7
        let frequencyOffset = 47.0

        for mode in SSTVMode.allCases {
            var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
            for segment in SSTVHeader.segments(visCode: mode.visCode) {
                writer.append(
                    frequencyHz: segment.frequencyHz + frequencyOffset,
                    duration: segment.duration
                )
            }
            let buffer = try PCMBuffer(
                sampleRate: sampleRate,
                samples: Array(repeating: 0, count: leadingSilence) + writer.samples
            )

            let detection = try XCTUnwrap(SSTVHeaderDetector.detect(in: buffer), mode.displayName)
            XCTAssertEqual(detection.mode, mode)
            XCTAssertLessThanOrEqual(
                abs(detection.headerStartSample - leadingSilence),
                sampleRate / 250
            )
            let expectedPictureStart = leadingSilence
                + Int((SSTVHeader.duration * Double(sampleRate)).rounded())
            XCTAssertLessThanOrEqual(
                abs(detection.pictureStartSample - expectedPictureStart),
                sampleRate / 250
            )
            XCTAssertEqual(detection.frequencyOffsetHz, frequencyOffset, accuracy: 12)
        }
    }

    func testRejectsInvalidVISParity() throws {
        let sampleRate = 12_000
        let mode = SSTVMode.robot36Color
        var bits = SSTVHeader.bits(visCode: mode.visCode)
        bits[7].toggle()

        var segments = [
            ToneSegment(frequencyHz: 1_900, duration: 0.300),
            ToneSegment(frequencyHz: 1_200, duration: 0.010),
            ToneSegment(frequencyHz: 1_900, duration: 0.300),
            ToneSegment(frequencyHz: 1_200, duration: 0.030),
        ]
        segments.append(contentsOf: bits.map {
            ToneSegment(frequencyHz: $0 ? 1_100 : 1_300, duration: 0.030)
        })
        segments.append(ToneSegment(frequencyHz: 1_200, duration: 0.030))

        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(contentsOf: segments)
        let buffer = try PCMBuffer(sampleRate: sampleRate, samples: writer.samples)

        XCTAssertNil(SSTVHeaderDetector.detect(in: buffer))
    }

    func testVISLookupRejectsUnknownCodes() {
        XCTAssertEqual(SSTVMode(visCode: 8), .robot36Color)
        XCTAssertEqual(SSTVMode(visCode: 97), .pd240)
        XCTAssertNil(SSTVMode(visCode: 1))
    }
}
