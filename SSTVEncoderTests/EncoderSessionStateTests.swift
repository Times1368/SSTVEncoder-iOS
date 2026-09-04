import XCTest
@testable import SSTVEncoder

@MainActor
final class EncoderSessionStateTests: XCTestCase {
    func testEveryInputChangeInvalidatesAnExistingResult() {
        let changes: [EncodingInputChange] = [.image, .mode, .crop]

        for change in changes {
            let state = EncoderSessionState<String>()
            let generation = state.beginEncoding()

            XCTAssertTrue(state.publish(result: "ready", for: generation))
            XCTAssertEqual(state.result, "ready")
            XCTAssertEqual(state.progress, 1, accuracy: 0.000_001)

            state.invalidate(for: change)

            XCTAssertNil(state.result, "\(change) must invalidate encoded audio")
            XCTAssertFalse(state.isEncoding)
            XCTAssertEqual(state.progress, 0, accuracy: 0.000_001)
        }
    }

    func testInputChangeWhileEncodingRejectsTheLateResult() {
        let state = EncoderSessionState<String>()
        let staleGeneration = state.beginEncoding()

        state.invalidate(for: .crop)

        XCTAssertFalse(state.publish(result: "stale", for: staleGeneration))
        XCTAssertNil(state.result)
        XCTAssertFalse(state.isEncoding)
    }

    func testNewEncodingSupersedesThePreviousGeneration() {
        let state = EncoderSessionState<String>()
        let oldGeneration = state.beginEncoding()
        let currentGeneration = state.beginEncoding()

        XCTAssertFalse(state.publish(result: "old", for: oldGeneration))
        XCTAssertNil(state.result)
        XCTAssertTrue(state.isEncoding)

        XCTAssertTrue(state.publish(result: "current", for: currentGeneration))
        XCTAssertEqual(state.result, "current")
        XCTAssertFalse(state.isEncoding)
        XCTAssertEqual(state.progress, 1, accuracy: 0.000_001)
    }

    func testCancellationMakesItsGenerationStale() {
        let state = EncoderSessionState<String>()
        let cancelledGeneration = state.beginEncoding()

        state.cancelEncoding()

        XCTAssertFalse(state.publish(result: "late", for: cancelledGeneration))
        XCTAssertNil(state.result)
        XCTAssertFalse(state.isEncoding)
        XCTAssertEqual(state.progress, 0, accuracy: 0.000_001)
    }

    func testProgressIsMonotonicForTheCurrentGeneration() {
        let state = EncoderSessionState<String>()
        let generation = state.beginEncoding()

        XCTAssertTrue(state.updateProgress(0.6, for: generation))
        XCTAssertTrue(state.updateProgress(0.2, for: generation))

        XCTAssertEqual(state.progress, 0.6, accuracy: 0.000_001)
    }

    func testProgressFromAStaleGenerationIsIgnored() {
        let state = EncoderSessionState<String>()
        let staleGeneration = state.beginEncoding()
        let currentGeneration = state.beginEncoding()

        XCTAssertFalse(state.updateProgress(0.9, for: staleGeneration))
        XCTAssertEqual(state.progress, 0, accuracy: 0.000_001)

        XCTAssertTrue(state.updateProgress(0.25, for: currentGeneration))
        XCTAssertEqual(state.progress, 0.25, accuracy: 0.000_001)
    }
}
