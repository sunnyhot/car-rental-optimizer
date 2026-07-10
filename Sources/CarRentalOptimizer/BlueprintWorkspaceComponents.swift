import SwiftUI

struct BlueprintSectionHeader: View {
    let icon: String
    let title: String
    var step: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkbenchStyle.signalTeal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                if let step {
                    Text(step.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(WorkbenchStyle.muted)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.muted)
                    .monospacedDigit()
            }
        }
    }
}

struct BlueprintMetricTile: View {
    let title: String
    let value: String
    let icon: String
    var tone: WorkbenchRailTone = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(tone.color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(WorkbenchStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tone.color.opacity(0.20), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

struct BlueprintRouteStep: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    var tone: WorkbenchRailTone = .idle
}

struct BlueprintRoutePath: View {
    let steps: [BlueprintRouteStep]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(step.tone.color.opacity(0.16))
                            Image(systemName: step.systemImage)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(step.tone.color)
                        }
                        .frame(width: 22, height: 22)

                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [step.tone.color.opacity(0.55), steps[index + 1].tone.color.opacity(0.35)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 2)
                                .frame(minHeight: 28)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                        Text(step.detail)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, index < steps.count - 1 ? 10 : 0)

                    Spacer(minLength: 8)
                }
            }
        }
        .animation(reduceMotion ? nil : WorkbenchStyle.motionStandard, value: steps)
    }
}

struct BlueprintStatePanel: View {
    let icon: String
    let title: String
    let message: String
    var tone: WorkbenchRailTone = .idle
    var isActive = false

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: tone.color.opacity(0.24), padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(tone.color)
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                StatusLightRail(isActive: isActive, tone: tone)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
