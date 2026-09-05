import XCTest
@testable import SSTVEncoder

final class MicrophoneCaptureBufferTests: XCTestCase {
    func testOverflowKeepsContiguousPrefixThenReportsError() async throws {
        let buffer = MicrophoneCaptureBuffer(capacity: 2)
        buffer.yield([1], sampleTime: 0)
        buffer.yield([2], sampleTime: 1)
        buffer.yield([3], sampleTime: 2)
        var iterator = buffer.stream.makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        XCTAssertEqual(first?.samples, [1])
        XCTAssertEqual(second?.samples, [2])
        do {
            _ = try await iterator.next()
            XCTFail("Overflow must not silently splice later audio into the image")
        } catch {
            XCTAssertEqual(error as? MicrophoneCaptureError, .bufferOverflow)
        }
    }

    func testHardwareTimestampGapIsDetectedBeforeDecoding() throws {
        var continuity = MicrophoneContinuityChecker()
        try continuity.accept(MicrophoneAudioChunk(samples: [1, 2], sampleTime: 100))
        try continuity.accept(MicrophoneAudioChunk(samples: [3, 4], sampleTime: 102))
        XCTAssertThrowsError(try continuity.accept(MicrophoneAudioChunk(samples: [5], sampleTime: 105))) {
            XCTAssertEqual($0 as? MicrophoneCaptureError, .discontinuousAudio)
        }
    }

    func testTimestampRestartAndOverlapAreNotTreatedAsContiguous() throws {
        var continuity = MicrophoneContinuityChecker()
        try continuity.accept(MicrophoneAudioChunk(samples: [1, 2], sampleTime: 100))
        XCTAssertThrowsError(try continuity.accept(MicrophoneAudioChunk(samples: [3], sampleTime: 0)))
    }

    func testAbsentHardwareTimeDoesNotInventAGap() throws {
        var continuity = MicrophoneContinuityChecker()
        try continuity.accept(MicrophoneAudioChunk(samples: [1], sampleTime: 100))
        try continuity.accept(MicrophoneAudioChunk(samples: [2], sampleTime: nil))
        try continuity.accept(MicrophoneAudioChunk(samples: [3], sampleTime: 102))
    }
}
