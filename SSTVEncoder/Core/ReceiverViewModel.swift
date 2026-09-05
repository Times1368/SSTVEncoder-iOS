import Combine
import Foundation
import SSTVKit
import UIKit

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published private(set) var selection: SSTVReceiveSelection = .automatic
    @Published private(set) var decodedFrame: SSTVDecodedFrame?
    @Published private(set) var decodedImage: UIImage?
    @Published private(set) var isReceiving = false
    @Published private(set) var progress = 0.0
    @Published private(set) var statusText = "等待导入音频或启动麦克风。"
    @Published private(set) var errorMessage: String?

    private let session = ReceiverSessionState<SSTVDecodedFrame>()
    private let microphone = MicrophoneReceiver()
    private var receiveTask: Task<Void, Never>?
    private var streamDecoder: SSTVStreamDecoder?

    static let selections: [SSTVReceiveSelection] = [
        .automatic,
        .hfFax(.ioc576_120),
    ] + SSTVMode.allCases.map { .mode($0) }

    var canExport: Bool { decodedImage != nil }
    var isUsingMicrophone: Bool { session.input == .microphone }
    var modeText: String { decodedFrame?.mode.displayName ?? selection.displayName }
    var rowText: String {
        guard let frame = decodedFrame else { return "尚无图像" }
        if let totalRows = frame.totalRows {
            return "\(frame.completedRows) / \(totalRows) 行"
        }
        return "\(frame.completedRows) 行"
    }
    var detectionText: String {
        guard let frame = decodedFrame else {
            return selection == .automatic ? "等待 VIS" : "手动模式"
        }
        switch frame.detectionSource {
        case .vis: return "VIS 自动识别"
        case .manual: return "手动选择"
        case .timing: return "扫描时序推断"
        }
    }
    var exportFilename: String {
        let name = modeText
            .replacingOccurrences(of: " / ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "SSTV-Decoded-\(name).png"
    }

    func select(_ newSelection: SSTVReceiveSelection) {
        guard newSelection != selection else { return }
        stopReceiving(clearResult: true)
        selection = newSelection
        statusText = newSelection == .automatic
            ? "等待自动识别 SSTV VIS。"
            : "已选择 \(newSelection.displayName)。"
        errorMessage = nil
    }

    func decodeAudioFile(_ url: URL) {
        stopReceiving(clearResult: true)
        let accessed = url.startAccessingSecurityScopedResource()
        let generation = session.begin(input: .audioFile)
        syncSessionState()
        statusText = "正在读取音频文件…"
        errorMessage = nil
        let selectedMode = selection

        receiveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let buffer = try await Task.detached(priority: .userInitiated) {
                    try AudioFileLoader.load(
                        from: url,
                        manageSecurityScope: false
                    )
                }.value
                try Task.checkCancellation()
                statusText = selectedMode == .automatic
                    ? "正在搜索 VIS 并解码…"
                    : "正在按 \(selectedMode.displayName) 解码…"

                let decoder = try SSTVDecoder(sampleRate: buffer.sampleRate)
                let finalFrame = try await decoder.decode(
                    buffer,
                    selection: selectedMode
                ) { [weak self] frame in
                    await self?.publish(frame, generation: generation)
                }
                finish(finalFrame, generation: generation, source: .audioFile)
            } catch is CancellationError {
                // A stop, reset, or newer receive task owns the visible state.
            } catch {
                handle(error, generation: generation)
            }
        }
    }

    func startMicrophone() {
        stopReceiving(clearResult: true)
        let generation = session.begin(input: .microphone)
        syncSessionState()
        statusText = "正在请求麦克风并准备接收…"
        errorMessage = nil
        let selectedMode = selection

        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let capture = try await microphone.start()
                try Task.checkCancellation()
                let decoder = try SSTVStreamDecoder(
                    sampleRate: capture.sampleRate,
                    selection: selectedMode
                )
                streamDecoder = decoder
                statusText = selectedMode == .automatic
                    ? "正在监听，等待 SSTV VIS 头…"
                    : "正在接收 \(selectedMode.displayName)…"

                var completedFrame: SSTVDecodedFrame?
                var continuity = MicrophoneContinuityChecker()
                for try await chunk in capture.chunks {
                    try Task.checkCancellation()
                    try continuity.accept(chunk)
                    if let frame = try await decoder.append(chunk.samples) {
                        publish(frame, generation: generation)
                        if frame.isComplete {
                            completedFrame = frame
                            break
                        }
                    }
                }
                try Task.checkCancellation()
                let finalFrame: SSTVDecodedFrame
                if let completedFrame {
                    finalFrame = completedFrame
                } else {
                    finalFrame = try await decoder.finish()
                }
                microphone.stop()
                streamDecoder = nil
                finish(finalFrame, generation: generation, source: .microphone)
            } catch is CancellationError {
                // Explicit stop owns microphone and session cleanup.
            } catch {
                handle(error, generation: generation)
            }
        }
    }

    func stopReceiving(clearResult: Bool = false) {
        receiveTask?.cancel()
        receiveTask = nil
        microphone.stop()
        streamDecoder = nil
        let hadResult = session.result != nil
        session.cancel(clearResult: clearResult)
        syncSessionState()
        if clearResult {
            decodedImage = nil
            statusText = "等待导入音频或启动麦克风。"
        } else if hadResult {
            statusText = "接收已停止，保留当前图像。"
        } else {
            statusText = "接收已停止。"
        }
    }

    func makeExportDocument() throws -> PNGDocument {
        guard let data = decodedImage?.pngData() else {
            throw ReceiverExportError.noImage
        }
        return PNGDocument(data: data)
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func dismissError() {
        errorMessage = nil
    }

    private func publish(
        _ frame: SSTVDecodedFrame,
        generation: ReceiverSessionState<SSTVDecodedFrame>.Generation
    ) {
        guard session.publish(
            result: frame,
            progress: frame.progress ?? progress,
            for: generation
        ) else { return }
        do {
            decodedImage = try DecodedImageRenderer.image(from: frame.image)
            syncSessionState()
            statusText = "正在解码 \(frame.mode.displayName)：\(rowDescription(frame))"
        } catch {
            handle(error, generation: generation)
        }
    }

    private func finish(
        _ frame: SSTVDecodedFrame,
        generation: ReceiverSessionState<SSTVDecodedFrame>.Generation,
        source: ReceiverInput
    ) {
        do {
            decodedImage = try DecodedImageRenderer.image(from: frame.image)
        } catch {
            handle(error, generation: generation)
            return
        }

        if frame.isComplete {
            guard session.finish(result: frame, for: generation) else { return }
            statusText = "解码完成：\(frame.mode.displayName)。"
        } else {
            guard session.publish(
                result: frame,
                progress: frame.progress ?? progress,
                for: generation
            ), session.stop(for: generation) else { return }
            statusText = source == .audioFile
                ? "音频已结束，保留部分图像：\(rowDescription(frame))"
                : "接收已停止，保留当前图像：\(rowDescription(frame))"
        }
        receiveTask = nil
        syncSessionState()
    }

    private func handle(
        _ error: Error,
        generation: ReceiverSessionState<SSTVDecodedFrame>.Generation
    ) {
        guard session.fail(for: generation) else { return }
        // An older task must not stop the microphone owned by a newer session.
        microphone.stop()
        streamDecoder = nil
        receiveTask = nil
        syncSessionState()
        statusText = "接收失败。"
        errorMessage = error.localizedDescription
    }

    private func syncSessionState() {
        decodedFrame = session.result
        isReceiving = session.isActive
        progress = session.progress
    }

    private func rowDescription(_ frame: SSTVDecodedFrame) -> String {
        if let totalRows = frame.totalRows {
            return "\(frame.completedRows)/\(totalRows) 行"
        }
        return "\(frame.completedRows) 行"
    }
}

enum ReceiverExportError: LocalizedError {
    case noImage

    var errorDescription: String? {
        "当前没有可导出的解码图像。"
    }
}
