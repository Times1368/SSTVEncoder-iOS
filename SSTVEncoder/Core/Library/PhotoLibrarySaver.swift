import Photos
import UIKit

enum PhotoLibrarySaveError: LocalizedError {
    case invalidImage
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取要存入系统相册的图像。"
        case .accessDenied:
            return "没有添加照片的权限，请在系统设置中允许访问照片。"
        }
    }
}

@MainActor
enum PhotoLibrarySaver {
    static func save(imageData: Data) async throws {
        guard let image = UIImage(data: imageData) else {
            throw PhotoLibrarySaveError.invalidImage
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.accessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
