import SSTVKit
import XCTest
@testable import SSTVEncoder

final class TransmitPlaybackProgressTests: XCTestCase {
    func testHeaderIsExcludedAndPictureProgressReachesTheEnd() {
        let duration = SSTVMode.robot36Color.totalDuration
        let headerFraction = SSTVHeader.duration / duration

        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: headerFraction / 2, totalDuration: duration
        ), 0)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: headerFraction, totalDuration: duration
        ), 0, accuracy: 0.000_001)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: (headerFraction + 1) / 2, totalDuration: duration
        ), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: 1, totalDuration: duration
        ), 1)
    }

    func testInvalidPlaybackValuesCannotMoveTheScanlineOutsideTheImage() {
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: -.infinity, totalDuration: 37
        ), 0)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: .nan, totalDuration: 37
        ), 0)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: -1, totalDuration: 37
        ), 0)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: 2, totalDuration: 37
        ), 1)
        XCTAssertEqual(TransmitPlaybackProgress.pictureFraction(
            playbackProgress: 1, totalDuration: SSTVHeader.duration
        ), 0)
    }
}
