import SwiftUI

/// UI-only design tokens. All color values live in the Any/Dark asset catalog.
enum Theme {
    enum ColorToken: String, CaseIterable {
        case accent = "Accent"
        case signalOK = "SignalOK"
        case signalWarn = "SignalWarn"
        case signalBad = "SignalBad"
        case instrument = "Instrument"
        case pageBackground = "PageBackground"
        case cardBackground = "CardBackground"
        case controlBackground = "ControlBackground"
        case primaryText = "PrimaryText"
        case secondaryText = "SecondaryText"
        case hairline = "Hairline"
        case onAccent = "OnAccent"
        case barsWhite = "BarsWhite"
        case barsYellow = "BarsYellow"
        case barsCyan = "BarsCyan"
        case barsGreen = "BarsGreen"
        case barsMagenta = "BarsMagenta"
        case barsRed = "BarsRed"

        var color: Color { Color(rawValue) }
    }

    static let accent = ColorToken.accent.color
    static let signalOK = ColorToken.signalOK.color
    static let signalWarn = ColorToken.signalWarn.color
    static let signalBad = ColorToken.signalBad.color
    static let instrument = ColorToken.instrument.color
    static let pageBackground = ColorToken.pageBackground.color
    static let cardBackground = ColorToken.cardBackground.color
    static let controlBackground = ColorToken.controlBackground.color
    static let primaryText = ColorToken.primaryText.color
    static let secondaryText = ColorToken.secondaryText.color
    static let hairline = ColorToken.hairline.color
    static let onAccent = ColorToken.onAccent.color

    static let barColors = [
        ColorToken.barsWhite.color, ColorToken.barsYellow.color,
        ColorToken.barsCyan.color, ColorToken.barsGreen.color,
        ColorToken.barsMagenta.color, ColorToken.barsRed.color,
    ]
    static let barGradient = LinearGradient(colors: barColors, startPoint: .leading, endPoint: .trailing)

    enum Spacing {
        static let unit: CGFloat = 8
        static let regular: CGFloat = 16
        static let section: CGFloat = 24
        static let spacious: CGFloat = 32
    }

    enum Metrics {
        static let cardRadius: CGFloat = 16
        static let primaryButtonHeight: CGFloat = 52
        static let secondaryButtonHeight: CGFloat = 44
        static let statusHeight: CGFloat = 44
        static let waterfallHeight: CGFloat = 132
        static let thinBorder: CGFloat = 1
        static let selectedBorder: CGFloat = 2
        static let scanLineHeight: CGFloat = 2
        static let progressHeight: CGFloat = 4
        static let contentMaxWidth: CGFloat = 760
    }

    /// Clamp presentation only; never feeds a value back into SSTVKit.
    static func displayProgress(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
