import CarRentalDomain
import Foundation
import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @State private var pendingMonitorRecommendation: Recommendation?

    var body: some View {
        WorkbenchPanel(
            title: "候选方案",
            subtitle: panelSubtitle,
            trailing: panelTrailing
        ) {
            Group {
                if viewModel.isSearching {
                    LoadingResultsView(phase: viewModel.searchProgressPhase)
                } else if viewModel.results.isEmpty {
                    EmptyResultsView(
                        statuses: viewModel.platformStatuses,
                        phase: viewModel.searchProgressPhase
                    ) {
                        Task { await viewModel.retrySearch() }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let notice = viewModel.retainedResultsNotice {
                                RetainedResultsNoticeView(notice: notice)
                            }

                            SearchDiagnosticSummaryView(summary: viewModel.searchDiagnosticSummary)

                            LazyVStack(spacing: 10) {
                                ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                                    ResultRowView(
                                        rank: index + 1,
                                        recommendation: result,
                                        isSelected: viewModel.selectedId == result.id
                                    ) {
                                        viewModel.selectResult(result.id)
                                        pendingMonitorRecommendation = result
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectResult(result.id)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
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

    private var panelTrailing: AnyView {
        AnyView(
            HStack(alignment: .center, spacing: 12) {
                if !viewModel.results.isEmpty {
                    Picker("排序", selection: $viewModel.recommendationSortMode) {
                        ForEach(RecommendationSortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .accessibilityLabel("候选方案排序")
                }

                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
        )
    }

    private var panelSubtitle: String {
        if viewModel.results.isEmpty {
            return "等待真实报价"
        }
        if viewModel.isShowingStaleResults {
            return "\(viewModel.results.count) 个上次成功候选，等待本次查询恢复"
        }
        return "\(viewModel.results.count) 个真实候选，同车型取优后按总成本升序"
    }
}

private struct LoadingResultsView: View {
    let phase: SearchProgressPhase

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            SurfaceBox(fill: WorkbenchStyle.surface, padding: 18) {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(phase.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text(phase.message)
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
    let phase: SearchProgressPhase
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            EmptyStateBlock(
                icon: emptyStateIcon,
                title: emptyStateTitle,
                message: emptyStateMessage
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

            RecoverySuggestionList(statuses: statuses)
                .frame(maxWidth: 460)

            Button {
                onRetry()
            } label: {
                Label("重试本次查询", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("重试本次租车查询")
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        phase == .failed ? "exclamationmark.triangle" : "doc.text.magnifyingglass"
    }

    private var emptyStateTitle: String {
        phase == .failed ? "查询未完成" : "等待结果"
    }

    private var emptyStateMessage: String {
        if phase == .failed {
            return "本次比较没有完成，可重试或调整搜索条件。"
        }
        return "没有可排序的真实车源时，这里不会显示推测价格。"
    }
}

private struct RetainedResultsNoticeView: View {
    let notice: RetainedResultsNotice

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.orange.opacity(0.08), stroke: WorkbenchStyle.orange.opacity(0.22), padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(WorkbenchStyle.orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text("\(notice.message) 上次成功：\(DateFormatter.localizedString(from: notice.lastSuccessfulSearchAt, dateStyle: .short, timeStyle: .short))")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SearchDiagnosticSummaryView: View {
    let summary: SearchDiagnosticSummary

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.surface, padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    InlineMetric(title: "已查平台", value: "\(summary.queriedPlatforms.count)")
                    InlineMetric(title: "成功平台", value: "\(summary.successfulPlatforms.count)")
                    InlineMetric(title: "原始报价", value: "\(summary.listingCount)")
                    InlineMetric(title: "可见结果", value: "\(summary.visibleResultCount)")
                }
                Text(summary.routeEstimateStatus)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
            }
        }
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

private struct RecoverySuggestionList: View {
    let statuses: [PlatformEvidenceStatus]

    private var actions: [SearchRecoveryAction] {
        var seen = Set<String>()
        return statuses.flatMap(SearchRecoveryAction.actions).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        if !actions.isEmpty {
            SurfaceBox(fill: WorkbenchStyle.surface, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    MonitorSectionLikeTitle(icon: "wrench.and.screwdriver.fill", title: "建议操作")
                    ForEach(actions) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: action.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WorkbenchStyle.accent)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WorkbenchStyle.ink)
                                Text(action.message)
                                    .font(.caption2)
                                    .foregroundStyle(WorkbenchStyle.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MonitorSectionLikeTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkbenchStyle.accent)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
            Spacer()
        }
    }
}

private struct ResultRowView: View {
    let rank: Int
    let recommendation: Recommendation
    let isSelected: Bool
    let onMonitor: () -> Void

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
                    Button {
                        onMonitor()
                    } label: {
                        Label("监控", systemImage: "bell.badge")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("监控此租车方案")
                }

                Text(rankingReason)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)

                QuoteCredibilityBadge(credibility: QuoteCredibility.make(for: recommendation))
            }
            .padding(14)
        }
        .accessibilityLabel(accessibilitySummary)
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

    private var accessibilitySummary: String {
        "\(rank)号方案，\(recommendation.listing.platform.label)，\(recommendation.listing.vehicleName)，总成本\(formatMoney(recommendation.bestTotal))"
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

private struct QuoteCredibilityBadge: View {
    let credibility: QuoteCredibility

    var body: some View {
        Label(credibility.title, systemImage: credibility.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .help(credibility.message)
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
