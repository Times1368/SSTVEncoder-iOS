import CoreGraphics

/// The user-controlled portion of the transform applied to an image in the
/// crop editor. `zoom` is relative to the geometry's aspect-fill scale.
struct CropTransform: Equatable {
    let zoom: CGFloat
    let offset: CGSize
}

/// Calculates an aspect-fill transform while ensuring that the crop never
/// exposes space outside the source image.
struct CropGeometry {
    let imageSize: CGSize
    let cropSize: CGSize

    /// The base scale required to cover the crop on both axes.
    var aspectFillScale: CGFloat {
        guard imageSize.width > 0,
              imageSize.height > 0,
              cropSize.width > 0,
              cropSize.height > 0 else {
            return 1
        }

        return max(
            cropSize.width / imageSize.width,
            cropSize.height / imageSize.height
        )
    }

    /// Clamps the relative zoom to its aspect-fill minimum and the translation
    /// to the rendered image's available overhang.
    func clampedTransform(zoom requestedZoom: CGFloat, offset requestedOffset: CGSize) -> CropTransform {
        let zoom = requestedZoom.isFinite ? max(1, requestedZoom) : 1
        let renderedWidth = imageSize.width * aspectFillScale * zoom
        let renderedHeight = imageSize.height * aspectFillScale * zoom
        let horizontalLimit = max(0, (renderedWidth - cropSize.width) / 2)
        let verticalLimit = max(0, (renderedHeight - cropSize.height) / 2)

        return CropTransform(
            zoom: zoom,
            offset: CGSize(
                width: Self.clamp(requestedOffset.width, to: -horizontalLimit ... horizontalLimit),
                height: Self.clamp(requestedOffset.height, to: -verticalLimit ... verticalLimit)
            )
        )
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
