import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SSTVKit

/// Patterned, multi-row receiver tests. These supplement (not replace) the
/// independent real-audio corpus still needed for a release-quality receiver.
final class ReceptionQualityTests: XCTestCase {
    func testPatternedReceptionAcrossEveryVISMode() async throws {
        for mode in SSTVMode.allCases {
            try await checkPattern(mode: mode, sampleRate: 12_000)
        }
    }

    func testPatternedReceptionAtDeviceAndFileSampleRates() async throws {
        for sampleRate in [44_100, 48_000] {
            for mode in [SSTVMode.robot36Color, .robot72Color, .martinM1, .pd120] {
                try await checkPattern(mode: mode, sampleRate: sampleRate)
            }
        }
    }

    func testRobot72CompleteFrameAtMicrophoneSampleRate() async throws {
        try await checkPattern(mode: .robot72Color, sampleRate: 48_000, radioLines: 240, scenario: "full-frame")
    }

    func testRobot72WithClockErrorFrequencyOffsetAndNoise() async throws {
        try await checkPattern(
            mode: .robot72Color, sampleRate: 48_000, radioLines: 64,
            scenario: "slow-offset-noise", clockScale: 1.001, addedFrequencyOffset: 120, noiseAmplitude: 0.015
        )
        try await checkPattern(
            mode: .robot72Color, sampleRate: 48_000, radioLines: 64,
            scenario: "fast-offset-noise", clockScale: 0.999, addedFrequencyOffset: -100, noiseAmplitude: 0.015
        )
        try await checkPattern(
            mode: .robot72Color, sampleRate: 48_000, radioLines: 64,
            scenario: "noise", noiseAmplitude: 0.03
        )
    }

