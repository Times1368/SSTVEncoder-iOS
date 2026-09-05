import BaselineSupport
import Foundation
import SSTVKit

private enum BaselineGeneratorError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        "用法：BaselineGenerator <robot36Color|martinM1|pd120> <output-directory>"
    }
}

private struct BaselineRecord: Encodable {
    let fixtureID: String
    let fixtureFormula: String
    let modeID: String
    let modeName: String
    let filename: String
    let width: Int
    let height: Int
    let sampleRate: Int
    let amplitude: Double
    let sampleCount: Int
    let durationSeconds: Double
}

private struct RowOrderDiagnostic: Encodable {
    let modeID: String
    let expectedRows: Int
    let completedRows: Int?
    let isComplete: Bool
    let detectedModeMatches: Bool
    let measurement: RowOrderMeasurement?
    let error: String?
}

@main
private enum BaselineGenerator {
    private static let sampleRate = 48_000
    private static let amplitude = 0.8

    static func main() async throws {
        let filenames: [SSTVMode: String] = [
            .robot36Color: "Robot-36-Color.wav",
            .martinM1: "Martin-M1.wav",
            .pd120: "PD-120.wav",
        ]
        guard CommandLine.arguments.count == 3,
              let mode = SSTVMode(rawValue: CommandLine.arguments[1]),
              let filename = filenames[mode] else {
            throw BaselineGeneratorError.invalidArguments
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let raster = try CoordinateFixture.image(for: mode)
        let encoder = try SSTVEncoder(sampleRate: sampleRate, amplitude: amplitude)
        let signal = try await encoder.encode(raster, mode: mode)
        let wav = try WAVEncoder.encode(signal)
        try wav.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
        try writeJSON(BaselineRecord(
            fixtureID: CoordinateFixture.identifier,
            fixtureFormula: CoordinateFixture.formula,
            modeID: mode.rawValue,
            modeName: mode.displayName,
            filename: filename,
            width: raster.width,
            height: raster.height,
            sampleRate: signal.sampleRate,
            amplitude: amplitude,
            sampleCount: signal.samples.count,
            durationSeconds: signal.duration
        ), to: outputURL.appendingPathComponent("\(mode.rawValue).json"))
        print("已生成 \(filename)：\(signal.samples.count) 样本，\(signal.duration) 秒")

        // This diagnostic consumes the same PCM, without reading the WAV or a PNG.
        // Save it separately: decoder/orientation errors must not erase the baseline.
        let diagnostic: RowOrderDiagnostic
        do {
            let decoder = try SSTVDecoder(sampleRate: signal.sampleRate)
            let frame = try await decoder.decode(signal, selection: .automatic)
            let measurement = try RowOrderMeasurement.compare(source: raster, decoded: frame.image)
            diagnostic = RowOrderDiagnostic(
                modeID: mode.rawValue,
                expectedRows: mode.height,
                completedRows: frame.completedRows,
                isComplete: frame.isComplete,
                detectedModeMatches: frame.mode == .sstv(mode),
                measurement: measurement,
                error: nil
            )
            print("行序检查 \(mode.displayName)：\(measurement.status.rawValue)，\(frame.completedRows)/\(mode.height) 行")
        } catch {
            diagnostic = RowOrderDiagnostic(
                modeID: mode.rawValue,
                expectedRows: mode.height,
                completedRows: nil,
                isComplete: false,
                detectedModeMatches: false,
                measurement: nil,
                error: String(describing: error)
            )
            print("行序检查未完成 \(mode.displayName)：\(error)")
        }
        try writeJSON(diagnostic, to: outputURL.appendingPathComponent("\(mode.rawValue)-row-order.json"))
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
