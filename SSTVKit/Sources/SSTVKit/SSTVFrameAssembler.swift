import Foundation

final class SSTVFrameAssembler {
    let mode: SSTVMode
    let detectionSource: SSTVDetectionSource
    let sampleRate: Int
    let latencySamples: Int

    private(set) var frequencyOffsetHz: Double
    private(set) var completedRows = 0

    private var lineClock: SSTVLineClock
    private var pixels: [RGBPixel]
    private var nextScanLine = 0
    private var robotEvenLuma: [Double]?
    private var robotRedDifference: [Double]?

    init(
        mode: SSTVMode,
        detectionSource: SSTVDetectionSource,
        pictureStartSample: Int,
        firstLineStartSample: Int? = nil,
        sampleRate: Int,
        latencySamples: Int,
        frequencyOffsetHz: Double
    ) {
        self.mode = mode
        self.detectionSource = detectionSource
        self.sampleRate = sampleRate
        self.latencySamples = latencySamples
        self.frequencyOffsetHz = frequencyOffsetHz
        let initialLineStart = firstLineStartSample ?? (
            pictureStartSample
                + Int((mode.framePrefixDuration * Double(sampleRate)).rounded())
        )
        lineClock = SSTVLineClock(
            nominalPeriod: mode.lineDuration * Double(sampleRate),
            firstStart: Double(initialLineStart)
        )
        pixels = Array(repeating: .black, count: mode.width * mode.height)
    }

    var isComplete: Bool {
        completedRows >= mode.height
    }

    func decodeAvailable(frequencies: [Float]) throws -> Bool {
        let sampler = SSTVToneSampler(
            frequencies: frequencies,
            sampleRate: sampleRate,
            latencySamples: latencySamples
        )
        var changed = false

        while nextScanLine < mode.scanLineCount {
            try Task.checkCancellation()
            let expectedLineStart = Int(lineClock.nextStart.rounded())

            let syncOffset = Int((syncOffsetDuration * Double(sampleRate) * lineClock.timingScale).rounded())
            let expectedSyncStart = expectedLineStart + syncOffset
            let tolerance = sampler.samples(for: syncSearchTolerance)
            let enoughForSearch = sampler.availableRawSampleCount >= expectedSyncStart
                + tolerance + sampler.samples(for: syncDuration)

            var observedStart: Double?
            var measuredFrequencyOffset: Double?
            if enoughForSearch,
               let sync = sampler.bestToneStart(
                   near: expectedSyncStart,
                   tolerance: tolerance,
                   duration: syncDuration,
                   targetFrequency: 1_200 + frequencyOffsetHz
               ), sync.score <= 190 {
                observedStart = Double(sync.start - syncOffset)
                let measuredOffset = sync.mean - 1_200
                if abs(measuredOffset) <= 300 {
                    measuredFrequencyOffset = measuredOffset
                }
            }

            // Speculate on a value copy so repeated incomplete appends cannot
            // apply the same clock/frequency correction more than once.
            var nextClock = lineClock
            let lineStart = Int(nextClock.advance(observedStart: observedStart).rounded())
            var decodingSampler = sampler
            decodingSampler.timingScale = nextClock.timingScale
            let lineSamples = decodingSampler.samples(for: mode.lineDuration)
            guard lineStart >= 0,
                  lineStart + lineSamples <= sampler.availableRawSampleCount else {
                break
            }

            // Commit synchronization state only when this line can be decoded.
            // Otherwise repeated appends of an incomplete line would apply the
            // same correction multiple times and make output chunk-dependent.
            if let measuredFrequencyOffset {
                frequencyOffsetHz = frequencyOffsetHz * 0.75
                    + measuredFrequencyOffset * 0.25
            }

            let rowsBefore = completedRows
            decode(scanLine: nextScanLine, lineStart: lineStart, sampler: decodingSampler)
            nextScanLine += 1
            lineClock = nextClock
            changed = changed || completedRows != rowsBefore
        }

        return changed
    }

    func snapshot() throws -> SSTVDecodedFrame {
        SSTVDecodedFrame(
            image: try RGBImage(width: mode.width, height: mode.height, pixels: pixels),
            mode: .sstv(mode),
            detectionSource: detectionSource,
            completedRows: completedRows,
            totalRows: mode.height,
            isComplete: isComplete,
            frequencyOffsetHz: frequencyOffsetHz
        )
    }

