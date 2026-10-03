import Foundation
import PhotosUI
import SSTVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @State private var selectedTab = AppTab.defaultTab
    @StateObject private var library = SSTVLibraryStore()
    @StateObject private var encoder = EncoderViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            ReceiveView(library: library)
                .tabItem {
                    Label(AppTab.receive.title, systemImage: AppTab.receive.systemImage)
                }
                .tag(AppTab.receive)

            EncoderView(viewModel: encoder, library: library, isActive: selectedTab == .transmit)
                .tabItem {
                    Label(AppTab.transmit.title, systemImage: AppTab.transmit.systemImage)
                }
                .tag(AppTab.transmit)

            SSTVLibraryView(store: library) { data, modeID in
                if let mode = SSTVMode(rawValue: modeID) { encoder.selectMode(mode) }
                encoder.loadImageData(data)
                selectedTab = .transmit
            }
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.systemImage)
                }
                .tag(AppTab.library)

            SettingsShellView()
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
        }
        .tint(Theme.accent)
        .toolbarBackground(Theme.pageBackground, for: .tabBar)
    }
}

@MainActor
private struct EncoderView: View {
    @ObservedObject var viewModel: EncoderViewModel
    let library: SSTVLibraryStore
    let isActive: Bool
    @StateObject private var playback = PlaybackController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var exportDocument: WAVDocument?
    @State private var isExporting = false
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var photoLoadGeneration: UInt64 = 0
    @State private var selectedOverlayID: UUID?
    @FocusState private var focusedOverlayID: UUID?
    @AppStorage("transmitCallsign") private var callsign = ""
    @AppStorage("transmitSafetySeen") private var safetySeen = false
    @State private var showsSafetyInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    imagePanel
                    if viewModel.sourceImage != nil { overlayPanel }
                    modePanel
                    actionPanel
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageBackground)
            .navigationTitle("发射")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSafetyInfo = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("发射说明")
                }
            }
        }
        .onAppear {
            showFirstSafetyInfoIfNeeded()
        }
        .onChange(of: isActive) { _, active in
            if active { showFirstSafetyInfoIfNeeded() }
        }
        .sheet(isPresented: $showsSafetyInfo) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Label("发射说明", systemImage: "speaker.wave.2")
                        .font(.title2.bold())
                    Text("仅生成、播放和导出音频；不会连接或控制电台发射。")
                    Text("播放时请先调低设备音量。要通过电台发送，请自行确认连接、频率及适用规则。")
                    Spacer()
                }
                .padding()
                .navigationTitle("发射说明")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showsSafetyInfo = false }
                    }
                }
            }
            .presentationDetents([.medium])
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

    private func showFirstSafetyInfoIfNeeded() {
        guard isActive, !safetySeen else { return }
        safetySeen = true
        showsSafetyInfo = true
    }

    private var imagePanel: some View {
        let hasImage = viewModel.sourceImage != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("图片", systemImage: "photo")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(hasImage ? "更换照片" : "选择照片")
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
                        TransmitPreview(
                            image: preview,
                            mode: viewModel.mode,
                            overlays: viewModel.textOverlays,
                            playbackProgress: playback.isPlaying ? playback.progress : nil,
                            playbackDuration: viewModel.encodedSignal?.duration ?? viewModel.mode.totalDuration,
                            selectedOverlayID: selectedOverlayID,
                            onSelect: { id in
                                selectedOverlayID = id
                                focusedOverlayID = id
                            },
                            onMove: { id, position in
                                playback.stop()
                                viewModel.moveTextOverlay(id, to: position)
                            }
                        )
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

    private var overlayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("叠字", systemImage: "textformat")
                    .font(.headline)
                Spacer()
                Button("添加文字") {
                    playback.stop()
                    let id = viewModel.addTextOverlay()
                    selectedOverlayID = id
                    focusedOverlayID = id
                }
                .buttonStyle(.bordered)
            }
            ForEach(viewModel.textOverlays) { overlay in
                HStack {
                    TextField("输入文字", text: Binding(
                        get: { viewModel.textOverlays.first(where: { $0.id == overlay.id })?.text ?? "" },
                        set: {
                            playback.stop()
                            viewModel.updateTextOverlay(overlay.id, text: $0)
                        }
                    ))
                    .textInputAutocapitalization(.characters)
                    .focused($focusedOverlayID, equals: overlay.id)
                    .onTapGesture { selectedOverlayID = overlay.id }
                    Button(role: .destructive) {
                        playback.stop()
                        viewModel.removeTextOverlay(overlay.id)
                        if selectedOverlayID == overlay.id { selectedOverlayID = nil }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除这条叠字")
                }
            }
            HStack {
                TextField("呼号", text: $callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("插入呼号") {
                    let trimmed = callsign.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    playback.stop()
                    selectedOverlayID = viewModel.addTextOverlay(trimmed)
                }
                .disabled(callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("点击文字框编辑；拖动预览中的文字位置。叠字只写入生成图像，原照片保持不变。")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .panelStyle()
    }

    private var modePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransmitModePicker(selectedMode: viewModel.mode) { mode in
                playback.stop()
                viewModel.selectMode(mode)
            }
            HStack {
                Label(viewModel.resolutionText, systemImage: "rectangle.split.3x3")
                Spacer()
                Label(viewModel.durationText, systemImage: "timer")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            Text("\(viewModel.encodedSignal == nil ? "预计" : "实际")时长 · 48 kHz · 单声道 · PCM 16-bit")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .panelStyle()
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("生成与播放", systemImage: "waveform")
                .font(.headline)

            if viewModel.isEncoding {
                ProgressView(value: viewModel.progress)
                Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Button("取消生成", role: .cancel) {
                    viewModel.cancelEncoding()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            } else if playback.isPlaying {
                ProgressView(value: playback.progress)
                Text(viewModel.playbackTimeText(progress: playback.progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                PrimaryActionButton(
                    title: "停止播放", systemImage: "stop.fill", tone: .destructive
                ) {
                    playback.stop()
                }
            } else {
                PrimaryActionButton(
                    title: viewModel.encodedSignal == nil ? "生成并播放" : "播放已生成音频",
                    systemImage: "play.fill",
                    disabledReason: primaryDisabledReason
                ) {
                    if let signal = viewModel.encodedSignal {
                        play(signal)
                    } else {
                        viewModel.startEncoding(onCompletion: play)
                    }
                }
                if viewModel.encodedSignal != nil {
                    Text("音频已生成，可再次播放或导出 WAV。")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack(spacing: 12) {
                Button {
                    playback.stop()
                    viewModel.startEncoding()
                } label: {
                    Label("仅生成", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canEncode)

                Button {
                    do {
                        exportDocument = try viewModel.makeExportDocument()
                        isExporting = true
                    } catch {
                        viewModel.report(error)
                    }
                } label: {
                    Label("导出 WAV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canPlayOrExport)
            }
            .frame(maxWidth: .infinity)

            if !viewModel.canPlayOrExport {
                Text("先完成编码后才能导出 WAV。")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .panelStyle()
    }

    private var primaryDisabledReason: String? {
        guard viewModel.encodedSignal == nil, !viewModel.canEncode else { return nil }
        return viewModel.sourceImage == nil ? "先选择一张照片。" : "图片处理失败，请重新选择。"
    }

    private func play(_ signal: PCMBuffer) {
        let image = viewModel.preparedPreview
        let mode = viewModel.mode
        do {
            try playback.play(signal) {
                guard let image else { return }
                Task {
                    do {
                        _ = try await library.save(image: image, metadata: SSTVLibraryMetadata(
                            direction: .transmit, modeID: mode.rawValue, modeName: mode.displayName
                        ))
                    } catch { library.report(error) }
                }
            }
        } catch {
            viewModel.report(error)
        }
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
