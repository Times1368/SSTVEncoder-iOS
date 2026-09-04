import Foundation

public actor SSTVStreamDecoder {
    public let sampleRate: Int
    public let selection: SSTVReceiveSelection

    private var demodulator: SSTVFrequencyDemodulator
    private var frequencies: [Float] = []
    private var headerSearchStart = 0
    private var frameAssembler: SSTVFrameAssembler?
    private var faxAssembler: HFFaxAssembler?

    public init(
        sampleRate: Int,
        selection: SSTVReceiveSelection = .automatic
    ) throws {
        self.sampleRate = sampleRate
        self.selection = selection
        demodulator = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        if case let .hfFax(profile) = selection {
            guard profile.width > 0,
                  profile.linesPerMinute > 0,
                  profile.maximumRows > 0 else {
                throw SSTVDecodeError.noImageData
            }
            faxAssembler = HFFaxAssembler(
                profile: profile,
                sampleRate: sampleRate,
                latencySamples: demodulator.latencySamples
            )
        }
    }

    public func append(_ samples: [Float]) throws -> SSTVDecodedFrame? {
        try Task.checkCancellation()
        guard !samples.isEmpty else { return nil }
        frequencies.append(contentsOf: demodulator.process(samples))

        if var faxAssembler {
            let changed = try faxAssembler.decodeAvailable(frequencies: frequencies)
            self.faxAssembler = faxAssembler
            return changed ? try faxAssembler.snapshot() : nil
        }

        if frameAssembler == nil {
            detectHeaderIfAvailable()
        }

        if var frameAssembler {
            let changed = try frameAssembler.decodeAvailable(frequencies: frequencies)
            self.frameAssembler = frameAssembler
            return changed ? try frameAssembler.snapshot() : nil
        }

        trimWaitingAudioIfNeeded()
        return nil
    }

    public func finish() throws -> SSTVDecodedFrame {
        try Task.checkCancellation()
        let flushCount = demodulator.latencySamples + 2
        if flushCount > 0 {
            frequencies.append(contentsOf: demodulator.process(
                Array(repeating: 0, count: flushCount)
            ))
        }

        if var faxAssembler {
            _ = try faxAssembler.decodeAvailable(frequencies: frequencies)
            self.faxAssembler = faxAssembler
            return try faxAssembler.snapshot()
        }

        if frameAssembler == nil {
            detectHeaderIfAvailable()
        }
        guard var frameAssembler else {
            throw SSTVDecodeError.headerNotFound
        }
        _ = try frameAssembler.decodeAvailable(frequencies: frequencies)
        self.frameAssembler = frameAssembler
        guard frameAssembler.completedRows > 0 else {
            throw SSTVDecodeError.noImageData
        }
        return try frameAssembler.snapshot()
    }

    private func detectHeaderIfAvailable() {
        guard let detection = SSTVHeaderDetector.detect(
            frequencies: frequencies,
            sampleRate: sampleRate,
            latencySamples: demodulator.latencySamples,
            searchStart: headerSearchStart
        ) else {
            let available = max(0, frequencies.count - demodulator.latencySamples)
            let overlap = Int((0.02 * Double(sampleRate)).rounded())
            let headerSamples = Int((0.905 * Double(sampleRate)).rounded())
            headerSearchStart = max(
                headerSearchStart,
                available - headerSamples - overlap
            )
            return
        }

        let mode: SSTVMode
        let source: SSTVDetectionSource
        switch selection {
        case .automatic:
            mode = detection.mode
            source = .vis
        case let .mode(selectedMode):
            mode = selectedMode
            source = .manual
        case .hfFax:
            return
        }

        let pictureStart = detection.pictureStartSample
        if pictureStart > 0, pictureStart <= frequencies.count {
            frequencies.removeFirst(pictureStart)
        }
        headerSearchStart = 0
        frameAssembler = SSTVFrameAssembler(
            mode: mode,
            detectionSource: source,
            pictureStartSample: 0,
            sampleRate: sampleRate,
            latencySamples: demodulator.latencySamples,
            frequencyOffsetHz: detection.frequencyOffsetHz
        )
    }

    private func trimWaitingAudioIfNeeded() {
        let maximum = sampleRate * 4
        let retained = sampleRate * 2
        guard frequencies.count > maximum else { return }
        let dropCount = frequencies.count - retained
        frequencies.removeFirst(dropCount)
        headerSearchStart = max(0, headerSearchStart - dropCount)
    }
}

public struct SSTVDecoder: Sendable {
    public let sampleRate: Int

    public init(sampleRate: Int) throws {
        _ = try SSTVFrequencyDemodulator(sampleRate: sampleRate)
        self.sampleRate = sampleRate
    }

    public func decode(
        _ buffer: PCMBuffer,
        selection: SSTVReceiveSelection = .automatic,
        progress: (@Sendable (SSTVDecodedFrame) async -> Void)? = nil
    ) async throws -> SSTVDecodedFrame {
        guard !buffer.samples.isEmpty else { throw SSTVDecodeError.emptyAudio }
        guard buffer.sampleRate == sampleRate else {
            throw SSTVDecodeError.invalidSampleRate(buffer.sampleRate)
        }

        let stream = try SSTVStreamDecoder(
            sampleRate: sampleRate,
            selection: selection
        )
        let chunkSize = max(2_048, sampleRate / 4)
        var offset = 0
        while offset < buffer.samples.count {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, buffer.samples.count)
            let chunk = Array(buffer.samples[offset..<end])
            if let frame = try await stream.append(chunk), let progress {
                await progress(frame)
            }
            offset = end
        }
        try Task.checkCancellation()
        let frame = try await stream.finish()
        if let progress {
            await progress(frame)
        }
        return frame
    }

    public func decode(
        _ samples: [Float],
        selection: SSTVReceiveSelection = .automatic,
        progress: (@Sendable (SSTVDecodedFrame) async -> Void)? = nil
    ) async throws -> SSTVDecodedFrame {
        try await decode(
            PCMBuffer(sampleRate: sampleRate, samples: samples),
            selection: selection,
            progress: progress
        )
    }
}
