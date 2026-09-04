import CoreGraphics

struct CropSelection: Equatable {
    var zoom: CGFloat = 1
    var normalizedOffset: CGSize = .zero

    static let identity = CropSelection()
}

