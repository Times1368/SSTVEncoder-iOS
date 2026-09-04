import XCTest
@testable import SSTVKit

final class EncoderTests: XCTestCase {
    func testFullFramesHaveExact48kHzSampleCounts() async throws {
        let encoder = try SSTVEncoder(sampleRate: 48_000, amplitude: 0.8)
        let expected: [SSTVMode: Int] = [
            .robot36Color: 1_771_680,
            .robot72Color: 3_499_680,
            .pd50: 2_428_535,
            .pd90: 4_363_158,
            .pd120: 6_096_626,
            .pd160: 7_766_074,
            .pd180: 9_022_153,
            .pd240: 11_947_680,
            .pd290: 13_900_428,
            .martinM1: 5_529_608,
            .martinM2: 2_830_574,
            .scottieS1: 5_306_079,
            .scottieS2: 3_456_391,
            .scottieDX: 12_950_198,
            .wraaseSC2180: 8_780_724,
        ]

        XCTAssertEqual(expected.count, SSTVMode.allCases.count)
        for mode in SSTVMode.allCases {
            let signal = try await encoder.encode(solidImage(for: mode), mode: mode)
            XCTAssertEqual(signal.sampleRate, 48_000)
            XCTAssertEqual(signal.samples.count, expected[mode])
            XCTAssertEqual(signal.duration, mode.totalDuration, accuracy: 1.0 / 48_000)
        }
    }

    func testEncodingIsDeterministic() async throws {
        let encoder = try SSTVEncoder(sampleRate: 48_000, amplitude: 0.8)
        let image = solidImage(for: .robot36Color, pixel: .green)

        let first = try await encoder.encode(image, mode: .robot36Color)
        let second = try await encoder.encode(image, mode: .robot36Color)

        XCTAssertEqual(first.samples, second.samples)
    }

    func testProgressIsMonotonicAndFinishesAtOne() async throws {
        let recorder = ProgressRecorder()
        let encoder = try SSTVEncoder(sampleRate: 48_000, amplitude: 0.8)
        _ = try await encoder.encode(
            solidImage(for: .robot36Color),
            mode: .robot36Color
        ) { value in
            await recorder.append(value)
        }
        let values = await recorder.values()

        XCTAssertEqual(values.count, 240)
        XCTAssertEqual(values.last ?? -1, 1.0)
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0.0 <= $0.1 })
    }

    func testPDProgressCountsTwoRasterRowsAsOneRadioLine() async throws {
        let recorder = ProgressRecorder()
        let encoder = try SSTVEncoder(sampleRate: 8_000, amplitude: 0)
        _ = try await encoder.encode(solidImage(for: .pd50), mode: .pd50) { value in
            await recorder.append(value)
        }
        let values = await recorder.values()

        XCTAssertEqual(values.count, SSTVMode.pd50.scanLineCount)
        XCTAssertEqual(values.first ?? -1, 1.0 / 128.0, accuracy: 0.000_000_1)
        XCTAssertEqual(values.last ?? -1, 1.0, accuracy: 0.000_000_1)
    }

    func testCancellationIsObservedAfterEncodingHasStarted() async throws {
        let recorder = ProgressRecorder()
        let encoder = try SSTVEncoder(sampleRate: 48_000, amplitude: 0.8)
        let task = Task {
            try await encoder.encode(
                solidImage(for: .martinM1),
                mode: .martinM1
            ) { value in
                await recorder.append(value)
                withUnsafeCurrentTask { current in
                    current?.cancel()
                }
            }
        }

        do {
            _ = try await task.value
            XCTFail("Expected encoding to observe task cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let values = await recorder.values()
        XCTAssertEqual(values.count, 1)
        if let first = values.first {
            XCTAssertGreaterThan(first, 0)
            XCTAssertLessThan(first, 1)
        }
    }

    func testRejectsInvalidConfigurationAndRasterSize() async throws {
        XCTAssertThrowsError(try SSTVEncoder(sampleRate: 0))
        XCTAssertThrowsError(try SSTVEncoder(sampleRate: .max))
        XCTAssertThrowsError(try SSTVEncoder(sampleRate: 48_000, amplitude: -0.1))
        XCTAssertThrowsError(try SSTVEncoder(sampleRate: 48_000, amplitude: 1.1))
        XCTAssertThrowsError(try SSTVEncoder(sampleRate: 48_000, amplitude: .nan))
        XCTAssertThrowsError(try SSTVEncoder(sampleRate: 48_000, amplitude: .infinity))

        let encoder = try SSTVEncoder()
        let wrong = try RGBImage(width: 1, height: 1, pixels: [.black])
        do {
            _ = try await encoder.encode(wrong, mode: .robot36Color)
            XCTFail("Expected an image-size error")
        } catch let error as SSTVEncodingError {
            XCTAssertEqual(
                error,
                .imageSizeMismatch(expectedWidth: 320, expectedHeight: 240, actualWidth: 1, actualHeight: 1)
            )
        }
    }
}
