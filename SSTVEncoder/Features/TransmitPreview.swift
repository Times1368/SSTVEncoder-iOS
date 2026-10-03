import SSTVKit
import SwiftUI

@MainActor
struct TransmitPreview: View {
    let image: UIImage
    let mode: SSTVMode
    let overlays: [TransmitTextOverlay]
    let playbackProgress: Double?
    let playbackDuration: Double
    let selectedOverlayID: UUID?
    let onSelect: (UUID) -> Void
    let onMove: (UUID, CGPoint) -> Void

    var body: some View {
        GeometryReader { container in
            let scale = min(
                container.size.width / CGFloat(mode.width),
                container.size.height / CGFloat(mode.height)
            )
            let imageSize = CGSize(
                width: CGFloat(mode.width) * scale,
                height: CGFloat(mode.height) * scale
            )
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize.width, height: imageSize.height)
                .overlay(alignment: .topLeading) {
                    if let playbackProgress {
                        let fraction = TransmitPlaybackProgress.pictureFraction(
                            playbackProgress: playbackProgress,
                            totalDuration: playbackDuration
                        )
                        if fraction > 0 {
                            Rectangle()
                                .fill(Theme.onAccent)
                                .frame(height: Theme.Metrics.scanLineHeight)
                                .shadow(color: .black, radius: 2)
                                .offset(y: max(0, imageSize.height - Theme.Metrics.scanLineHeight) * fraction)
                                .animation(.linear(duration: 0.1), value: playbackProgress)
                        }
                    }
                }
                .overlay {
                    ForEach(overlays) { overlay in
                        TransmitOverlayHandle(
                            overlay: overlay,
                            canvasSize: imageSize,
                            isSelected: selectedOverlayID == overlay.id,
                            onSelect: { onSelect(overlay.id) },
                            onMove: { onMove(overlay.id, $0) }
                        )
                    }
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .position(x: container.size.width / 2, y: container.size.height / 2)
        }
        .frame(height: 280)
        .accessibilityLabel("最终 SSTV 编码预览")
    }
}

@MainActor
private struct TransmitOverlayHandle: View {
    let overlay: TransmitTextOverlay
    let canvasSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void

    @GestureState private var drag = CGSize.zero

    var body: some View {
        let handleWidth = min(canvasSize.width, max(80, CGFloat(overlay.text.count) * 12))
        Rectangle()
            .fill(.clear)
            .frame(width: handleWidth, height: 42)
            .contentShape(Rectangle())
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.white, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
            }
            .position(
                x: overlay.position.x * canvasSize.width + drag.width,
                y: overlay.position.y * canvasSize.height + drag.height
            )
            .onTapGesture(perform: onSelect)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                        onMove(CGPoint(
                            x: overlay.position.x + value.translation.width / canvasSize.width,
                            y: overlay.position.y + value.translation.height / canvasSize.height
                        ))
                    }
            )
            .accessibilityLabel("移动叠字：\(overlay.text)")
    }
}