    private var syncDuration: Double {
        switch mode.family {
        case .robot, .scottie: return 0.009
        case .pd: return 0.020
        case .martin: return 0.004862
        case .wraase: return 0.0055225
        }
    }

    private var syncOffsetDuration: Double {
        switch mode.family {
        case .scottie:
            return 2 * (mode.channelScanDuration + 0.0015)
        default:
            return 0
        }
    }

    private var syncSearchTolerance: Double {
        switch mode.family {
        case .pd: return 0.014
        case .robot, .scottie: return 0.009
        case .martin, .wraase: return 0.005
        }
    }

    private func decode(
        scanLine: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        switch mode {
        case .robot36Color:
            decodeRobot36(scanLine: scanLine, lineStart: lineStart, sampler: sampler)
        case .robot72Color:
            decodeRobot72(row: scanLine, lineStart: lineStart, sampler: sampler)
        case .pd50, .pd90, .pd120, .pd160, .pd180, .pd240, .pd290:
            decodePD(scanLine: scanLine, lineStart: lineStart, sampler: sampler)
        case .martinM1, .martinM2:
            decodeMartin(row: scanLine, lineStart: lineStart, sampler: sampler)
        case .scottieS1, .scottieS2, .scottieDX:
            decodeScottie(row: scanLine, lineStart: lineStart, sampler: sampler)
        case .wraaseSC2180:
            decodeWraase(row: scanLine, lineStart: lineStart, sampler: sampler)
        }
    }

    private func decodeRobot36(
        scanLine: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        let yStart = lineStart + sampler.samples(for: 0.012)
        let chromaStart = lineStart + sampler.samples(for: 0.106)
        var luminance: [Double] = []
        var chroma: [Double] = []
        luminance.reserveCapacity(mode.width)
        chroma.reserveCapacity(mode.width)
        for x in 0..<mode.width {
            luminance.append(sampler.component(
                scanStart: yStart,
                scanDuration: 0.088,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            ))
            chroma.append(sampler.component(
                scanStart: chromaStart,
                scanDuration: 0.044,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            ))
        }

        if scanLine.isMultiple(of: 2) {
            robotEvenLuma = luminance
            robotRedDifference = chroma
            for x in 0..<mode.width {
                pixels[scanLine * mode.width + x] = yuvPixel(
                    y: luminance[x],
                    redDifference: chroma[x],
                    blueDifference: 128
                )
            }
            return
        }

        let evenRow = scanLine - 1
        let evenLuma = robotEvenLuma ?? luminance
        let redDifference = robotRedDifference ?? Array(repeating: 128, count: mode.width)
        for x in 0..<mode.width {
            pixels[evenRow * mode.width + x] = yuvPixel(
                y: evenLuma[x],
                redDifference: redDifference[x],
                blueDifference: chroma[x]
            )
            pixels[scanLine * mode.width + x] = yuvPixel(
                y: luminance[x],
                redDifference: redDifference[x],
                blueDifference: chroma[x]
            )
        }
        robotEvenLuma = nil
        robotRedDifference = nil
        completedRows = max(completedRows, min(mode.height, scanLine + 1))
    }

