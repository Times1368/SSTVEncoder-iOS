import Foundation
import PhotosUI
import SSTVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @StateObject private var viewModel = EncoderViewModel()
    @StateObject private var playback = PlaybackController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var exportDocument: WAVDocument?
    @State private var isExporting = false
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var photoLoadGeneration: UInt64 = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    safetyNote
                    imagePanel
                    modePanel
                    encodingPanel
                    outputPanel
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("SSTV 编码器")
        }
        .onChange(of: pickerItem) { _, newItem in
            startPhotoLoad(newItem)
        }
        .onDisappear {
            photoLoadTask?.cancel()
            if viewModel.isEncoding {
                viewModel.cancelEncoding()
            }
            if playback.isPlaying {
                playback.stop()
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .wav,
            defaultFilename: viewModel.exportFilename
        ) { result in
            if case let .failure(error) = result, !isUserCancellation(error) {
                viewModel.report(error)
            }
            exportDocument = nil
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    private var safetyNote: some View {
        Label("仅生成、播放和导出音频；不会连接或控制电台发射。", systemImage: "speaker.wave.2")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var imagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("图片", systemImage: "photo")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(viewModel.sourceImage == nil ? "选择照片" : "更换照片")
                }
                .buttonStyle(.bordered)
            }

            if let image = viewModel.sourceImage {
                CropEditor(
                    image: image,
                    selection: $viewModel.cropSelection
                ) {
                    playback.stop()
                    viewModel.cropDidChange()
                }
                .aspectRatio(
                    CGFloat(viewModel.mode.width) / CGFloat(viewModel.mode.height),
                    contentMode: .fit
                )
                .frame(maxHeight: 360)

                HStack {
                    Text("拖动定位，双指缩放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("重置裁剪") {
                        playback.stop()
                        viewModel.resetCrop()
                    }
                    .font(.caption)
                }

                if let preview = viewModel.preparedPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("编码预览")
                            .font(.subheadline.weight(.semibold))
                        Image(uiImage: preview)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel("最终 SSTV 编码预览")
                        Text("此精确栅格将用于编码；完成拖动或缩放后自动更新。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "选择一张照片",
                    systemImage: "photo.badge.plus",
                    description: Text("照片只在本机处理。")
                )
                .frame(maxWidth: .infinity, minHeight: 230)
            }
        }
        .panelStyle()
    }

    private var modePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("模式", systemImage: "waveform")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                ForEach(SSTVMode.allCases, id: \.self) { mode in
                    Button {
                        playback.stop()
                        viewModel.selectMode(mode)
                    } label: {
                        VStack(spacing: 3) {
                            Text(mode.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("VIS \(mode.visCode)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.mode == mode ? .blue : .gray.opacity(0.45))
                    .accessibilityAddTraits(viewModel.mode == mode ? .isSelected : [])
                }
            }
            HStack(spacing: 18) {
                Label(viewModel.resolutionText, systemImage: "rectangle.split.3x3")
                Label(viewModel.durationText, systemImage: "timer")
                Spacer()
                Text("48 kHz · 单声道 · PCM 16-bit")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var encodingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("编码", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                if viewModel.isEncoding {
                    Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: viewModel.progress)
                .opacity(viewModel.isEncoding || viewModel.encodedSignal != nil ? 1 : 0.35)

            if viewModel.isEncoding {
                Button("取消编码", role: .cancel) {
                    viewModel.cancelEncoding()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    playback.stop()
                    viewModel.startEncoding()
                } label: {
                    Label("开始编码", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canEncode)
            }
        }
        .panelStyle()
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("输出", systemImage: "square.and.arrow.up")
                .font(.headline)

            if playback.isPlaying {
                ProgressView(value: playback.progress)
            }

            HStack(spacing: 12) {
                Button {
                    if playback.isPlaying {
                        playback.stop()
                    } else if let signal = viewModel.encodedSignal {
                        do {
                            try playback.play(signal)
                        } catch {
                            viewModel.report(error)
                        }
                    }
                } label: {
                    Label(
                        playback.isPlaying ? "停止播放" : "本机播放",
                        systemImage: playback.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canPlayOrExport)

                Button {
                    do {
                        exportDocument = try viewModel.makeExportDocument()
                        isExporting = true
                    } catch {
                        viewModel.report(error)
                    }
                } label: {
                    Label("导出 WAV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canPlayOrExport)
            }
        }
        .panelStyle()
    }

    private func startPhotoLoad(_ item: PhotosPickerItem?) {
        photoLoadTask?.cancel()
        photoLoadGeneration &+= 1
        let generation = photoLoadGeneration

        playback.stop()
        viewModel.beginImageSelection()

        guard let item else { return }
        photoLoadTask = Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoLoadingError.noData
                }
                try Task.checkCancellation()
                guard generation == photoLoadGeneration else { return }
                viewModel.loadImageData(data)
            } catch is CancellationError {
                // A newer picker selection owns the visible state.
            } catch {
                guard generation == photoLoadGeneration else { return }
                viewModel.report(error)
            }
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }
}

private enum PhotoLoadingError: LocalizedError {
    case noData

    var errorDescription: String? {
        "照片没有返回可读取的数据。"
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
