import SwiftUI
import UIKit

struct CropEditor: View {
    let image: UIImage
    @Binding var selection: CropSelection
    let onCommit: () -> Void

    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let geometry = CropGeometry(imageSize: image.size, cropSize: size)
            let baseOffset = CGSize(
                width: selection.normalizedOffset.width * size.width,
                height: selection.normalizedOffset.height * size.height
            )
            let requestedOffset = CGSize(
                width: baseOffset.width + dragTranslation.width,
                height: baseOffset.height + dragTranslation.height
            )
            let transform = geometry.clampedTransform(
                zoom: selection.zoom * magnification,
                offset: requestedOffset
            )

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .scaleEffect(transform.zoom)
                .offset(transform.offset)
                .clipped()
                .contentShape(Rectangle())
                .overlay(alignment: .center) {
                    CropGrid()
                }
                .gesture(cropGesture(size: size, geometry: geometry))
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        }
        .accessibilityLabel("SSTV 图片裁剪预览")
        .accessibilityHint("拖动调整位置，双指缩放图片")
    }

    private func cropGesture(size: CGSize, geometry: CropGeometry) -> some Gesture {
        DragGesture()
            .simultaneously(with: MagnificationGesture())
            .updating($dragTranslation) { value, state, _ in
                state = value.first?.translation ?? .zero
            }
            .updating($magnification) { value, state, _ in
                state = value.second ?? 1
            }
            .onEnded { value in
                let translation = value.first?.translation ?? .zero
                let magnification = value.second ?? 1
                let current = CGSize(
                    width: selection.normalizedOffset.width * size.width,
                    height: selection.normalizedOffset.height * size.height
                )
                commit(
                    geometry.clampedTransform(
                        zoom: selection.zoom * magnification,
                        offset: CGSize(
                            width: current.width + translation.width,
                            height: current.height + translation.height
                        )
                    ),
                    in: size
                )
            }
    }

    private func commit(_ transform: CropTransform, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        selection = CropSelection(
            zoom: transform.zoom,
            normalizedOffset: CGSize(
                width: transform.offset.width / size.width,
                height: transform.offset.height / size.height
            )
        )
        onCommit()
    }
}

private struct CropGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    let x = proxy.size.width * fraction
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    let y = proxy.size.height * fraction
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.28), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}
