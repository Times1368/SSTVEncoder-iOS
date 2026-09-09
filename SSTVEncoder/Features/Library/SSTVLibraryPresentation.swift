import Foundation

enum SSTVLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case receive
    case transmit
    case favorite

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "全部"
        case .receive: return "接收"
        case .transmit: return "发射"
        case .favorite: return "收藏"
        }
    }

    func apply(to records: [SSTVLibraryRecord]) -> [SSTVLibraryRecord] {
        switch self {
        case .all:
            return records
        case .receive:
            return records.filter { $0.direction == .receive }
        case .transmit:
            return records.filter { $0.direction == .transmit }
        case .favorite:
            return records.filter(\.isFavorite)
        }
    }
}

struct SSTVLibraryDaySection: Identifiable, Equatable {
    let id: Date
    let records: [SSTVLibraryRecord]
}

enum SSTVLibraryDayGrouping {
    static func sections(
        for records: [SSTVLibraryRecord],
        calendar: Calendar = .current
    ) -> [SSTVLibraryDaySection] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            .map { day, records in
                SSTVLibraryDaySection(
                    id: day,
                    records: records.sorted {
                        if $0.date != $1.date { return $0.date > $1.date }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                )
            }
            .sorted { $0.id > $1.id }
    }
}