    private func decodeRobot72(
        row: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        let yStart = lineStart + sampler.samples(for: 0.012)
        let redDifferenceStart = lineStart + sampler.samples(for: 0.156)
        let blueDifferenceStart = lineStart + sampler.samples(for: 0.231)
        for x in 0..<mode.width {
            let y = sampler.component(
                scanStart: yStart,
                scanDuration: 0.138,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let redDifference = sampler.component(
                scanStart: redDifferenceStart,
                scanDuration: 0.069,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let blueDifference = sampler.component(
                scanStart: blueDifferenceStart,
                scanDuration: 0.069,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            pixels[row * mode.width + x] = yuvPixel(
                y: y,
                redDifference: redDifference,
                blueDifference: blueDifference
            )
        }
        completedRows = max(completedRows, min(mode.height, row + 1))
    }

    private func decodePD(
        scanLine: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        let channel = mode.channelScanDuration
        let firstStart = lineStart + sampler.samples(for: 0.02208)
        let redDifferenceStart = firstStart + sampler.samples(for: channel)
        let blueDifferenceStart = firstStart + sampler.samples(for: 2 * channel)
        let secondStart = firstStart + sampler.samples(for: 3 * channel)
        let firstRow = scanLine * 2
        let secondRow = firstRow + 1

        for x in 0..<mode.width {
            let firstY = sampler.component(
                scanStart: firstStart,
                scanDuration: channel,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let redDifference = sampler.component(
                scanStart: redDifferenceStart,
                scanDuration: channel,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let blueDifference = sampler.component(
                scanStart: blueDifferenceStart,
                scanDuration: channel,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let secondY = sampler.component(
                scanStart: secondStart,
                scanDuration: channel,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            pixels[firstRow * mode.width + x] = yuvPixel(
                y: firstY,
                redDifference: redDifference,
                blueDifference: blueDifference
            )
            pixels[secondRow * mode.width + x] = yuvPixel(
                y: secondY,
                redDifference: redDifference,
                blueDifference: blueDifference
            )
        }
        completedRows = max(completedRows, min(mode.height, secondRow + 1))
    }

    private func decodeMartin(
        row: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        let channel = mode.channelScanDuration
        let greenStart = lineStart + sampler.samples(for: 0.005434)
        let blueStart = greenStart + sampler.samples(for: channel + 0.000572)
        let redStart = blueStart + sampler.samples(for: channel + 0.000572)
        decodeRGBRow(
            row: row,
            redStart: redStart,
            greenStart: greenStart,
            blueStart: blueStart,
            channelDuration: channel,
            sampler: sampler
        )
    }

    private func decodeScottie(
        row: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        let channel = mode.channelScanDuration
        let greenStart = lineStart + sampler.samples(for: 0.0015)
        let blueStart = lineStart + sampler.samples(for: channel + 0.003)
        let redStart = lineStart + sampler.samples(for: 2 * channel + 0.0135)
        decodeRGBRow(
            row: row,
            redStart: redStart,
            greenStart: greenStart,
            blueStart: blueStart,
            channelDuration: channel,
            sampler: sampler
        )
    }

    private func decodeWraase(
        row: Int,
        lineStart: Int,
        sampler: SSTVToneSampler
    ) {
        let channel = mode.channelScanDuration
        let redStart = lineStart + sampler.samples(for: 0.0060225)
        let greenStart = redStart + sampler.samples(for: channel)
        let blueStart = greenStart + sampler.samples(for: channel)
        decodeRGBRow(
            row: row,
            redStart: redStart,
            greenStart: greenStart,
            blueStart: blueStart,
            channelDuration: channel,
            sampler: sampler
        )
    }

    private func decodeRGBRow(
        row: Int,
        redStart: Int,
        greenStart: Int,
        blueStart: Int,
        channelDuration: Double,
        sampler: SSTVToneSampler
    ) {
        for x in 0..<mode.width {
            let red = sampler.component(
                scanStart: redStart,
                scanDuration: channelDuration,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let green = sampler.component(
                scanStart: greenStart,
                scanDuration: channelDuration,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            let blue = sampler.component(
                scanStart: blueStart,
                scanDuration: channelDuration,
                pixel: x,
                width: mode.width,
                frequencyOffset: frequencyOffsetHz
            )
            pixels[row * mode.width + x] = RGBPixel(
                red: byte(red),
                green: byte(green),
                blue: byte(blue)
            )
        }
        completedRows = max(completedRows, min(mode.height, row + 1))
    }

    private func yuvPixel(
        y: Double,
        redDifference: Double,
        blueDifference: Double
    ) -> RGBPixel {
        let scaledY = 1.164 * (y - 16)
        let red = scaledY + 1.596 * (redDifference - 128)
        let green = scaledY - 0.813 * (redDifference - 128)
            - 0.391 * (blueDifference - 128)
        let blue = scaledY + 2.018 * (blueDifference - 128)
        return RGBPixel(red: byte(red), green: byte(green), blue: byte(blue))
    }

    private func byte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, Int(value.rounded()))))
    }
}
