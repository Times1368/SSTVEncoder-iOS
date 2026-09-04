import XCTest
@testable import SSTVKit

final class WAVEncoderTests: XCTestCase {
    func testWritesCanonicalMono16BitPCMHeaderAndPayload() throws {
        let buffer = try PCMBuffer(
            sampleRate: 48_000,
            samples: [-2, -1, -0.5, 0, 0.5, 1, 2]
        )
        let wav = try WAVEncoder.encode(buffer)

        XCTAssertEqual(wav.count, 44 + 14)
        XCTAssertEqual(wav.ascii(at: 0, count: 4), "RIFF")
        XCTAssertEqual(wav.uint32LE(at: 4), UInt32(wav.count - 8))
        XCTAssertEqual(wav.ascii(at: 8, count: 4), "WAVE")
        XCTAssertEqual(wav.ascii(at: 12, count: 4), "fmt ")
        XCTAssertEqual(wav.uint32LE(at: 16), 16)
        XCTAssertEqual(wav.uint16LE(at: 20), 1)
        XCTAssertEqual(wav.uint16LE(at: 22), 1)
        XCTAssertEqual(wav.uint32LE(at: 24), 48_000)
        XCTAssertEqual(wav.uint32LE(at: 28), 96_000)
        XCTAssertEqual(wav.uint16LE(at: 32), 2)
        XCTAssertEqual(wav.uint16LE(at: 34), 16)
        XCTAssertEqual(wav.ascii(at: 36, count: 4), "data")
        XCTAssertEqual(wav.uint32LE(at: 40), 14)

        let actual = stride(from: 44, to: wav.count, by: 2).map { wav.int16LE(at: $0) }
        XCTAssertEqual(actual, [-32_768, -32_768, -16_384, 0, 16_384, 32_767, 32_767])
    }

    func testRejectsUnsupportedSampleRateOrOversizedPayload() {
        XCTAssertThrowsError(try PCMBuffer(sampleRate: 0, samples: []))
        XCTAssertThrowsError(try WAVEncoder.encodeRawPCM(sampleRate: 48_000, byteCount: 1))
        XCTAssertThrowsError(try WAVEncoder.encodeRawPCM(sampleRate: 48_000, byteCount: UInt64(UInt32.max)))
    }
}
