// 新增于 SSTV 大改版 · T02
import CoreGraphics
import Foundation
import ImageIO
import SSTVKit

private enum BaselineGeneratorError: LocalizedError {
    case invalidArguments
    case unreadableFixture(URL)
    case invalidFixtureSize(width: Int, height: Int)
    case bitmapCreationFailed
    case unexpectedFixturePixel(x: Int, y: Int, actual: RGBPixel)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "用法：BaselineGenerator <testcard.png> <output-directory>"
        case let .unreadableFixture(url):
            return "无法读取基线测试图：\(url.path)"
        case let .invalidFixtureSize(width, height):
            return "基线测试图必须是 320×256，实际为 \(width)×\(height)"
        case .bitmapCreationFailed:
            return "无法创建测试图 RGBA 位图上下文"
        case let .unexpectedFixturePixel(x, y, actual):
            return "测试图像素校验失败 (\(x), \(y))：\(actual)"
        }
    }
}

private struct BaselineRecord: Encodable {
    let modeID: String
    let modeName: String
    let filename: String
    let sampleRate: Int
    let sampleCount: Int
    let durationSeconds: Double
}

private struct BaselineManifest: Encodable {
    let fixtureFilename: String
    let fixtureWidth: Int
    let fixtureHeight: Int
    let resizeRule: String
    let records: [BaselineRecord]
}

@main
private enum BaselineGenerator {
    private static let sampleRate = 48_000

    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw BaselineGeneratorError.invalidArguments
        }

        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let fixture = try loadFixture(from: fixtureURL)
        try validateFixture(fixture)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )

        let encoder = try SSTVEncoder(sampleRate: sampleRate, amplitude: 0.8)
        let cases: [(SSTVMode, String)] = [
            (.robot36Color, "Robot-36-Color.wav"),
            (.martinM1, "Martin-M1.wav"),
            (.pd120, "PD-120.wav"),
        ]
        var records: [BaselineRecord] = []

        for (mode, filename) in cases {
            let raster = try nearestNeighborResize(fixture, for: mode)
            let signal = try await encoder.encode(raster, mode: mode)
            let wav = try WAVEncoder.encode(signal)
            try wav.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
            records.append(
                BaselineRecord(
                    modeID: mode.rawValue,
                    modeName: mode.displayName,
                    filename: filename,
                    sampleRate: signal.sampleRate,
                    sampleCount: signal.samples.count,
                    durationSeconds: signal.duration
                )
            )
            print(
                "Generated \(filename): \(signal.samples.count) samples, "
                    + String(format: "%.9f seconds", signal.duration)
            )
        }

        let manifest = BaselineManifest(
            fixtureFilename: fixtureURL.lastPathComponent,
            fixtureWidth: fixture.width,
            fixtureHeight: fixture.height,
            resizeRule: "nearest-neighbor normalized stretch to each mode's native raster",
            records: records
        )
        let encoderJSON = JSONEncoder()
        encoderJSON.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoderJSON.encode(manifest)
        try data.write(
            to: outputURL.appendingPathComponent("baseline-metadata.json"),
            options: .atomic
        )
    }

    private static func loadFixture(from url: URL) throws -> RGBImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BaselineGeneratorError.unreadableFixture(url)
        }
        guard image.width == 320, image.height == 256 else {
            throw BaselineGeneratorError.invalidFixtureSize(
                width: image.width,
                height: image.height
            )
        }

        let bytesPerRow = image.width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        try rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                throw BaselineGeneratorError.bitmapCreationFailed
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.translateBy(x: 0, y: CGFloat(image.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }

        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(image.width * image.height)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            pixels.append(
                RGBPixel(
                    red: rgba[offset],
                    green: rgba[offset + 1],
                    blue: rgba[offset + 2]
                )
            )
        }
        return try RGBImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func validateFixture(_ image: RGBImage) throws {
        let expected: [(Int, Int, RGBPixel)] = [
            (0, 0, RGBPixel(red: 228, green: 236, blue: 248)),
            (319, 0, RGBPixel(red: 6, green: 10, blue: 20)),
            (0, 255, RGBPixel(red: 41, green: 42, blue: 45)),
            (319, 255, RGBPixel(red: 4, green: 7, blue: 14)),
        ]
        for (x, y, pixel) in expected {
            let actual = image[x, y]
            guard actual == pixel else {
                throw BaselineGeneratorError.unexpectedFixturePixel(
                    x: x,
                    y: y,
                    actual: actual
                )
            }
        }
    }

    private static func nearestNeighborResize(
        _ source: RGBImage,
        for mode: SSTVMode
    ) throws -> RGBImage {
        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(mode.width * mode.height)
        for y in 0..<mode.height {
            let sourceY = min(source.height - 1, y * source.height / mode.height)
            for x in 0..<mode.width {
                let sourceX = min(source.width - 1, x * source.width / mode.width)
                pixels.append(source[sourceX, sourceY])
            }
        }
        return try RGBImage(width: mode.width, height: mode.height, pixels: pixels)
    }
}