    private func checkPattern(
        mode: SSTVMode, sampleRate: Int, radioLines: Int = 16,
        scenario: String = "clean", clockScale: Double = 1,
        addedFrequencyOffset: Double = 0, noiseAmplitude: Double = 0
    ) async throws {
        let source = image(width: mode.width, height: mode.height) { x, y in
            let gray: UInt8 = (y / 4).isMultiple(of: 2) ? 96 : 160
            let bars: [RGBPixel] = [
                .white, RGBPixel(red: 255, green: 255, blue: 0),
                RGBPixel(red: 0, green: 255, blue: 255), .green,
                RGBPixel(red: 255, green: 0, blue: 255), .red, .black,
                RGBPixel(red: gray, green: gray, blue: gray),
            ]
            return bars[min(7, x * 8 / mode.width)]
        }
        var writer = ToneWriter(sampleRate: sampleRate, amplitude: 0.8)
        // Disturb only the test signal. Model sample-clock error in both time
        // and pitch; do not modify the production encoder or baseline input.
        func impaired(_ segments: [ToneSegment]) -> [ToneSegment] {
            segments.map {
                ToneSegment(frequencyHz: $0.frequencyHz / clockScale + addedFrequencyOffset, duration: $0.duration * clockScale)
            }
        }
        writer.append(contentsOf: impaired(SSTVHeader.segments(visCode: mode.visCode)))
        writer.append(contentsOf: impaired(SSTVLineEncoder.framePrefix(for: mode)))
        for row in 0..<radioLines {
            writer.append(contentsOf: impaired(try SSTVLineEncoder.segments(for: source, mode: mode, row: row)))
        }
        writer.append(frequencyHz: 1_900, duration: 0.04)
        var audio = writer.samples
        if noiseAmplitude > 0 {
            var random: UInt64 = 0x72_C010_2026
            for index in audio.indices {
                random = random &* 6_364_136_223_846_793_005 &+ 1
                let noise = Double(random >> 32) / Double(UInt32.max) * 2 - 1
                audio[index] += Float(noise * noiseAmplitude)
            }
        }
        let decoder = try SSTVStreamDecoder(sampleRate: sampleRate)
        var offset = 0
        while offset < audio.count {
            let end = min(offset + 2_048, audio.count)
            _ = try await decoder.append(Array(audio[offset..<end]))
            offset = end
        }
        let frame = try await decoder.finish()
        let expectedRows = mode.family == .pd ? radioLines * 2 : radioLines
        let label = "\(mode.displayName) / \(sampleRate) Hz / \(scenario)"
        var maximumColorError = 0
        var colorErrorSum = 0
        var measuredComponents = 0
        var edgePositions: [Int] = []
        let edgeX = mode.width * 7 / 8
        // The first two raster rows and six pixels around each color transition
        // are a declared acquisition/filter boundary, not a post-hoc tolerance.
        for y in 2..<max(2, min(expectedRows, frame.completedRows)) {
            for bar in 0..<8 {
                let left = bar * mode.width / 8 + 6
                let right = (bar + 1) * mode.width / 8 - 6
                for x in left..<right {
                    let actual = frame.image[x, y]
                    let expected = source[x, y]
                    for error in [
                        abs(Int(actual.redValue) - Int(expected.redValue)),
                        abs(Int(actual.greenValue) - Int(expected.greenValue)),
                        abs(Int(actual.blueValue) - Int(expected.blueValue)),
                    ] {
                        maximumColorError = max(maximumColorError, error)
                        colorErrorSum += error
                        measuredComponents += 1
                    }
                }
            }
            let threshold = Double(source[edgeX + 10, y].redValue) / 2
            if let crossing = ((edgeX - 16)...(edgeX + 16)).first(where: { x in
                brightness(frame.image[x - 1, y]) < threshold
                    && brightness(frame.image[x, y]) >= threshold
            }) {
                edgePositions.append(crossing)
            }
        }
        let spread = (edgePositions.max() ?? edgeX) - (edgePositions.min() ?? edgeX)
        let maximumDisplacement = edgePositions.map { abs($0 - edgeX) }.max() ?? mode.width
        let report = Report(
            mode: mode.rawValue, sampleRate: sampleRate, completedRows: frame.completedRows,
            expectedRows: expectedRows, maximumColorError: maximumColorError,
            meanColorError: Double(colorErrorSum) / Double(max(1, measuredComponents)),
            edgeSpreadPixels: spread, maximumEdgeDisplacement: maximumDisplacement,
            measuredEdges: edgePositions.count, edgePositions: edgePositions,
            frequencyOffsetHz: frame.frequencyOffsetHz, scenario: scenario,
            clockScale: clockScale, addedFrequencyOffsetHz: addedFrequencyOffset, noiseAmplitude: noiseAmplitude
        )
        // Write before asserting, so a red CI run still supplies inspectable images.
        try writeArtifacts(report: report, source: source, decoded: frame.image)
        XCTAssertEqual(frame.mode, .sstv(mode), label)
        XCTAssertEqual(frame.completedRows, expectedRows, label)
        if expectedRows == mode.height { XCTAssertTrue(frame.isComplete, label) }
        XCTAssertGreaterThan(measuredComponents, 0, label)
        XCTAssertLessThanOrEqual(report.meanColorError, 12, label)
        XCTAssertLessThanOrEqual(maximumColorError, 24, label)
        XCTAssertEqual(edgePositions.count, expectedRows - 2, label)
        XCTAssertLessThanOrEqual(spread, 2, label)
        XCTAssertLessThanOrEqual(maximumDisplacement, 4, label)
    }

    private func brightness(_ pixel: RGBPixel) -> Double {
        Double(Int(pixel.redValue) + Int(pixel.greenValue) + Int(pixel.blueValue)) / 3
    }

    private struct Report: Codable {
        let mode: String
        let sampleRate: Int
        let completedRows: Int
        let expectedRows: Int
        let maximumColorError: Int
        let meanColorError: Double
        let edgeSpreadPixels: Int
        let maximumEdgeDisplacement: Int
        let measuredEdges: Int
        let edgePositions: [Int]
        let frequencyOffsetHz: Double
        let scenario: String
        let clockScale: Double
        let addedFrequencyOffsetHz: Double
        let noiseAmplitude: Double
    }

    private func writeArtifacts(report: Report, source: RGBImage, decoded: RGBImage) throws {
        guard let directory = ProcessInfo.processInfo.environment["SSTV_RECEIVE_QUALITY_OUTPUT"] else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = "\(report.mode)-\(report.sampleRate)-\(report.scenario)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: folder.appendingPathComponent(stem + ".json"), options: .atomic)
        try writePNG(source, to: folder.appendingPathComponent(stem + "-source.png"))
        try writePNG(decoded, to: folder.appendingPathComponent(stem + "-decoded.png"))
    }

    private func writePNG(_ raster: RGBImage, to url: URL) throws {
        let bytes = raster.pixels.flatMap { [$0.redValue, $0.greenValue, $0.blueValue] }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(
            width: raster.width, height: raster.height, bitsPerComponent: 8,
            bitsPerPixel: 24, bytesPerRow: raster.width * 3, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
