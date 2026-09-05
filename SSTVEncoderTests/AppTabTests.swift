import XCTest
@testable import SSTVEncoder

final class AppTabTests: XCTestCase {
    func testReceiveIsTheFirstAndDefaultTab() {
        XCTAssertEqual(AppTab.defaultTab, .receive)
        XCTAssertEqual(AppTab.allCases, [.receive, .transmit, .library, .settings])
    }

    func testAllTabTitlesAreTheApprovedChineseLabels() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["接收", "发射", "图库", "设置"])
    }

    func testEveryTabHasAStableDistinctIdentityAndSymbol() {
        XCTAssertEqual(Set(AppTab.allCases.map(\.rawValue)).count, 4)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
