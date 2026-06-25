import CarRentalDomain
import AppKit
import SwiftUI

enum WorkbenchStyle {
    static let accent = Color(nsColor: .systemBlue)
    static let accentSoft = adaptiveColor(
        light: NSColor(calibratedRed: 0.88, green: 0.93, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.25, alpha: 1)
    )
    static let teal = Color(nsColor: .systemTeal)
    static let green = Color(nsColor: .systemGreen)
    static let orange = Color(nsColor: .systemOrange)
    static let red = Color(nsColor: .systemRed)
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let line = Color(nsColor: .separatorColor)
    static let quietFill = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    static let background = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let surface = Color(nsColor: .textBackgroundColor)

    static func statusColor(_ kind: PlatformEvidenceStatusKind) -> Color {
        switch kind {
        case .ready:
            return green
        case .unavailable:
            return orange
        case .loginRequired, .captchaRequired:
            return orange
        case .parseFailed:
            return red
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
}
