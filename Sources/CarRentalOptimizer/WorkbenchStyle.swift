import CarRentalDomain
import AppKit
import SwiftUI

enum WorkbenchStyle {
    static let commandBlue = adaptiveColor(
        light: NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.78, alpha: 1),
        dark: NSColor(calibratedRed: 0.32, green: 0.58, blue: 1.00, alpha: 1)
    )
    static let signalTeal = adaptiveColor(
        light: NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.56, alpha: 1),
        dark: NSColor(calibratedRed: 0.30, green: 0.86, blue: 0.90, alpha: 1)
    )
    static let routeGreen = Color(nsColor: .systemGreen)
    static let amberAlert = Color(nsColor: .systemOrange)
    static let criticalRed = Color(nsColor: .systemRed)
    static let consoleBase = adaptiveColor(
        light: NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1),
        dark: NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.075, alpha: 1)
    )
    static let panelSurface = adaptiveColor(
        light: NSColor(calibratedRed: 0.985, green: 0.99, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.085, green: 0.10, blue: 0.13, alpha: 1)
    )
    static let elevatedSurface = adaptiveColor(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1)
    )
    static let hairline = adaptiveColor(
        light: NSColor(calibratedWhite: 0.62, alpha: 0.24),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )
    static let cardShadow = adaptiveColor(
        light: NSColor(calibratedWhite: 0.18, alpha: 0.10),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.38)
    )
    static let glowLine = adaptiveColor(
        light: NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.0, alpha: 0.32),
        dark: NSColor(calibratedRed: 0.28, green: 0.78, blue: 1.0, alpha: 0.50)
    )

    static let motionFast = Animation.easeOut(duration: 0.16)
    static let motionStandard = Animation.easeOut(duration: 0.24)
    static let motionSlow = Animation.easeInOut(duration: 0.34)

    static let accent = commandBlue
    static let accentSoft = adaptiveColor(
        light: NSColor(calibratedRed: 0.88, green: 0.93, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.25, alpha: 1)
    )
    static let teal = signalTeal
    static let green = routeGreen
    static let orange = amberAlert
    static let red = criticalRed
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let line = hairline
    static let quietFill = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    static let background = consoleBase
    static let panel = panelSurface
    static let surface = elevatedSurface

    static func statusColor(_ kind: PlatformEvidenceStatusKind) -> Color {
        switch kind {
        case .ready:
            return routeGreen
        case .unavailable:
            return amberAlert
        case .loginRequired, .captchaRequired:
            return amberAlert
        case .parseFailed:
            return criticalRed
        case .waitingForEvidence:
            return muted
        }
    }

    static func statusIcon(_ kind: PlatformEvidenceStatusKind) -> String {
        switch kind {
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "calendar.badge.exclamationmark"
        case .loginRequired:
            return "person.crop.circle.badge.exclamationmark"
        case .captchaRequired:
            return "shield.lefthalf.filled"
        case .parseFailed:
            return "exclamationmark.triangle.fill"
        case .waitingForEvidence:
            return "clock.fill"
        }
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}

enum WorkbenchRailTone {
    case idle
    case active
    case success
    case warning
    case critical

    var color: Color {
        switch self {
        case .idle:
            return WorkbenchStyle.glowLine
        case .active:
            return WorkbenchStyle.commandBlue
        case .success:
            return WorkbenchStyle.routeGreen
        case .warning:
            return WorkbenchStyle.amberAlert
        case .critical:
            return WorkbenchStyle.criticalRed
        }
    }
}

struct StatusLightRail: View {
    let isActive: Bool
    var tone: WorkbenchRailTone = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tone.color.opacity(0.18))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tone.color.opacity(0.10),
                                tone.color.opacity(0.75),
                                tone.color.opacity(0.18),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: isActive && !reduceMotion ? max(84, proxy.size.width * 0.36) : proxy.size.width)
                    .offset(x: isActive && !reduceMotion ? (phase ? proxy.size.width : -proxy.size.width * 0.38) : 0)
            }
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            guard isActive && !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                phase = true
            }
        }
        .onChange(of: isActive) { _, active in
            phase = false
            guard active && !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                phase = true
            }
        }
    }
}

struct WorkbenchBackground: View {
    var body: some View {
        ZStack {
            WorkbenchStyle.consoleBase
            LinearGradient(
                colors: [
                    WorkbenchStyle.commandBlue.opacity(0.08),
                    Color.clear,
                    WorkbenchStyle.signalTeal.opacity(0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct WorkbenchCard<Content: View>: View {
    var fill: Color = WorkbenchStyle.elevatedSurface
    var stroke: Color = WorkbenchStyle.hairline
    var isHighlighted = false
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isHighlighted ? WorkbenchStyle.commandBlue.opacity(0.48) : stroke, lineWidth: isHighlighted ? 1.35 : 1)
                    )
                    .shadow(color: WorkbenchStyle.cardShadow.opacity(isHighlighted ? 0.78 : 0.46), radius: isHighlighted ? 14 : 8, x: 0, y: isHighlighted ? 7 : 3)
            )
    }
}

struct TaskStatusTile: View {
    let title: String
    let value: String
    let icon: String
    var tone: WorkbenchRailTone = .idle

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: tone.color.opacity(0.22), padding: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tone.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                    Text(value)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

struct ActionStatusRow: View {
    let icon: String
    let title: String
    let message: String
    var tone: WorkbenchRailTone = .idle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
    }
}

struct WorkbenchSheetShell<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    var tone: WorkbenchRailTone = .active
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tone.color)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                StatusLightRail(isActive: false, tone: tone)
            }
            .background(WorkbenchStyle.panelSurface)

            content
        }
        .background(WorkbenchStyle.panelSurface)
    }
}

private struct CommandCenterTransitionModifier: ViewModifier {
    let isEnabled: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transition(
                reduceMotion || !isEnabled
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity
                    )
            )
            .animation(
                reduceMotion || !isEnabled
                    ? WorkbenchStyle.motionFast
                    : WorkbenchStyle.motionStandard.delay(Double(index) * 0.035),
                value: isEnabled
            )
    }
}

struct WorkbenchPanel<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let trailing {
                    trailing
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle()
                .fill(WorkbenchStyle.line)
                .frame(height: 1)

            content
        }
        .background(WorkbenchStyle.panel)
    }
}

struct SurfaceBox<Content: View>: View {
    var fill: Color = WorkbenchStyle.surface
    var stroke: Color = WorkbenchStyle.line
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    var color: Color = WorkbenchStyle.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(WorkbenchStyle.muted)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(WorkbenchStyle.quietFill)
        )
    }
}

struct EmptyStateBlock: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(WorkbenchStyle.muted)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WorkbenchStyle.quietFill)
                )
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(WorkbenchStyle.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension View {
    func subtleDividerOverlay() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkbenchStyle.line)
                .frame(height: 1)
        }
    }

    func commandCenterTransition(isEnabled: Bool = true, index: Int = 0) -> some View {
        modifier(CommandCenterTransitionModifier(isEnabled: isEnabled, index: index))
    }
}
