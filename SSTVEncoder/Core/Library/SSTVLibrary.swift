import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

enum SSTVLibraryDirection: String, Codable, CaseIterable, Sendable {
    case receive = "rx"
    case transmit = "tx"
    /// Used only when a damaged index is rebuilt from image files.
    case unknown

    var displayName: String {
        switch self {
        case .receive: return "接收"
        case .transmit: return "发射"
        case .unknown: return "方向未知"
        }
    }
}

struct SSTVLibraryRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let direction: SSTVLibraryDirection
    let modeID: String
    let modeName: String
    let width: Int
    let height: Int
    var note: String
    var isFavorite: Bool
}

struct SSTVLibraryMetadata: Equatable, Sendable {
    let direction: SSTVLibraryDirection
    let modeID: String
    let modeName: String
    var note: String

    init(
        direction: SSTVLibraryDirection,
        modeID: String,
        modeName: String,
        note: String = ""
    ) {
        self.direction = direction
        self.modeID = modeID
        self.modeName = modeName
        self.note = note
    }
}

enum SSTVLibraryError: LocalizedError, Equatable {
    case invalidImage
    case recordNotFound
    case imageNotFound
    case thumbnailUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图像不是可读取的 PNG 文件。"
        case .recordNotFound:
            return "图库中找不到这条记录。"
        case .imageNotFound:
            return "图库原图已丢失，索引将在下次载入时修复。"
        case .thumbnailUnavailable:
            return "无法生成图库缩略图。"
        }
    }
}

