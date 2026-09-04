import XCTest
@testable import SSTVKit

final class DecoderTests: XCTestCase {
    func testEncodeDecodeRoundTripCoversEveryProtocolFamily() async throws {
        let sampleRate = 12_000
        let cases: [(SSTVMode, RGBPixel, Int)] = [
            (.robot36Color, .red, 42),
            (.pd50, .green, 42),
            (.martinM2, .blue, 30),
            (.scottieS2, RGBPixel(red: 210, green: 80, blue: 40), 30),
            (.wraaseSC2180, .white, 24),
        ]

        for (mode, sourcePixel, tolerance) in cases {
            let encoder = try SSTVEncoder(sampleRate: sampleRate, amplitude: 0.8)
            let signal = try await encoder.encode(
                solidImage(for: mode, pixel: sourcePixel),
                mode: mode
            )
            let decoder = try SSTVDecoder(sampleRate: sampleRate)
            let frame = try await decoder.decode(signal, selection: .automatic)

            XCTAssertEqual(frame.mode, .sstv(mode), mode.displayName)
            XCTAssertEqual(frame.detectionSource, .vis, mode.displayName)
            XCTAssertTrue(frame.isComplete, mode.displayName)
            XCTAssertEqual(frame.completedRows, mode.height, mode.displayName)
            assertPixel(
                frame.image[mode.width / 2, mode.height / 2],
                isCloseTo: sourcePixel,
                tolerance: tolerance,
                mode.displayName
            )
        }
    }

    func testStreamingResultIsIndependentOfInputChunkBoundaries() async throws {
        let sampleRate = 12_000
        let mode = SSTVMode.robot36Color
        let source = RGBPixel(red: 36, green: 140, blue: 220)
        let encoder = try SSTVEncoder(sampleRate: sampleRate, amplitude: 0.8)
        let signal = try await encoder.encode(solidImage(for: mode, pixel: source), mode: mode)

        let contiguousDecoder = try SSTVStreamDecoder(
            sampleRate: sampleRate,
            selection: .automatic
        )
        _ = try await contiguousDecoder.append(signal.samples)
        let contiguous = try await contiguousDecoder.finish()

        let chunkedDecoder = try SSTVStreamDecoder(
            sampleRate: sampleRate,
            selection: .automatic
        )
        let chunkSizes = [137, 4_093, 29, 2_048, 701]
        var offset = 0
        var chunkIndex = 0
        while offset < signal.samples.count {
            let end = min(offset + chunkSizes[chunkIndex % chunkSizes.count], signal.samples.count)
            _ = try await chunkedDecoder.append(Array(signal.samples[offset..<end]))
            offset = end
            chunkIndex += 1
        }
        let chunked = try await chunkedDecoder.finish()

        XCTAssertEqual(chunked.mode, contiguous.mode)
        XCTAssertEqual(chunked.completedRows, contiguous.completedRows)
        XCTAssertEqual(chunked.image, contiguous.image)
    }

    func testTruncatedTransmissionReturnsTheProgressivePartialImage() async throws {
        let sampleRate = 12_000
        let mode = SSTVMode.robot36Color
        let encoder = try SSTVEncoder(sampleRate: sampleRate, amplitude: 0.8)
        let signal = try await encoder.encode(
            solidImage(for: mode, pixel: .green),
            mode: mode
        )
        let partialCount = Int(
            (SSTVHeader.duration + mode.lineDuration * 12.5) * Double(sampleRate)
        )
        let partial = try PCMBuffer(
            sampleRate: sampleRate,
            samples: Array(signal.samples.prefix(partialCount))
        )

        let decoder = try SSTVDecoder(sampleRate: sampleRate)
        let frame = try await decoder.decode(partial, selection: .automatic)

        XCTAssertEqual(frame.mode, .sstv(mode))
        XCTAssertGreaterThanOrEqual(frame.completedRows, 11)
        XCTAssertLessThan(frame.completedRows, mode.height)
        XCTAssertFalse(frame.isComplete)
    }

    func testDecodeObservesTaskCancellation() async throws {
        let sampleRate = 12_000
        let mode = SSTVMode.robot36Color
        let encoder = try SSTVEncoder(sampleRate: sampleRate, amplitude: 0.8)
        let signal = try await encoder.encode(solidImage(for: mode), mode: mode)
        let decoder = try SSTVDecoder(sampleRate: sampleRate)

        let task = Task {
            try await decoder.decode(signal, selection: .automatic) { frame in
                if frame.completedRows > 0 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }

        do {
            _ = try await task.value
            XCTFail("Expected decoding to observe cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    private func assertPixel(
        _ actual: RGBPixel,
        isCloseTo expected: RGBPixel,
        tolerance: Int,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            abs(Int(actual.redValue) - Int(expected.redValue)),
            tolerance,
            message,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(Int(actual.greenValue) - Int(expected.greenValue)),
            tolerance,
            message,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(Int(actual.blueValue) - Int(expected.blueValue)),
            tolerance,
            message,
            file: file,
            line: line
        )
    }
}
