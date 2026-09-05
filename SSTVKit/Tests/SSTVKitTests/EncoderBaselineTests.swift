import CryptoKit
import Foundation
import XCTest
@testable import SSTVKit

final class EncoderBaselineTests: XCTestCase {
    func testSwift59WAVsMatchFrozenEncoderBaseline() async throws {
        guard ProcessInfo.processInfo.environment["SSTV_VERIFY_ENCODER_BASELINE"] == "1" else {
            throw XCTSkip("Exact WAV hashes are checked only in the pinned Swift 5.9 Release CI job.")
        }
        let cases: [(SSTVMode, String, String)] = [
            (.robot36Color, "Robot-36-Color", "2acfaaab8b5dd14b17f283f1d4b05815259e1eb60ff461d69fe33ae3d14fa3fb"),
            (.martinM1, "Martin-M1", "c8d217e84aeb81c83a76d00b83b4791fd3b9f370d65112d280e2c29c5c6c6251"),
            (.pd120, "PD-120", "8553fc7fb48ac291245df7f9bbd79bf210cb209a39115ce04dd2416ab0dc5e52"),
        ]
        var checksums: [String] = []
        let folder = ProcessInfo.processInfo.environment["SSTV_RECEIVE_QUALITY_OUTPUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("encoder-check", isDirectory: true)
        }
        if let folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for (mode, filename, expectedHash) in cases {
            let source = image(width: mode.width, height: mode.height) { x, y in
                RGBPixel(
                    red: UInt8((x * 8) % 256),
                    green: UInt8((y * 8) % 256),
                    blue: UInt8(((x + y) * 4) % 256)
                )
            }
            let encoder = try SSTVEncoder(sampleRate: 48_000, amplitude: 0.8)
            let buffer = try await encoder.encode(source, mode: mode)
            let data = try WAVEncoder.encode(buffer)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            checksums.append("\(hash)  \(filename).wav")
            if let folder {
                try data.write(to: folder.appendingPathComponent(filename + ".wav"), options: .atomic)
            }
            XCTAssertEqual(buffer.duration, mode.totalDuration, accuracy: 1.0 / 48_000, mode.displayName)
            XCTAssertEqual(hash, expectedHash, "Encoding changed: \(mode.displayName)")
        }
        if let folder {
            try (checksums.joined(separator: "\n") + "\n").write(
                to: folder.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8
            )
        }
    }
}