/// Serializes every index and image mutation so two completed frames cannot overwrite each other.
actor SSTVLibraryRepository {
    nonisolated let rootDirectory: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedRecords: [SSTVLibraryRecord]?

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func applicationRootDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documents.appendingPathComponent("SSTVLibrary", isDirectory: true)
    }

    nonisolated var indexURL: URL {
        rootDirectory.appendingPathComponent("index.json", isDirectory: false)
    }

    nonisolated var imagesDirectory: URL {
        rootDirectory.appendingPathComponent("images", isDirectory: true)
    }

    nonisolated var thumbnailsDirectory: URL {
        rootDirectory.appendingPathComponent("thumbs", isDirectory: true)
    }

    nonisolated func imageURL(for id: UUID) -> URL {
        imagesDirectory.appendingPathComponent("\(id.uuidString.lowercased()).png", isDirectory: false)
    }

    nonisolated func thumbnailURL(for id: UUID) -> URL {
        thumbnailsDirectory.appendingPathComponent("\(id.uuidString.lowercased()).jpg", isDirectory: false)
    }

    func load() throws -> [SSTVLibraryRecord] {
        if let cachedRecords {
            return cachedRecords
        }

        try prepareDirectories()
        let records: [SSTVLibraryRecord]
        if fileManager.fileExists(atPath: indexURL.path) {
            // Read failures (for example locked protected data) are not corrupt JSON.
            let data = try Data(contentsOf: indexURL)
            let decoded: [SSTVLibraryRecord]
            do {
                decoded = try decoder.decode([SSTVLibraryRecord].self, from: data)
            } catch {
                try quarantineCorruptIndex()
                let recovered = try rebuildIndexFromImages()
                cachedRecords = sorted(recovered)
                return cachedRecords ?? []
            }
            records = try reconcile(decoded)
        } else {
            records = try rebuildIndexFromImages()
        }

        cachedRecords = sorted(records)
        return cachedRecords ?? []
    }

    func reload() throws -> [SSTVLibraryRecord] {
        cachedRecords = nil
        return try load()
    }

    @discardableResult
    func save(
        pngData: Data,
        metadata: SSTVLibraryMetadata,
        date: Date = Date()
    ) throws -> SSTVLibraryRecord {
        var records = try load()
        let dimensions = try SSTVLibraryImageCodec.pngDimensions(from: pngData)
        let thumbnailData = try SSTVLibraryImageCodec.jpegThumbnail(from: pngData)
        let id = UUID()
        let record = SSTVLibraryRecord(
            id: id,
            date: date,
            direction: metadata.direction,
            modeID: metadata.modeID,
            modeName: metadata.modeName,
            width: dimensions.width,
            height: dimensions.height,
            note: metadata.note,
            isFavorite: false
        )
        let imageURL = imageURL(for: id)
        let thumbnailURL = thumbnailURL(for: id)

        do {
            try pngData.write(to: imageURL, options: .atomic)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
            records.append(record)
            records = sorted(records)
            try writeIndex(records)
            cachedRecords = records
            return record
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw error
        }
    }

    @discardableResult
    func setFavorite(_ isFavorite: Bool, for id: UUID) throws -> [SSTVLibraryRecord] {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SSTVLibraryError.recordNotFound
        }
        records[index].isFavorite = isFavorite
        try writeIndex(records)
        cachedRecords = records
        return records
    }

    @discardableResult
    func updateNote(_ note: String, for id: UUID) throws -> [SSTVLibraryRecord] {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SSTVLibraryError.recordNotFound
        }
        records[index].note = note
        try writeIndex(records)
        cachedRecords = records
        return records
    }

    @discardableResult
    func delete(ids: Set<UUID>) throws -> [SSTVLibraryRecord] {
        guard !ids.isEmpty else { return try load() }
        let records = try load()
        let remaining = records.filter { !ids.contains($0.id) }
        guard remaining.count != records.count else {
            throw SSTVLibraryError.recordNotFound
        }

        // Commit the authoritative index first. Leftover orphan files are safe to clean,
        // while deleting files before this write could leave valid records without images.
        try writeIndex(remaining)
        cachedRecords = remaining
        for id in ids {
            try? fileManager.removeItem(at: imageURL(for: id))
            try? fileManager.removeItem(at: thumbnailURL(for: id))
        }
        return remaining
    }

    func imageData(for id: UUID) throws -> Data {
        let url = imageURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SSTVLibraryError.imageNotFound
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func thumbnailData(for id: UUID) throws -> Data {
        let url = thumbnailURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        let thumbnail = try SSTVLibraryImageCodec.jpegThumbnail(from: imageData(for: id))
        try thumbnail.write(to: url, options: .atomic)
        return thumbnail
    }

    func storageByteCount() throws -> Int64 {
        try prepareDirectories()
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    private func reconcile(_ decoded: [SSTVLibraryRecord]) throws -> [SSTVLibraryRecord] {
        var seen = Set<UUID>()
        var records: [SSTVLibraryRecord] = []

        for record in sorted(decoded) where seen.insert(record.id).inserted {
            let imageURL = imageURL(for: record.id)
            guard fileManager.fileExists(atPath: imageURL.path) else { continue }
            records.append(record)
            ensureThumbnail(for: record.id)
        }

        if records != sorted(decoded) {
            try writeIndex(records)
        }
        // Preserve orphan images: an interrupted save may have written its PNG
        // before the index was committed. They remain available for recovery.
        return records
    }

    private func rebuildIndexFromImages() throws -> [SSTVLibraryRecord] {
        let urls = try fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        var records: [SSTVLibraryRecord] = []

        for url in urls where url.pathExtension.lowercased() == "png" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let dimensions = try? SSTVLibraryImageCodec.pngDimensions(from: data) else {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let date = values?.contentModificationDate ?? values?.creationDate ?? Date()
            records.append(SSTVLibraryRecord(
                id: id,
                date: date,
                direction: .unknown,
                modeID: "unknown",
                modeName: "模式未知",
                width: dimensions.width,
                height: dimensions.height,
                note: "索引恢复：收发方向、模式与收藏状态未知。",
                isFavorite: false
            ))
            ensureThumbnail(for: id)
        }

        records = sorted(records)
        try writeIndex(records)
        return records
    }

    private func ensureThumbnail(for id: UUID) {
        let destination = thumbnailURL(for: id)
        guard !fileManager.fileExists(atPath: destination.path),
              let imageData = try? Data(contentsOf: imageURL(for: id), options: .mappedIfSafe),
              let thumbnail = try? SSTVLibraryImageCodec.jpegThumbnail(from: imageData) else {
            return
        }
        try? thumbnail.write(to: destination, options: .atomic)
    }

    private func quarantineCorruptIndex() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let destination = rootDirectory.appendingPathComponent(
            "index.corrupt-\(timestamp)-\(suffix).json",
            isDirectory: false
        )
        try fileManager.copyItem(at: indexURL, to: destination)
    }

    private func writeIndex(_ records: [SSTVLibraryRecord]) throws {
        let data = try encoder.encode(sorted(records))
        try data.write(to: indexURL, options: .atomic)
    }

    private func sorted(_ records: [SSTVLibraryRecord]) -> [SSTVLibraryRecord] {
        records.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

@MainActor
final class SSTVLibraryStore: ObservableObject {
    @Published private(set) var records: [SSTVLibraryRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let repository: SSTVLibraryRepository
    private var hasLoaded = false

    init(
        repository: SSTVLibraryRepository = SSTVLibraryRepository(
            rootDirectory: SSTVLibraryRepository.applicationRootDirectory()
        )
    ) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await repository.reload()
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(
        image: UIImage,
        metadata: SSTVLibraryMetadata,
        date: Date = Date()
    ) async throws -> SSTVLibraryRecord {
        guard let pngData = image.pngData() else {
            throw SSTVLibraryError.invalidImage
        }
        let record = try await repository.save(pngData: pngData, metadata: metadata, date: date)
        records = try await repository.load()
        hasLoaded = true
        return record
    }

    func setFavorite(_ isFavorite: Bool, for id: UUID) async throws {
        records = try await repository.setFavorite(isFavorite, for: id)
    }

    func updateNote(_ note: String, for id: UUID) async throws {
        records = try await repository.updateNote(note, for: id)
    }

    func delete(ids: Set<UUID>) async throws {
        records = try await repository.delete(ids: ids)
    }

    func imageData(for id: UUID) async throws -> Data {
        try await repository.imageData(for: id)
    }

    func thumbnailData(for id: UUID) async throws -> Data {
        try await repository.thumbnailData(for: id)
    }

    func imageURL(for id: UUID) -> URL {
        repository.imageURL(for: id)
    }

    func dismissError() {
        errorMessage = nil
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private enum SSTVLibraryImageCodec {
    struct Dimensions {
        let width: Int
        let height: Int
    }

    static func pngDimensions(from data: Data) throws -> Dimensions {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              UTType(sourceType as String)?.conforms(to: .png) == true,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = number(properties[kCGImagePropertyPixelWidth]),
              let height = number(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0 else {
            throw SSTVLibraryError.invalidImage
        }
        return Dimensions(width: width, height: height)
    }

    static func jpegThumbnail(from pngData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else {
            throw SSTVLibraryError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SSTVLibraryError.thumbnailUnavailable
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw SSTVLibraryError.thumbnailUnavailable
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw SSTVLibraryError.thumbnailUnavailable
        }
        return output as Data
    }

    private static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }
}
