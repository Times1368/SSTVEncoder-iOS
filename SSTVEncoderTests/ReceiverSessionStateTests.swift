import XCTest
@testable import SSTVEncoder

@MainActor
final class ReceiverSessionStateTests: XCTestCase {
    func testProgressiveFramesRemainActiveUntilFinished() {
        let state = ReceiverSessionState<String>()
        let generation = state.begin(input: .audioFile)

        XCTAssertTrue(state.publish(result: "row 10", progress: 0.1, for: generation))
        XCTAssertEqual(state.result, "row 10")
        XCTAssertEqual(state.progress, 0.1, accuracy: 0.000_001)
        XCTAssertTrue(state.isActive)

        XCTAssertTrue(state.finish(result: "complete", for: generation))
        XCTAssertEqual(state.result, "complete")
        XCTAssertEqual(state.progress, 1, accuracy: 0.000_001)
        XCTAssertFalse(state.isActive)
    }

    func testStartingMicrophoneRejectsLateFileResults() {
        let state = ReceiverSessionState<String>()
        let fileGeneration = state.begin(input: .audioFile)
        let microphoneGeneration = state.begin(input: .microphone)

        XCTAssertFalse(state.publish(result: "late file", progress: 0.8, for: fileGeneration))
        XCTAssertNil(state.result)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.input, .microphone)

        XCTAssertTrue(state.publish(result: "live", progress: 0.2, for: microphoneGeneration))
        XCTAssertEqual(state.result, "live")
    }

    func testProgressCannotMoveBackward() {
        let state = ReceiverSessionState<String>()
        let generation = state.begin(input: .microphone)

        XCTAssertTrue(state.publish(result: "later", progress: 0.6, for: generation))
        XCTAssertTrue(state.publish(result: "older", progress: 0.3, for: generation))

        XCTAssertEqual(state.progress, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(state.result, "older")
    }

    func testCancelClearsResultAndInvalidatesGeneration() {
        let state = ReceiverSessionState<String>()
        let generation = state.begin(input: .microphone)
        XCTAssertTrue(state.publish(result: "partial", progress: 0.4, for: generation))

        state.cancel(clearResult: true)

        XCTAssertFalse(state.publish(result: "late", progress: 0.8, for: generation))
        XCTAssertNil(state.result)
        XCTAssertNil(state.input)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.progress, 0, accuracy: 0.000_001)
    }
}
