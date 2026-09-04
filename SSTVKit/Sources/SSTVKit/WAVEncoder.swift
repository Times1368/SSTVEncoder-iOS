import Foundation

public enum WAVEncodingError: Error, Sendable, Equatable {
    case invalidSampleRate(Int)
    case payloadTooLarge(UInt64)
}

public enum WAVEncoder {
    public static func encode(_ buffer: PCMBuffer) throws -> Data {
        let byteCount = UInt64(buffer.samples.count) * 2
        var data = try encodeRawPCM(sampleRate: buffer.sampleRate, byteCount: byteCount)
        data.reserveCapacity(44 + Int(byteCount))

        for sample in buffer.samples {
            var pcm = quantize(sample).littleEndian
            Swift.withUnsafeBytes(of: &pcm) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Creates a canonical RIFF/WAVE header for a mono signed PCM16 payload.
    public static func encodeRawPCM(sampleRate: Int, byteCount: UInt64) throws -> Data {
        guard sampleRate > 0,
              let rate = UInt32(exactly: sampleRate),
              sampleRate <= Int(UInt32.max / 2) else {
            throw WAVEncodingError.invalidSampleRate(sampleRate)
        }
        guard byteCount <= UInt64(UInt32.max) - 36,
              byteCount <= UInt64(Int.max) - 44 else {
            throw WAVEncodingError.payloadTooLarge(byteCount)
        }

        var data = Data()
        data.reserveCapacity(44)
        data.appendASCII("RIFF")
        data.appendLE(UInt32(36 + byteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1)) // PCM
        data.appendLE(UInt16(1)) // mono
        data.appendLE(rate)
        data.appendLE(rate * 2)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.appendASCII("data")
        data.appendLE(UInt32(byteCount))
        return data
    }

    private static func quantize(_ sample: Float) -> Int16 {
        if sample.isNaN { return 0 }
        if sample <= -1 { return Int16.min }
        if sample >= 1 { return Int16.max }

        let scaled = Double(sample) * 32_768
        let rounded = min(Double(Int16.max), max(Double(Int16.min), scaled.rounded()))
        return Int16(rounded)
    }
}

private extension Data {
    mutating func appendASCII(_ text: String) {
        append(contentsOf: text.utf8)
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
