import CarRentalDomain
import Foundation
import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @State private var pendingMonitorRecommendation: Recommendation?

    var body: some View {
        WorkbenchPanel(title: "推荐明细", subtitle: "成本拆解和路线") {
            Group {
                if let recommendation = viewModel.selected {
                    RecommendationDetailView(
                        recommendation: recommendation,
                        originLabel: viewModel.request.originLabel,
                        vehicleInsight: viewModel.selectedVehicleInsight,
                        isLoadingVehicleInsight: viewModel.isLoadingSelectedVehicleInsight
                    ) {
                        pendingMonitorRecommendation = recommendation
                    }
                } else {
                    EmptyStateBlock(
                        icon: "receipt",
                        title: "等待选择",
                        message: "读取到官方车源后，这里会显示费用拆分和路线估算。"
                    )
                }
            }
        }
        .sheet(item: $pendingMonitorRecommendation) { recommendation in
            CreateMonitorSheet(
                recommendation: recommendation,
                request: viewModel.request,
                onSaveFromRecommendation: { frequency, rule, notifications in
                    try await monitorViewModel.createMonitor(
                        from: recommendation,
                        request: viewModel.request,
                        frequency: frequency,
                        alertRule: rule,
                        systemNotificationsEnabled: notifications
                    )
                },
                onSaveManual: { _, _, _, _, _, _ in }
            )
        }
    }
}

private struct RecommendationDetailView: View {
    let recommendation: Recommendation
    let originLabel: String
    let vehicleInsight: VehicleInsight?
    let isLoadingVehicleInsight: Bool
    let onMonitor: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DecisionReceiptHeader(recommendation: recommendation)

                HStack(spacing: 8) {
                    BlueprintMetricTile(title: "租车小计", value: formatMoney(recommendation.rentalTotal), icon: "car.fill", tone: .active)
                    BlueprintMetricTile(title: "到店成本", value: formatMoney(bestRouteCost), icon: recommendation.bestRouteMode == .taxi ? "car.side" : "bus.fill", tone: .success)
                }

                SurfaceBox {
                    VStack(alignment: .leading, spacing: 10) {
                        DetailTitleRow(
                            icon: "building.2.fill",
                            title: recommendation.listing.store.name,
                            badge: recommendation.match.displayLabel
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            FactLine(icon: "mappin.circle.fill", text: "\(recommendation.listing.store.city) · \(recommendation.listing.store.address)")
                            FactLine(icon: "location.fill", text: String(format: "距离约 %.1f km", recommendation.listing.store.distanceKm))
                            FactLine(icon: "clock.fill", text: recommendation.listing.store.hours)
                            FactLine(icon: "car.fill", text: recommendation.listing.displayNameWithClass)
                        }
                    }
                }

                VehicleInsightSection(
                    insight: vehicleInsight ?? VehicleInsightLocalInferencer.localInsight(for: recommendation.listing),
                    isLoading: isLoadingVehicleInsight
                )

                if recommendation.comparisonQuotes.count > 1 {
                    PlatformQuoteComparisonView(recommendation: recommendation)
                }

                SurfaceBox {
                    VStack(alignment: .leading, spacing: 9) {
                        DetailTitleRow(icon: "list.bullet.clipboard", title: "费用拆分")

                        VStack(spacing: 0) {
                            CostLineView(label: "平台返回租车价", value: recommendation.listing.basePrice)
                            CostLineView(label: "平台服务费", value: recommendation.listing.platformFees)
                            CostLineView(label: "保险/保障", value: recommendation.listing.insuranceFees)
                            CostLineView(label: "异店还车费", value: recommendation.listing.oneWayFee)

                            Divider()
                                .padding(.vertical, 5)

                            CostLineView(label: "租车小计", value: recommendation.rentalTotal, bold: true)

                            QuoteCredibilityDetail(credibility: QuoteCredibility.make(for: recommendation))
                                .padding(.top, 6)
                        }
                    }
                }

