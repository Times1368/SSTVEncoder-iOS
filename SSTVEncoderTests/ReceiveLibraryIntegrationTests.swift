import Combine
import SSTVKit
import UIKit
import XCTest
@testable import SSTVEncoder

@MainActor
final class ReceiveLibraryIntegrationTests: XCTestCase {
    func testDecodedAudioAppearsInSharedLibraryAndManualSaveDoesNotDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SSTVLibraryStore(repository: SSTVLibraryRepository(rootDirectory: root))
        await library.loadIfNeeded() // Reproduce opening the empty gallery before receiving.
        let receiver = ReceiverViewModel(library: library)
        let mode = SSTVMode.robot36Color
        let image = try RGBImage(width: mode.width, height: mode.height,
                                 pixels: Array(repeating: .green, count: mode.width * mode.height))
        let encoder = try SSTVKit.SSTVEncoder(sampleRate: 48_000)
        let pcm = try await encoder.encode(image, mode: mode)
        let url = root.appendingPathComponent("input.wav")
        try WAVEncoder.encode(pcm).write(to: url)
        let saved = expectation(description: "Decoded image is published to the shared gallery")
        let subscription = library.$records.dropFirst().filter { !$0.isEmpty }.prefix(1).sink { _ in saved.fulfill() }
        defer { subscription.cancel(); receiver.stopReceiving() }
        receiver.decodeAudioFile(url)
        await fulfillment(of: [saved], timeout: 90)
        XCTAssertEqual(library.records.count, 1)
        XCTAssertEqual(library.records.first?.modeID, mode.rawValue)
        XCTAssertEqual(library.records.first?.direction, .receive)
        await receiver.saveToLibrary()
        XCTAssertEqual(library.records.count, 1)
        let reloaded = try await SSTVLibraryRepository(rootDirectory: root).load()
        XCTAssertEqual(reloaded.count, 1)
        let record = try XCTUnwrap(reloaded.first)
        let thumbnail = try await library.thumbnailData(for: record.id)
        XCTAssertNotNil(UIImage(data: thumbnail))
    }

    func testTwoIdenticalReceivedFramesAreDistinctAndLateEntryIsMarkedPartial() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SSTVLibraryStore(repository: SSTVLibraryRepository(rootDirectory: root))
        let image = try RGBImage(width: 2, height: 2, pixels: [.red, .green, .blue, .white])
        let frame = SSTVDecodedFrame(image: image, mode: .sstv(.robot72Color), detectionSource: .lateEntry,
                                     completedRows: 2, totalRows: 240, isComplete: false, frequencyOffsetHz: 0)
        let first = try await store.saveReceivedFrame(frame)
        let second = try await store.saveReceivedFrame(frame)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.records.count, 2)
        XCTAssertTrue(first.note.contains("原始行号未知"))
        XCTAssertEqual(first.direction, .receive)
    }
}
