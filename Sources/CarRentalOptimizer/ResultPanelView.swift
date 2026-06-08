import CarRentalDomain
import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        WorkbenchPanel(
            title: "候选方案",
            subtitle: panelSubtitle,
            trailing: AnyView(
                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 360, alignment: .trailing)
            )
        ) {
            Group {
                if viewModel.isSearching {
                    LoadingResultsView()
                } else if viewModel.results.isEmpty {
                    EmptyResultsView(statuses: viewModel.platformStatuses)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                                ResultRowView(
                                    rank: index + 1,
                                    recommendation: result,
                                    isSelected: viewModel.selectedId == result.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectResult(result.id)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }

    private var panelSubtitle: String {
        if viewModel.results.isEmpty {
            return "等待真实报价"
        }
        return "\(viewModel.results.count) 个真实候选，同车型取优后按总成本升序"
    }
}

private struct LoadingResultsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            SurfaceBox(fill: WorkbenchStyle.surface, padding: 18) {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在比较")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text("平台车源、门店距离和到店路线正在合并计算。")
                        .font(.callout)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(width: 320)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct EmptyResultsView: View {
    let statuses: [PlatformEvidenceStatus]

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            EmptyStateBlock(
                icon: "doc.text.magnifyingglass",
                title: "等待结果",
                message: "没有可排序的真实车源时，这里不会显示推测价格。"
            )
            .frame(maxHeight: 210)

            SurfaceBox(fill: WorkbenchStyle.surface, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                        PlatformSummaryRow(status: status)

                        if index < statuses.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }
            .frame(maxWidth: 460)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlatformSummaryRow: View {
    let status: PlatformEvidenceStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: WorkbenchStyle.statusIcon(status.kind))
                .font(.callout.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.statusColor(status.kind))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.platform.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                Text(status.message)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ResultRowView: View {
    let rank: Int
    let recommendation: Recommendation
    let isSelected: Bool

    var body: some View {
        SurfaceBox(
            fill: isSelected ? WorkbenchStyle.accentSoft.opacity(0.9) : WorkbenchStyle.surface,
            stroke: isSelected ? WorkbenchStyle.accent.opacity(0.45) : WorkbenchStyle.line,
            padding: 0
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    rankBadge

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(recommendation.listing.store.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(WorkbenchStyle.ink)
                                .lineLimit(1)
                            StatusPill(
                                text: recommendation.listing.platform.label,
                                color: recommendation.listing.platform == .ehi ? WorkbenchStyle.teal : WorkbenchStyle.accent,
                                systemImage: "building.2.fill"
                            )
                            if let comparisonLabel {
                                StatusPill(
                                    text: comparisonLabel,
                                    color: WorkbenchStyle.green,
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                        }

                        Text("\(recommendation.listing.vehicleName) · \(recommendation.match.label)")
                            .font(.callout)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .lineLimit(1)

                        HStack(spacing: 14) {
                            Label("\(recommendation.listing.store.distanceKm, specifier: "%.1f") km", systemImage: "location.fill")
                            Label(recommendation.listing.store.hours, systemImage: "clock.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("总成本")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.muted)
                        Text(formatMoney(recommendation.bestTotal))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(WorkbenchStyle.ink)
                            .monospacedDigit()
                        Text(recommendation.bestRouteMode.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.accent)
                    }
                }

                HStack(spacing: 8) {
                    InlineMetric(title: "租车小计", value: formatMoney(recommendation.rentalTotal))
                    InlineMetric(title: "打车到店", value: formatMoney(recommendation.taxiRoute.cost))
                    InlineMetric(title: "公交到店", value: formatMoney(recommendation.transitRoute.cost))
                    InlineMetric(title: "完整度", value: "\(Int((recommendation.listing.dataCompleteness * 100).rounded()))%")
                }

                Text(rankingReason)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
            }
            .padding(14)
        }
    }

    private var rankingReason: String {
        "排序依据：总成本 \(formatMoney(recommendation.bestTotal)) = 租车 \(formatMoney(recommendation.rentalTotal)) + 到店 \(formatMoney(bestRouteCost)) · \(recommendation.match.label)"
    }

    private var bestRouteCost: Double {
        recommendation.bestRouteMode == .taxi ? recommendation.taxiRoute.cost : recommendation.transitRoute.cost
    }

    private var comparisonLabel: String? {
        let platforms = PlatformId.allCases.filter { platform in
            recommendation.comparisonQuotes.contains { $0.listing.platform == platform }
        }
        guard platforms.count > 1 else { return nil }
        return platforms.map(\.label).joined(separator: "/") + "取优"
    }

    private var rankBadge: some View {
        VStack(spacing: 0) {
            Text("\(rank)")
                .font(.headline.weight(.bold))
                .foregroundStyle(isSelected ? .white : WorkbenchStyle.accent)
                .monospacedDigit()
        }
        .frame(width: 40, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? WorkbenchStyle.accent : WorkbenchStyle.accentSoft)
        )
    }
}

private struct InlineMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(WorkbenchStyle.muted)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.035))
        )
    }
}
