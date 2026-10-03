import Combine
import Foundation
import SSTVKit
import UIKit

@MainActor
final class EncoderViewModel: ObservableObject {
    @Published private(set) var sourceImage: UIImage?
    @Published private(set) var preparedPreview: UIImage?
    @Published private(set) var encodedSignal: PCMBuffer?
    @Published private(set) var isEncoding = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?
    @Published var cropSelection = CropSelection.identity
    @Published private(set) var textOverlays: [TransmitTextOverlay] = []
    @Published private(set) var mode: SSTVMode = .robot36Color

    private var preparedRaster: RGBImage?
    private let session = EncoderSessionState<PCMBuffer>()
    private var encodingTask: Task<Void, Never>?

    var canEncode: Bool { preparedRaster != nil && !isEncoding }
    var canPlayOrExport: Bool { encodedSignal != nil && !isEncoding }
    var resolutionText: String { "\(mode.width) x \(mode.height)" }
    var durationText: String {
        Self.durationFormatter.string(from: encodedSignal?.duration ?? mode.totalDuration) ?? "--:--"
    }
    func playbackTimeText(progress: Double) -> String {
        let duration = encodedSignal?.duration ?? mode.totalDuration
        let elapsed = min(max(progress, 0), 1) * duration
        let elapsedText = Self.durationFormatter.string(from: elapsed) ?? "--:--"
        return "\(elapsedText) / \(durationText)"
    }
    var exportFilename: String {
        let modeName = mode.displayName.replacingOccurrences(of: " ", with: "-")
        return "SSTV-\(modeName)-48kHz.wav"
    }

    func beginImageSelection() {
        invalidate(for: .image)
        sourceImage = nil
        preparedPreview = nil
        preparedRaster = nil
        cropSelection = .identity
        errorMessage = nil
    }

    func loadImageData(_ data: Data) {
        guard let image = UIImage(data: data) else {
            errorMessage = "无法读取所选图片。"
            return
        }
        invalidate(for: .image)
        sourceImage = image
        cropSelection = .identity
        refreshPreparedImage()
    }

    func selectMode(_ newMode: SSTVMode) {
        guard newMode != mode else { return }
        invalidate(for: .mode)
        mode = newMode
        cropSelection = .identity
        refreshPreparedImage()
    }

    func cropDidChange() {
        invalidate(for: .crop)
        refreshPreparedImage()
    }

    func resetCrop() {
        guard cropSelection != .identity else { return }
        cropSelection = .identity
        cropDidChange()
    }

    @discardableResult
    func addTextOverlay(_ text: String = "") -> UUID {
        let overlay = TransmitTextOverlay(text: String(text.prefix(32)))
        textOverlays.append(overlay)
        overlaysDidChange()
        return overlay.id
    }

    func updateTextOverlay(_ id: UUID, text: String) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let limited = String(text.prefix(32))
        guard textOverlays[index].text != limited else { return }
        textOverlays[index].text = limited
        overlaysDidChange()
    }

    func moveTextOverlay(_ id: UUID, to position: CGPoint) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[index].position = CGPoint(
            x: min(max(position.x, 0), 1),
            y: min(max(position.y, 0), 1)
        )
        overlaysDidChange()
    }

    func removeTextOverlay(_ id: UUID) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays.remove(at: index)
        overlaysDidChange()
    }

    func startEncoding(onCompletion: (@MainActor (PCMBuffer) -> Void)? = nil) {
        guard let preparedRaster else { return }
        encodingTask?.cancel()

        let generation = session.beginEncoding()
        syncSessionState()
        let selectedMode = mode

        do {
            let encoder = try SSTVEncoder(sampleRate: 48_000, amplitude: 0.8)
            encodingTask = Task { [weak self] in
                do {
                    let signal = try await encoder.encode(
                        preparedRaster,
                        mode: selectedMode
                    ) { [weak self] value in
                        await self?.acceptProgress(value, generation: generation)
                    }
                    guard !Task.isCancelled else { return }
                    self?.publish(signal, generation: generation, onCompletion: onCompletion)
                } catch is CancellationError {
                    // Invalidation already clears the visible state.
                } catch {
                    self?.handleEncodingError(error, generation: generation)
                }
            }
        } catch {
            session.cancelEncoding()
            syncSessionState()
            errorMessage = error.localizedDescription
        }
    }

    func cancelEncoding() {
        encodingTask?.cancel()
        encodingTask = nil
        session.cancelEncoding()
        syncSessionState()
    }

    func makeExportDocument() throws -> WAVDocument {
        guard let encodedSignal else {
            throw ExportError.noCurrentSignal
        }
        return WAVDocument(data: try WAVEncoder.encode(encodedSignal))
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func dismissError() {
        errorMessage = nil
    }

    private func refreshPreparedImage() {
        guard let sourceImage else {
            preparedPreview = nil
            preparedRaster = nil
            return
        }
        do {
            let prepared = try ImagePreparer.prepare(
                image: sourceImage,
                mode: mode,
                selection: cropSelection,
                overlays: textOverlays
            )
            preparedPreview = prepared.preview
            preparedRaster = prepared.raster
        } catch {
            preparedPreview = nil
            preparedRaster = nil
            errorMessage = error.localizedDescription
        }
    }

    private func overlaysDidChange() {
        invalidate(for: .crop)
        refreshPreparedImage()
    }

    private func invalidate(for change: EncodingInputChange) {
        encodingTask?.cancel()
        encodingTask = nil
        session.invalidate(for: change)
        syncSessionState()
    }

    private func acceptProgress(
        _ value: Double,
        generation: EncoderSessionState<PCMBuffer>.Generation
    ) {
        if session.updateProgress(value, for: generation) {
            syncSessionState()
        }
    }

    private func publish(
        _ signal: PCMBuffer,
        generation: EncoderSessionState<PCMBuffer>.Generation,
        onCompletion: (@MainActor (PCMBuffer) -> Void)?
    ) {
        if session.publish(result: signal, for: generation) {
            encodingTask = nil
            syncSessionState()
            onCompletion?(signal)
        }
    }

    private func handleEncodingError(
        _ error: Error,
        generation: EncoderSessionState<PCMBuffer>.Generation
    ) {
        if session.failEncoding(for: generation) {
            encodingTask = nil
            syncSessionState()
            errorMessage = error.localizedDescription
        }
    }

    private func syncSessionState() {
        encodedSignal = session.result
        isEncoding = session.isEncoding
        progress = session.progress
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}

enum ExportError: LocalizedError {
    case noCurrentSignal

    var errorDescription: String? {
        "当前没有可导出的编码结果。"
    }
}
