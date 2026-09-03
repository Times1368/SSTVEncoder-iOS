import Foundation
import XCTest
@testable import SSTVKit

func solidImage(for mode: SSTVMode, pixel: RGBPixel = .black) -> RGBImage {
    try! RGBImage(
        width: mode.width,
        height: mode.height,
        pixels: Array(repeating: pixel, count: mode.width * mode.height)
    )
}

func image(
    width: Int,
    height: Int,
    pixelAt: (Int, Int) -> RGBPixel
) -> RGBImage {
    let pixels = (0..<height).flatMap { y in
        (0..<width).map { x in pixelAt(x, y) }
    }
    return try! RGBImage(width: width, height: height, pixels: pixels)
}

extension Data {
    func ascii(at offset: Int, count: Int) -> String {
        String(decoding: self[offset..<(offset + count)], as: UTF8.self)
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func int16LE(at offset: Int) -> Int16 {
        Int16(bitPattern: uint16LE(at: offset))
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}

actor ProgressRecorder {
    private var storage: [Double] = []

    func append(_ value: Double) {
        storage.append(value)
    }

    func values() -> [Double] {
        storage
    }
}

