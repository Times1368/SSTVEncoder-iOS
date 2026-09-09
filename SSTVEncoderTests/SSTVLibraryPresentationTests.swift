import XCTest
@testable import SSTVEncoder

final class SSTVLibraryPresentationTests: XCTestCase {
    func testFiltersMatchDirectionAndFavoriteWithoutHidingRecoveredItemsFromAll() {
        let received = record(id: 1, direction: .receive, isFavorite: false)
        let transmitted = record(id: 2, direction: .transmit, isFavorite: true)
        let recovered = record(id: 3, direction: .unknown, isFavorite: false)
        let records = [received, transmitted, recovered]

        XCTAssertEqual(SSTVLibraryFilter.all.apply(to: records).map(\.id), records.map(\.id))
        XCTAssertEqual(SSTVLibraryFilter.receive.apply(to: records).map(\.id), [received.id])
        XCTAssertEqual(SSTVLibraryFilter.transmit.apply(to: records).map(\.id), [transmitted.id])
        XCTAssertEqual(SSTVLibraryFilter.favorite.apply(to: records).map(\.id), [transmitted.id])
    }

    func testDayGroupingIsNewestFirstAndPreservesNewestRecordOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = Date(timeIntervalSince1970: 1_700_006_400)
        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne)!
        let oldest = record(id: 1, date: dayOne.addingTimeInterval(10))
        let newest = record(id: 2, date: dayTwo.addingTimeInterval(30))
        let middle = record(id: 3, date: dayTwo.addingTimeInterval(20))

        let sections = SSTVLibraryDayGrouping.sections(
            for: [oldest, middle, newest],
            calendar: calendar
        )

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].records.map(\.id), [newest.id, middle.id])
        XCTAssertEqual(sections[1].records.map(\.id), [oldest.id])
    }

    func testApprovedFilterLabelsAreSimplifiedChinese() {
        XCTAssertEqual(SSTVLibraryFilter.allCases.map(\.title), ["全部", "接收", "发射", "收藏"])
    }

    private func record(
        id: UInt8,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        direction: SSTVLibraryDirection = .receive,
        isFavorite: Bool = false
    ) -> SSTVLibraryRecord {
        SSTVLibraryRecord(
            id: UUID(uuid: (id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            date: date,
            direction: direction,
            modeID: "robot36",
            modeName: "Robot 36 Color",
            width: 320,
            height: 256,
            note: "",
            isFavorite: isFavorite
        )
    }
}
