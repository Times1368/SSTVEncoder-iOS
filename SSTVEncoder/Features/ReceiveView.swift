import Foundation
import SSTVKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ReceiveView: View {
    @StateObject private var viewModel = ReceiverViewModel()
    @State private var isImportingAudio = false
    @State private var exportDocument: PNGDocument?
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    privacyNote
                    receiveModePanel
                    inputPanel
                    imagePanel
                    exportPanel
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageBackground)
            .navigationTitle("接收")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                viewModel.decodeAudioFile(url)
            } catch {
                if !isUserCancellation(error) {
                    viewModel.report(error)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .png,
            defaultFilename: viewModel.exportFilename
        ) { result in
            if case let .failure(error) = result, !isUserCancellation(error) {
                viewModel.report(error)
            }
            exportDocument = nil
        }
        .alert(
            "接收失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
        .onDisappear {
            if viewModel.isReceiving {
                viewModel.stopReceiving()
            }
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("接收完全在本机进行", systemImage: "waveform.and.mic")
                .font(.subheadline.weight(.semibold))
            Text("只有点击“启动麦克风”后才会请求并使用麦克风；原始音频不会保存或上传。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var receiveModePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("接收模式", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)

            Picker(
                "模式",
                selection: Binding(
                    get: { viewModel.selection },
                    set: { viewModel.select($0) }
                )
            ) {
                Text("自动识别 SSTV（支持中途接收）")
                    .tag(SSTVReceiveSelection.automatic)
                Text("Contrib / HF Fax · IOC 576 · 120 LPM")
                    .tag(SSTVReceiveSelection.hfFax(.ioc576_120))
                ForEach(SSTVModeFamily.allCases, id: \.self) { family in
                    Section(family.displayName) {
                        ForEach(family.modes, id: \.self) { mode in
                            Text(mode.displayName)
                                .tag(SSTVReceiveSelection.mode(mode))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isReceiving)

            if viewModel.selection == .hfFax(.ioc576_120) {
                Text("HF Fax 没有 VIS，必须手动选择；每 500 ms 解码一行灰度传真。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.selection == .automatic {
                Text("优先识别模式头；错过开头时，尝试用连续行同步识别 15 种 SSTV 模式。锁定需要数条清晰扫描行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .receivePanelStyle()
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("音频输入", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                if viewModel.isReceiving {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Button {
                    isImportingAudio = true
                } label: {
                    Label("导入音频", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isReceiving)

                Button {
                    if viewModel.isUsingMicrophone {
                        viewModel.stopReceiving()
                    } else {
                        viewModel.startMicrophone()
                    }
                } label: {
                    Label(
                        viewModel.isUsingMicrophone ? "停止接收" : "启动麦克风",
                        systemImage: viewModel.isUsingMicrophone ? "stop.fill" : "mic.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isReceiving && !viewModel.isUsingMicrophone)
            }

            if viewModel.isReceiving && !viewModel.isUsingMicrophone {
                Button("停止文件解码", role: .cancel) {
                    viewModel.stopReceiving()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLateEntry {
                Text("中途接收 · 不估算整图完成率")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.isReceiving || viewModel.decodedFrame != nil {
                ProgressView(value: viewModel.progress)
                    .opacity(viewModel.decodedFrame?.totalRows == nil ? 0.35 : 1)
            }
        }
        .receivePanelStyle()
    }

    private var imagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("解码图像", systemImage: "photo")
                    .font(.headline)
                Spacer()
                if viewModel.decodedFrame != nil {
                    Text(viewModel.rowText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let image = viewModel.decodedImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 520)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("SSTV 解码图像")

                HStack(spacing: 12) {
                    Label(viewModel.modeText, systemImage: "waveform.path.ecg")
                    Label(viewModel.detectionText, systemImage: "checkmark.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if viewModel.isLateEntry {
                    Label("已保留可接收的图像片段。缺失的开头无法恢复，原始行号未知；可导出当前 PNG。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "等待 SSTV 图像",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("导入录音或启动麦克风；即使发送已经开始，也可尝试中途锁定。")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .receivePanelStyle()
    }

    private var exportPanel: some View {
        Button {
            do {
                exportDocument = try viewModel.makeExportDocument()
                isExporting = true
            } catch {
                viewModel.report(error)
            }
        } label: {
            Label("导出解码 PNG", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canExport)
        .receivePanelStyle()
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }
}

private extension View {
    func receivePanelStyle() -> some View {
        padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
