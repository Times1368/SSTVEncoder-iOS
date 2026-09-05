import SwiftUI

struct SSTVCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Theme.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.Metrics.thinBorder)
            }
    }
}

enum ActionTone: Equatable {
    case accent
    case destructive

    var color: Color { self == .destructive ? Theme.signalBad : Theme.accent }
}

struct PrimaryActionStyle: ButtonStyle {
    var tone: ActionTone = .accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.primaryButtonHeight)
            .foregroundStyle(Theme.onAccent)
            .background(tone.color.opacity(isEnabled ? 1 : 0.45), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Disabled actions always carry a visible explanation, not only a gray color.
struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var tone: ActionTone = .accent
    var disabledReason: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.unit) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(PrimaryActionStyle(tone: tone))
            .disabled(disabledReason != nil)

            if let disabledReason {
                Text(disabledReason)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, Theme.Spacing.regular)
            .frame(minWidth: Theme.Metrics.secondaryButtonHeight, minHeight: Theme.Metrics.secondaryButtonHeight)
            .foregroundStyle(Theme.primaryText.opacity(isEnabled ? 1 : 0.5))
            .background(Theme.controlBackground, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: Theme.Metrics.thinBorder) }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct StatusPill: View {
    let title: String
    var color: Color = Theme.secondaryText
    var value: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.unit) {
            Circle().fill(color).frame(width: Theme.Spacing.unit, height: Theme.Spacing.unit)
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: Theme.Spacing.unit)
            if let value {
                Text(value).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .monospacedDigit()
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, Theme.Spacing.regular)
        .frame(height: Theme.Metrics.statusHeight)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: Theme.Metrics.thinBorder)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InstrumentCanvas<Content: View>: View {
    private let aspectRatio: CGFloat
    private let content: Content

    init(aspectRatio: CGFloat = 4.0 / 3.0, @ViewBuilder content: () -> Content) {
        self.aspectRatio = aspectRatio
        self.content = content()
    }

    var body: some View {
        Rectangle().fill(Theme.instrument)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.Metrics.thinBorder)
            }
    }
}

struct ColorBars: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Theme.barColors.enumerated()), id: \.offset) { item in
                item.element.frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SSTVProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(Theme.barGradient)
                    .frame(width: geometry.size.width * CGFloat(Theme.displayProgress(progress)))
            }
        }
        .frame(height: Theme.Metrics.progressHeight)
        .accessibilityLabel("进度")
        .accessibilityValue("\(Int(Theme.displayProgress(progress) * 100))%")
    }
}

struct ScanLineOverlay: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(Theme.onAccent)
                .frame(height: Theme.Metrics.scanLineHeight)
                .offset(y: max(0, geometry.size.height - Theme.Metrics.scanLineHeight) * CGFloat(Theme.displayProgress(progress)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ModeChip: View {
    let title: String
    let duration: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.unit) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(duration).font(.caption).foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            .foregroundStyle(Theme.primaryText)
            .padding(Theme.Spacing.regular)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                        .strokeBorder(Theme.barGradient, lineWidth: Theme.Metrics.selectedBorder)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                        .strokeBorder(Theme.hairline, lineWidth: Theme.Metrics.thinBorder)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "已选中，\(duration)" : duration)
    }
}

struct SSTVEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage).foregroundStyle(Theme.primaryText)
        } description: {
            Text(message).foregroundStyle(Theme.secondaryText)
        }
    }
}
