import SSTVKit
import SwiftUI

@MainActor
struct TransmitModePicker: View {
    let selectedMode: SSTVMode
    let onSelect: (SSTVMode) -> Void

    @State private var showsAllModes = false

    private static let featuredModes: [SSTVMode] = [
        .robot36Color, .martinM1, .scottieS1, .pd120,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("模式", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button("全部 ›") { showsAllModes = true }
                    .font(.subheadline.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                ForEach(Self.featuredModes, id: \.self) { mode in
                    Button { onSelect(mode) } label: {
                        VStack(spacing: 3) {
                            Text(mode.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(durationText(for: mode))
                                .font(.caption.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(selectedMode == mode ? Theme.onAccent : Theme.primaryText)
                        .background(
                            selectedMode == mode ? Theme.accent : Theme.controlBackground,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                }
            }

            Text("当前：\(selectedMode.displayName) · VIS \(selectedMode.visCode)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $showsAllModes) {
            NavigationStack {
                List {
                    ForEach(SSTVModeFamily.allCases, id: \.self) { family in
                        Section(family.displayName) {
                            ForEach(family.modes, id: \.self) { mode in
                                Button {
                                    onSelect(mode)
                                    showsAllModes = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(mode.displayName)
                                                .foregroundStyle(Theme.primaryText)
                                            if selectedMode == mode {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Theme.accent)
                                            }
                                        }
                                        Text("\(durationText(for: mode)) · \(mode.width) × \(mode.height) · VIS \(mode.visCode)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Theme.secondaryText)
                                        Text(description(for: mode.family))
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("全部 SSTV 模式")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showsAllModes = false }
                    }
                }
            }
        }
    }

    private func durationText(for mode: SSTVMode) -> String {
        let seconds = Int(mode.totalDuration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func description(for family: SSTVModeFamily) -> String {
        switch family {
        case .robot: return "常用彩色模式"
        case .pd: return "双行彩色传输"
        case .martin: return "逐行彩色传输"
        case .scottie: return "彩色图像传输"
        case .wraase: return "三通道彩色传输"
        }
    }
}
