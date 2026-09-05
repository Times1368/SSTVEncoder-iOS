import SSTVKit
import XCTest
@testable import SSTVEncoder

@MainActor
final class ReceiverAdapterTests: XCTestCase {
    func testAudioFileLoaderReadsExportedPCMAsMonoFloat() throws {
        let source = try PCMBuffer(
            sampleRate: 12_000,
            samples: [0, 0.25, -0.5, 0.75, -1]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try WAVEncoder.encode(source).write(to: url, options: .atomic)

        let loaded = try AudioFileLoader.load(from: url)

        XCTAssertEqual(loaded.sampleRate, source.sampleRate)
        XCTAssertEqual(loaded.samples.count, source.samples.count)
        for (actual, expected) in zip(loaded.samples, source.samples) {
            XCTAssertEqual(actual, expected, accuracy: 1.0 / 32_767)
        }
    }

    func testReceiveMenuExposesAutomaticHFFaxAndEveryVISMode() {
        XCTAssertTrue(ReceiverViewModel.selections.contains(.automatic))
        XCTAssertTrue(
            ReceiverViewModel.selections.contains(.hfFax(.ioc576_120))
        )
        for mode in SSTVMode.allCases {
            XCTAssertTrue(
                ReceiverViewModel.selections.contains(.mode(mode)),
                mode.displayName
            )
        }
        XCTAssertEqual(ReceiverViewModel.selections.count, SSTVMode.allCases.count + 2)
    }

    func testAutomaticReceiverExplainsLineTimingWithoutStartingTheMicrophone() {
        let model = ReceiverViewModel()
        XCTAssertTrue(model.detectionText.contains("行同步"))
        XCTAssertFalse(model.isReceiving)
        XCTAssertFalse(model.isUsingMicrophone)
        XCTAssertFalse(model.isLateEntry)
    }
}