                SurfaceBox {
                    VStack(alignment: .leading, spacing: 10) {
                        BlueprintSectionHeader(icon: "point.3.connected.trianglepath.dotted", title: "决策路径", step: "ROUTE")
                        BlueprintRoutePath(steps: decisionRouteSteps)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    DetailTitleRow(icon: "map.fill", title: "到店路线")

                    HStack(spacing: 10) {
                        RouteDecisionCard(
                            title: "打车",
                            total: recommendation.taxiTotal,
                            route: recommendation.taxiRoute,
                            isBest: recommendation.bestRouteMode == .taxi
                        )
                        RouteDecisionCard(
                            title: "公共交通",
                            total: recommendation.transitTotal,
                            route: recommendation.transitRoute,
                            isBest: recommendation.bestRouteMode == .transit
                        )
                    }
                }

                if !recommendation.warnings.isEmpty {
                    WarningBox(warnings: recommendation.warnings)
                }

                ReceiptActionBar(
                    sourceURL: URL(string: recommendation.listing.sourceUrl),
                    onMonitor: onMonitor
                )
            }
            .padding(16)
        }
    }

    private var bestRouteCost: Double {
        recommendation.bestRouteMode == .taxi ? recommendation.taxiRoute.cost : recommendation.transitRoute.cost
    }

    private var decisionRouteSteps: [BlueprintRouteStep] {
        let route = recommendation.bestRouteMode == .taxi
            ? recommendation.taxiRoute
            : recommendation.transitRoute
        return [
            BlueprintRouteStep(
                id: "origin",
                title: originLabel,
                detail: "当前行程起点",
                systemImage: "mappin.circle.fill",
                tone: .active
            ),
            BlueprintRouteStep(
                id: "transport",
                title: recommendation.bestRouteMode.label,
                detail: "\(Int(route.durationMinutes.rounded())) 分钟 · \(String(format: "%.1f km", route.distanceKm)) · \(formatMoney(route.cost))",
                systemImage: recommendation.bestRouteMode == .taxi ? "car.side.fill" : "bus.fill",
                tone: .success
            ),
            BlueprintRouteStep(
                id: "store",
                title: recommendation.listing.store.name,
                detail: recommendation.listing.store.address,
                systemImage: "building.2.fill",
                tone: .success
            ),
        ]
    }
}

private struct VehicleInsightSection: View {
    let insight: VehicleInsight
    let isLoading: Bool

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 11) {
                DetailTitleRow(
                    icon: insight.origin == .network ? "network" : "sparkle.magnifyingglass",
                    title: "车型介绍",
                    badge: isLoading ? "更新中" : insight.origin.label
                )

                Text(insight.longSummary)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(insight.sourceName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.commandBlue)
                    if let fetchedAt = insight.fetchedAt {
                        Text(vehicleInsightFreshness(fetchedAt))
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                    }
                    if let sourceURL = insight.sourceURL, let url = URL(string: sourceURL), insight.origin == .network {
                        Link("来源", destination: url)
                            .font(.caption2.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }

                VehicleInsightFactGrid(title: "基础参数", facts: insight.formattedBasicSpecs)

                VStack(alignment: .leading, spacing: 7) {
                    VehicleInsightFactGrid(title: "配置参考", facts: insight.formattedConfigurationFacts)
                    Text("下单前以平台确认页为准")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                }
            }
        }
    }
}

private struct VehicleInsightFactGrid: View {
    let title: String
    let facts: [VehicleInsightFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                        Text(fact.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                            .lineLimit(1)
                        if let scopeLabel = fact.scopeLabel {
                            Text(scopeLabel)
                                .font(.caption2)
                                .foregroundStyle(WorkbenchStyle.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchStyle.quietFill))
                }
            }
        }
    }
}

private func vehicleInsightFreshness(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.string(from: date)
}

private struct PlatformQuoteComparisonView: View {
    let recommendation: Recommendation

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 9) {
                DetailTitleRow(icon: "arrow.triangle.2.circlepath", title: "平台价格对比")

                VStack(spacing: 0) {
                    ForEach(Array(recommendation.comparisonQuotes.enumerated()), id: \.element.id) { index, quote in
                        PlatformQuoteRowView(
                            quote: quote,
                            isWinner: quote.id == recommendation.id
                        )

                        if index < recommendation.comparisonQuotes.count - 1 {
                            Divider()
                                .padding(.vertical, 7)
                        }
                    }
                }
            }
        }
    }
}

