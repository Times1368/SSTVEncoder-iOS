import XCTest
@testable import SSTVKit

final class HFFaxDecoderTests: XCTestCase {
    func testContribHFFaxDecodesIOC576At120LinesPerMinute() async throws {
        let sampleRate = 12_000
        let profile = HFFaxProfile.ioc576_120
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        for _ in 0..<2 {
            writer.append(frequencyHz: 1_500, duration: 0.250)
            writer.append(frequencyHz: 2_300, duration: 0.250)
        }
        let buffer = try PCMBuffer(sampleRate: sampleRate, samples: writer.samples)
        let decoder = try SSTVDecoder(sampleRate: sampleRate)

        let frame = try await decoder.decode(buffer, selection: .hfFax(profile))

        XCTAssertEqual(profile.displayName, "Contrib / HF Fax")
        XCTAssertEqual(profile.width, 1_808)
        XCTAssertEqual(profile.lineDuration, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(frame.mode, .hfFax(profile))
        XCTAssertEqual(frame.detectionSource, .manual)
        XCTAssertEqual(frame.completedRows, 2)
        XCTAssertNil(frame.totalRows)
        XCTAssertFalse(frame.isComplete)
        XCTAssertEqual(frame.image.width, 1_808)
        XCTAssertEqual(frame.image.height, 2)

        XCTAssertLessThan(frame.image[200, 0].redValue, 24)
        XCTAssertGreaterThan(frame.image[1_600, 0].redValue, 231)
    }

    func testHFFaxHasNoVISAndCannotBeAutomaticallySelected() async throws {
        let sampleRate = 12_000
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        writer.append(frequencyHz: 2_300, duration: 1.0)
        let buffer = try PCMBuffer(sampleRate: sampleRate, samples: writer.samples)
        let decoder = try SSTVDecoder(sampleRate: sampleRate)

        do {
            _ = try await decoder.decode(buffer, selection: .automatic)
            XCTFail("HF Fax must remain a manual receive profile")
        } catch let error as SSTVDecodeError {
            XCTAssertEqual(error, .headerNotFound)
        }
    }
}
