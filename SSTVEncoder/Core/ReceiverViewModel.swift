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
    @Published private(set) var libraryMessage: String?
    @Published private(set) var isSavingToLibrary = false
    @Published private(set) var isWaitingForNextFrame = false
    private let library: SSTVLibraryStore?
    private var savedFrame: SSTVDecodedFrame?
    private var activeLibrarySaves = 0
    private var archiveSerial = 0
    private var libraryMessageTask: Task<Void, Never>?

    init(library: SSTVLibraryStore? = nil) {
        self.library = library
    }

    func saveToLibrary() async {
        guard let library, let frame = decodedFrame, frame.completedRows > 0,
              !isSavingToLibrary else { return }
        if savedFrame == frame {
            libraryMessage = "已保存到图库"
            return
        }
        activeLibrarySaves += 1
        isSavingToLibrary = true
        defer { finishLibrarySave() }
        do {
            _ = try await library.saveReceivedFrame(frame)
            if decodedFrame == frame {
                savedFrame = frame
                libraryMessage = "已保存到图库"
            }
        } catch {
            library.report(error)
            if decodedFrame == frame { libraryMessage = "入库失败：\(error.localizedDescription)，可重试或导出 PNG。" }
        }
    }

    private func finishLibrarySave() {
        activeLibrarySaves -= 1
        isSavingToLibrary = activeLibrarySaves > 0
    }

    private let session = ReceiverSessionState<SSTVDecodedFrame>()
    private let microphone = MicrophoneReceiver()
    private var receiveTask: Task<Void, Never>?
    private var streamDecoder: ContinuousStreamDecoder?

    static let selections: [SSTVReceiveSelection] = [
        .automatic,
        .hfFax(.ioc576_120),
    ] + SSTVMode.allCases.map { .mode($0) }

    var canExport: Bool { decodedImage != nil }
    var isUsingMicrophone: Bool { session.input == .microphone }
    var isLateEntry: Bool { decodedFrame?.detectionSource == .lateEntry }
    var modeText: String { decodedFrame?.mode.displayName ?? selection.displayName }
    var rowText: String {
        guard let frame = decodedFrame else { return "尚无图像" }
        if frame.detectionSource == .lateEntry { return "片段 \(frame.completedRows) 行" }
        if let totalRows = frame.totalRows {
            return "\(frame.completedRows) / \(totalRows) 行"
        }
        return "\(frame.completedRows) 行"
    }
    var detectionText: String {
        guard let frame = decodedFrame else {
            return selection == .automatic ? "等待模式头或行同步" : "手动模式"
        }
        switch frame.detectionSource {
        case .vis: return "VIS 自动识别"
        case .manual: return "手动选择"
        case .timing: return "扫描时序推断"
        case .lateEntry: return "中途锁定 · 无 VIS"
        }
    }
    var exportFilename: String {
        let name = modeText
            .replacingOccurrences(of: " / ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "SSTV-\(isLateEntry ? "Partial" : "Decoded")-\(name).png"
    }

    func select(_ newSelection: SSTVReceiveSelection) {
        guard newSelection != selection else { return }
        stopReceiving(clearResult: true)
        selection = newSelection
        statusText = newSelection == .automatic
            ? "等待模式头或连续行同步，可在发送中途开始接收。"
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
                    ? "正在搜索模式头或连续行同步…"
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
                let decoder = try ContinuousStreamDecoder(
                    sampleRate: capture.sampleRate,
                    selection: selectedMode
                )
                streamDecoder = decoder
                statusText = selectedMode == .automatic
                    ? "正在监听，识别模式头或尝试中途锁定…"
                    : "正在接收 \(selectedMode.displayName)…"

                var continuity = MicrophoneContinuityChecker()
                for try await chunk in capture.chunks {
                    try Task.checkCancellation()
                    try continuity.accept(chunk)
                    if let frame = try await decoder.append(chunk.samples) {
                        if frame.isComplete {
                            completeMicrophoneFrame(
                                frame,
                                count: decoder.completedFrameCount,
                                generation: generation
                            )
                        } else {
                            publish(frame, generation: generation)
                        }
                    }
                }
                try Task.checkCancellation()
                do {
                    let finalFrame = try await decoder.finish()
                    microphone.stop()
                    streamDecoder = nil
                    finish(finalFrame, generation: generation, source: .microphone)
                } catch let error as SSTVDecodeError
                    where decoder.completedFrameCount > 0
                        && (error == .headerNotFound || error == .noImageData) {
                    microphone.stop()
                    streamDecoder = nil
                    guard session.stop(for: generation) else { return }
                    isWaitingForNextFrame = false
                    syncSessionState()
                    receiveTask = nil
                    statusText = "麦克风输入已结束，保留最近收到的图像。"
                }
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
            archiveSerial &+= 1
            libraryMessageTask?.cancel()
            libraryMessageTask = nil
            savedFrame = nil
            libraryMessage = nil
            decodedImage = nil
            statusText = "等待导入音频或启动麦克风。"
        } else if hadResult {
            statusText = "接收已停止，保留当前图像。"
        } else {
            statusText = "接收已停止。"
        }
        isWaitingForNextFrame = false
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
            isWaitingForNextFrame = false
            syncSessionState()
            statusText = frame.detectionSource == .lateEntry
                ? "中途接收 \(frame.mode.displayName)：\(rowDescription(frame))"
                : "正在解码 \(frame.mode.displayName)：\(rowDescription(frame))"
        } catch {
            handle(error, generation: generation)
        }
    }

    private func completeMicrophoneFrame(
        _ frame: SSTVDecodedFrame,
        count: Int,
        generation: ReceiverSessionState<SSTVDecodedFrame>.Generation
    ) {
        publish(frame, generation: generation)
        guard session.completeFrameAndContinue(result: frame, for: generation) else { return }
        isWaitingForNextFrame = true
        syncSessionState()
        statusText = "第 \(count) 张图像已接收，继续监听下一帧。"
        archive(frame, transientMessage: true)
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
            statusText = frame.detectionSource == .lateEntry
                ? "当前画布已填满，保留中途接收片段：\(frame.mode.displayName)。"
                : "解码完成：\(frame.mode.displayName)。"
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
        isWaitingForNextFrame = false
        syncSessionState()
        archive(frame, transientMessage: false)
    }

    private func archive(_ frame: SSTVDecodedFrame, transientMessage: Bool) {
        guard let library, frame.completedRows > 0 else { return }
        archiveSerial &+= 1
        let serial = archiveSerial
        activeLibrarySaves += 1
        isSavingToLibrary = true
        Task { [weak self] in
            defer { self?.finishLibrarySave() }
            do {
                _ = try await library.saveReceivedFrame(frame)
                guard let self, self.archiveSerial == serial else { return }
                if self.decodedFrame == frame { self.savedFrame = frame }
                self.showLibraryMessage("已保存到图库", transient: transientMessage)
            } catch {
                library.report(error)
                guard let self, self.archiveSerial == serial else { return }
                self.showLibraryMessage(
                    "入库失败：\(error.localizedDescription)，可重试或导出 PNG。",
                    transient: false
                )
            }
        }
    }

    private func showLibraryMessage(_ message: String, transient: Bool) {
        libraryMessageTask?.cancel()
        libraryMessage = message
        guard transient else { return }
        libraryMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.libraryMessage = nil
        }
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
        isWaitingForNextFrame = false
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
        if frame.detectionSource == .lateEntry {
            return "已解码 \(frame.completedRows) 行，原始行号未知"
        }
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
