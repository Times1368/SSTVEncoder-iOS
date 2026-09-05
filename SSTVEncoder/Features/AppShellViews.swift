import SwiftUI

@MainActor
struct LibraryShellView: View {
    let openReceive: () -> Void
    let openTransmit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.section) {
                StatusPill(title: "本机图库", value: "准备中")
                SSTVEmptyState(
                    title: "图像将在这里留存",
                    systemImage: "photo.stack",
                    message: "尚未启用自动入库。图像存储与历史记录将在下一步接入。"
                )
                Spacer(minLength: 0)
                VStack(spacing: Theme.Spacing.unit) {
                    PrimaryActionButton(title: "去接收", systemImage: AppTab.receive.systemImage, action: openReceive)
                    Button(action: openTransmit) {
                        Label("去发射", systemImage: AppTab.transmit.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle())
                }
            }
            .padding(Theme.Spacing.regular)
            .frame(maxWidth: Theme.Metrics.contentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pageBackground)
            .navigationTitle("图库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        }
    }
}

@MainActor
struct SettingsShellView: View {
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.section) {
                SSTVCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                        ColorBars().frame(width: 72, height: Theme.Spacing.unit).clipShape(Capsule())
                        Text("SSTV 收发").font(.title2.weight(.bold)).foregroundStyle(Theme.primaryText)
                        Text("图像与音频处理均在本机进行。")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
                SSTVCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.unit) {
                        Label("设置页骨架", systemImage: "slider.horizontal.3")
                            .font(.headline).foregroundStyle(Theme.primaryText)
                        Text("呼号、模式偏好、外观与存储管理将在设置步骤接入。当前不改变收发参数。")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                PrimaryActionButton(title: "关于与隐私", systemImage: "info.circle") {
                    showingAbout = true
                }
            }
            .padding(Theme.Spacing.regular)
            .frame(maxWidth: Theme.Metrics.contentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pageBackground)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        }
        .sheet(isPresented: $showingAbout) {
            AboutPrivacySheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

@MainActor
private struct AboutPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "\(marketing)（\(build)）"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.regular) {
                    SSTVCard {
                        LabeledContent("版本", value: version).monospacedDigit()
                    }
                    SSTVCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                            Label("使用说明", systemImage: "speaker.wave.2").font(.headline)
                            Text("仅生成、播放和导出音频；不会连接或控制电台发射。")
                                .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    SSTVCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                            Label("隐私说明", systemImage: "hand.raised").font(.headline)
                            Text("只有点击“启动麦克风”后才会请求并使用麦克风；原始音频不会保存或上传。")
                                .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .padding(Theme.Spacing.regular)
            }
            .background(Theme.pageBackground)
            .navigationTitle("关于与隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
