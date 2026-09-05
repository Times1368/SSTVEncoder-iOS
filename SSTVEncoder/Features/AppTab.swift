enum AppTab: String, CaseIterable {
    case receive
    case transmit
    case library
    case settings

    static let defaultTab: Self = .receive

    var title: String {
        switch self {
        case .receive: return "接收"
        case .transmit: return "发射"
        case .library: return "图库"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .receive: return "antenna.radiowaves.left.and.right"
        case .transmit: return "waveform.path"
        case .library: return "square.grid.3x3.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
