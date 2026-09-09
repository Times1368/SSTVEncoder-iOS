import ImageIO
import UIKit
import XCTest
@testable import SSTVEncoder

@MainActor
final class SSTVLibraryRepositoryTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUpWithError() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSTVLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
    }

    func testTwoSavesCreateDistinctImagesAndSurviveReload() async throws {
        let repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        let first = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .systemBlue),
            metadata: metadata(direction: .receive, modeID: "robot36", modeName: "Robot 36 Color"),
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let second = try await repository.save(
            pngData: makePNG(width: 640, height: 496, color: .systemOrange),
            metadata: metadata(direction: .transmit, modeID: "pd120", modeName: "PD 120"),
            date: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.imageURL(for: first.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.imageURL(for: second.id).path))

        let reloaded = try await SSTVLibraryRepository(rootDirectory: rootDirectory).load()
        XCTAssertEqual(reloaded.map(\.id), [second.id, first.id])
        XCTAssertEqual(reloaded.map(\.direction), [.transmit, .receive])
        XCTAssertEqual(reloaded.map(\.modeName), ["PD 120", "Robot 36 Color"])
    }

    func testIndexContainsTheRequiredStableFields() async throws {
        let repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        _ = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .systemGreen),
            metadata: SSTVLibraryMetadata(
                direction: .receive,
                modeID: "martinM1",
                modeName: "Martin M1",
                note: "测试备注"
            ),
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try Data(contentsOf: repository.indexURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let record = try XCTUnwrap(json.first)
        XCTAssertEqual(
            Set(record.keys),
            Set(["id", "date", "direction", "modeID", "modeName", "width", "height", "note", "isFavorite"])
        )
        XCTAssertEqual(record["direction"] as? String, "rx")
        XCTAssertEqual(record["width"] as? Int, 320)
        XCTAssertEqual(record["height"] as? Int, 256)
        XCTAssertEqual(record["isFavorite"] as? Bool, false)
    }

    func testThumbnailUsesJPEGAndLimitsItsLongestEdgeTo320Pixels() async throws {
        let repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        let record = try await repository.save(
            pngData: makePNG(width: 800, height: 616, color: .systemPurple),
            metadata: metadata(direction: .transmit, modeID: "pd290", modeName: "PD 290")
        )

        let thumbnail = try await repository.thumbnailData(for: record.id)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, "public.jpeg")
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(max(width, height), 320)
        XCTAssertLessThanOrEqual(min(width, height), 320)
    }

    func testCorruptIndexIsQuarantinedAndImagesAreRecoveredWithoutInventingMetadata() async throws {
        var repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        _ = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .red),
            metadata: metadata(direction: .receive, modeID: "robot72", modeName: "Robot 72 Color")
        )
        _ = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .blue),
            metadata: metadata(direction: .transmit, modeID: "scottieS1", modeName: "Scottie S1")
        )
        try Data("{not-json".utf8).write(to: repository.indexURL, options: .atomic)

        repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        let recovered = try await repository.load()

        XCTAssertEqual(recovered.count, 2)
        XCTAssertTrue(recovered.allSatisfy { $0.direction == .unknown })
        XCTAssertTrue(recovered.allSatisfy { $0.modeID == "unknown" })
        XCTAssertTrue(recovered.allSatisfy { $0.modeName == "模式未知" })
        XCTAssertTrue(recovered.allSatisfy { $0.note.contains("索引恢复") })

        let directoryNames = try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path)
        XCTAssertTrue(directoryNames.contains { $0.hasPrefix("index.corrupt-") && $0.hasSuffix(".json") })
        let rebuiltData = try Data(contentsOf: repository.indexURL)
        XCTAssertNoThrow(try indexDecoder().decode([SSTVLibraryRecord].self, from: rebuiltData))
    }

    func testFavoriteAndNoteUpdatesArePersistedAtomically() async throws {
        var repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        let record = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .cyan),
            metadata: metadata(direction: .receive, modeID: "martinM2", modeName: "Martin M2")
        )

        _ = try await repository.setFavorite(true, for: record.id)
        _ = try await repository.updateNote("CQ 测试", for: record.id)

        repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        let reloaded = try await repository.load()
        let updated = try XCTUnwrap(reloaded.first)
        XCTAssertTrue(updated.isFavorite)
        XCTAssertEqual(updated.note, "CQ 测试")
    }

    func testDeletingOneRecordDoesNotRemoveAnother() async throws {
        let repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        let first = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .yellow),
            metadata: metadata(direction: .receive, modeID: "robot36", modeName: "Robot 36 Color")
        )
        let second = try await repository.save(
            pngData: makePNG(width: 320, height: 256, color: .magenta),
            metadata: metadata(direction: .receive, modeID: "robot72", modeName: "Robot 72 Color")
        )

        let remaining = try await repository.delete(ids: [first.id])

        XCTAssertEqual(remaining.map(\.id), [second.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.imageURL(for: first.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.thumbnailURL(for: first.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.imageURL(for: second.id).path))
    }

    func testInvalidImageDataDoesNotCreateARecord() async throws {
        let repository = SSTVLibraryRepository(rootDirectory: rootDirectory)

        do {
            _ = try await repository.save(
                pngData: Data("not-an-image".utf8),
                metadata: metadata(direction: .receive, modeID: "robot36", modeName: "Robot 36 Color")
            )
            XCTFail("无效图片不应写入图库")
        } catch {
            XCTAssertEqual(error as? SSTVLibraryError, .invalidImage)
        }

        let records = try await repository.load()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: repository.imagesDirectory.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: repository.thumbnailsDirectory.path).isEmpty)
    }

    func testReloadPreservesUnindexedImageAfterInterruptedSave() async throws {
        let repository = SSTVLibraryRepository(rootDirectory: rootDirectory)
        _ = try await repository.load()
        let orphan = repository.imageURL(for: UUID())
        try makePNG(width: 320, height: 256, color: .blue).write(to: orphan)
        _ = try await repository.reload()
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path), "不能自动删除中断保存留下的原图")
    }

    private func metadata(
        direction: SSTVLibraryDirection,
        modeID: String,
        modeName: String
    ) -> SSTVLibraryMetadata {
        SSTVLibraryMetadata(
            direction: direction,
            modeID: modeID,
            modeName: modeName,
            note: ""
        )
    }

    private func makePNG(width: Int, height: Int, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func indexDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
