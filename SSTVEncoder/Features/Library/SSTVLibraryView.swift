import SwiftUI
import UIKit

@MainActor
struct SSTVLibraryView: View {
    @ObservedObject var store: SSTVLibraryStore
    let retransmit: (Data, String) -> Void
    @State private var filter = SSTVLibraryFilter.all
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private var selectedURLs: [URL] {
        store.records.filter { selectedIDs.contains($0.id) }.map { store.imageURL(for: $0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.unit) {
                Picker("筛选图库", selection: $filter) {
                    ForEach(SSTVLibraryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.regular)
                if store.isLoading {
                    ProgressView("正在读取图库")
                }
                if filter.apply(to: store.records).isEmpty {
                    SSTVEmptyState(title: "暂无图像", systemImage: "photo.stack",
                                   message: "保存的图像会按日期保留在这里。")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                            ForEach(SSTVLibraryDayGrouping.sections(for: filter.apply(to: store.records))) { section in
                                Text(dayTitle(section.id)).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.unit), count: 3), spacing: Theme.Spacing.unit) {
                                    ForEach(section.records) { record in
                                        if isSelecting {
                                            Button {
                                                if !selectedIDs.insert(record.id).inserted {
                                                    selectedIDs.remove(record.id)
                                                }
                                            } label: {
                                                SSTVLibraryThumbnail(store: store, record: record)
                                                    .overlay(alignment: .topLeading) {
                                                        Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                                            .foregroundStyle(Theme.onAccent)
                                                            .padding(Theme.Spacing.unit)
                                                            .background(Theme.instrument.opacity(0.7), in: Circle())
                                                    }
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityValue(selectedIDs.contains(record.id) ? "已选择" : "未选择")
                                        } else {
                                            NavigationLink {
                                                SSTVLibraryDetail(store: store, original: record, retransmit: retransmit)
                                            } label: {
                                                SSTVLibraryThumbnail(store: store, record: record)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Theme.Spacing.regular)
                    }
                    .refreshable { await store.reload() }
                }
                Spacer(minLength: 0)
            }
            .background(Theme.pageBackground)
            .navigationTitle("图库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "完成" : "选择") {
                        isSelecting.toggle()
                        selectedIDs.removeAll()
                    }
                    .disabled(store.records.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    VStack(spacing: Theme.Spacing.unit) {
                        ShareLink(items: selectedURLs) {
                            Label("分享所选 \(selectedURLs.count) 张", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(selectedURLs.isEmpty)
                        if selectedURLs.isEmpty {
                            Text("先选择要导出的图像").font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .monospacedDigit()
                    .padding(Theme.Spacing.regular).background(Theme.pageBackground)
                }
            }
            .onChange(of: filter) { _, _ in selectedIDs.removeAll() }
            .onChange(of: store.records) { _, records in
                selectedIDs.formIntersection(Set(records.map(\.id)))
                if records.isEmpty { isSelecting = false }
            }
            .task { await store.loadIfNeeded() }
            .alert("图库操作失败", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.dismissError() } })) {
                Button("好") { store.dismissError() }
            } message: { Text(store.errorMessage ?? "未知错误") }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

@MainActor
private struct SSTVLibraryThumbnail: View {
    let store: SSTVLibraryStore
    let record: SSTVLibraryRecord
    @State private var image: UIImage?

    var body: some View {
        Rectangle().fill(Theme.instrument)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    GeometryReader { proxy in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    }
                } else { Image(systemName: "photo").foregroundStyle(Theme.secondaryText) }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    Circle().fill(directionColor).frame(width: 8, height: 8)
                    Spacer(minLength: 0)
                    Text(record.modeName).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(Theme.onAccent).padding(6)
                .background(Theme.instrument.opacity(0.65))
            }
            .overlay(alignment: .topTrailing) {
                if record.isFavorite { Image(systemName: "star.fill").foregroundStyle(Theme.signalWarn).padding(6) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.unit))
            .accessibilityLabel("\(record.direction.displayName)，\(record.modeName)")
            .task(id: record.id) {
                do {
                    let data = try await store.thumbnailData(for: record.id)
                    try Task.checkCancellation()
                    image = UIImage(data: data)
                } catch { image = nil }
            }
    }

    private var directionColor: Color {
        switch record.direction {
        case .receive: return Theme.signalOK
        case .transmit: return Theme.accent
        case .unknown: return Theme.secondaryText
        }
    }
}

@MainActor
private struct SSTVLibraryDetail: View {
    @ObservedObject var store: SSTVLibraryStore
    let original: SSTVLibraryRecord
    let retransmit: (Data, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var imageData: Data?
    @State private var image: UIImage?
    @State private var confirmDelete = false
    @State private var note = ""
    @State private var busy = false
    @State private var message: String?
    private var record: SSTVLibraryRecord { store.records.first { $0.id == original.id } ?? original }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.regular) {
                if let image {
                    LibraryZoomImage(image: image).frame(height: 320).background(Theme.instrument)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
                } else if let message {
                    SSTVEmptyState(title: "无法读取原图", systemImage: "photo.badge.exclamationmark", message: message)
                        .frame(height: 320)
                } else { ProgressView("正在读取原图").frame(height: 320) }
                SSTVCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.unit) {
                        Text(record.modeName).font(.headline)
                        Text("\(record.direction.displayName) · \(record.width)×\(record.height)").monospacedDigit()
                        Text(record.date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().hour().minute())).monospacedDigit()
                        TextField("备注", text: $note, axis: .vertical)
                        Button("保存备注") { perform { try await store.updateNote(note, for: record.id) } }
                    }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.secondaryText) }
            }.padding(Theme.Spacing.regular)
        }
        .background(Theme.pageBackground)
        .navigationTitle("图像详情").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.unit) {
                HStack {
                    ShareLink(item: store.imageURL(for: record.id)) { Label("分享", systemImage: "square.and.arrow.up") }
                        .disabled(imageData == nil)
                    Spacer()
                    Button(record.isFavorite ? "取消收藏" : "收藏") {
                        perform { try await store.setFavorite(!record.isFavorite, for: record.id) }
                    }
                    Spacer()
                    Button("删除", role: .destructive) { confirmDelete = true }
                }.buttonStyle(.bordered)
                if record.direction == .transmit {
                    PrimaryActionButton(title: "用这张图再发一次", systemImage: "waveform", disabledReason: imageData == nil ? "正在读取原图" : nil) {
                        if let imageData { retransmit(imageData, record.modeID); dismiss() }
                    }
                }
            }
            .disabled(busy).padding(Theme.Spacing.regular).background(Theme.pageBackground)
        }
        .confirmationDialog("删除这张图像？原图和缩略图将永久删除，无法恢复。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除图像", role: .destructive) {
                perform { try await store.delete(ids: [record.id]); dismiss() }
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            note = record.note
            do {
                let data = try await store.imageData(for: record.id)
                guard let decoded = UIImage(data: data) else { throw SSTVLibraryError.invalidImage }
                imageData = data
                image = decoded
            } catch { message = error.localizedDescription }
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
}

private struct LibraryZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator
        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let imageView = context.coordinator.imageView
        if imageView.image !== image {
            scroll.setZoomScale(1, animated: false)
            imageView.image = image
        }
        if scroll.zoomScale == 1 { imageView.frame = scroll.bounds }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}