private struct PlatformQuoteRowView: View {
    let quote: Recommendation
    let isWinner: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusPill(
                text: quote.listing.platform.label,
                color: quote.listing.platform == .ehi ? WorkbenchStyle.teal : WorkbenchStyle.accent,
                systemImage: "building.2.fill"
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(quote.listing.store.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                        .lineLimit(1)
                    if isWinner {
                        Text("当前取优")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.green)
                    }
                }
                Text(quote.listing.vehicleName)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
                Text(QuoteCredibility.make(for: quote).title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("租车 \(formatMoney(quote.rentalTotal))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                    .monospacedDigit()
                Text("含到店 \(formatMoney(quote.bestTotal)) · \(quote.bestRouteMode.label)")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .monospacedDigit()
            }
        }
    }
}

private struct QuoteCredibilityDetail: View {
    let credibility: QuoteCredibility

    var body: some View {
        Label(credibility.message, systemImage: credibility.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch credibility.level {
        case .complete:
            return WorkbenchStyle.green
        case .reviewRecommended:
            return WorkbenchStyle.orange
        case .blocked:
            return WorkbenchStyle.red
        }
    }
}

private struct DecisionReceiptHeader: View {
    let recommendation: Recommendation

    var body: some View {
        WorkbenchCard(
            fill: WorkbenchStyle.decisionBlue.opacity(0.11),
            stroke: WorkbenchStyle.decisionBlue.opacity(0.34),
            isHighlighted: true,
            padding: 16
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    StatusPill(
                        text: recommendation.listing.platform.label,
                        color: recommendation.listing.platform == .ehi ? WorkbenchStyle.signalTeal : WorkbenchStyle.commandBlue,
                        systemImage: "building.2.fill"
                    )
                    Spacer()
                    StatusPill(
                        text: recommendation.bestRouteMode.label,
                        color: WorkbenchStyle.routeGreen,
                        systemImage: recommendation.bestRouteMode == .taxi ? "car.fill" : "bus.fill"
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("推荐总成本")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.muted)
                    Text(formatMoney(recommendation.bestTotal))
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundStyle(WorkbenchStyle.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("租车 \(formatMoney(recommendation.rentalTotal)) + 到店 \(formatMoney(bestRouteCost))")
                        .font(.caption)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                }
            }
        }
    }

    private var bestRouteCost: Double {
        recommendation.bestRouteMode == .taxi ? recommendation.taxiRoute.cost : recommendation.transitRoute.cost
    }
}

private struct DetailTitleRow: View {
    let icon: String
    let title: String
    var badge: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkbenchStyle.accent)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(WorkbenchStyle.green.opacity(0.12))
                    )
            }
        }
    }
}

private struct FactLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)
                .frame(width: 14, height: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(WorkbenchStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CostLineView: View {
    let label: String
    let value: Double
    var bold = false

    var body: some View {
        HStack {
            Text(label)
                .font(bold ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(bold ? WorkbenchStyle.ink : WorkbenchStyle.muted)
            Spacer()
            Text(formatMoney(value))
                .font(bold ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(WorkbenchStyle.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

private struct RouteDecisionCard: View {
    let title: String
    let total: Double
    let route: RouteEstimate
    let isBest: Bool

    var body: some View {
        WorkbenchCard(
            fill: isBest ? WorkbenchStyle.routeGreen.opacity(0.10) : WorkbenchStyle.elevatedSurface,
            stroke: isBest ? WorkbenchStyle.routeGreen.opacity(0.34) : WorkbenchStyle.hairline,
            isHighlighted: isBest,
            padding: 11
        ) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Spacer()
                    if isBest {
                        Text("推荐")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.routeGreen)
                    }
                }

                Text(formatMoney(total))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WorkbenchStyle.ink)
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 3) {
                    Text(route.summary)
                    Text("\(Int(route.durationMinutes.rounded())) 分钟 · \(route.distanceKm, specifier: "%.1f") km")
                }
                .font(.caption2)
                .foregroundStyle(WorkbenchStyle.muted)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WarningBox: View {
    let warnings: [ResultWarning]

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.orange.opacity(0.08), stroke: WorkbenchStyle.orange.opacity(0.22)) {
            ActionStatusRow(
                icon: "exclamationmark.triangle.fill",
                title: "提醒",
                message: renderWarnings(warnings),
                tone: .warning
            )
        }
    }
}

private struct ReceiptActionBar: View {
    let sourceURL: URL?
    let onMonitor: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                onMonitor()
            } label: {
                HStack(spacing: 6) {
                    Spacer()
                    Text("监控这个方案")
                    Image(systemName: "bell.badge")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(WorkbenchStyle.commandBlue)

            if let sourceURL {
                Link(destination: sourceURL) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("打开原始平台")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
