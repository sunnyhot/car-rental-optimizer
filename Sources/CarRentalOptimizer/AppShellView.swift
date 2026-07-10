import SwiftUI

struct AppShellView: View {
    @ObservedObject var navigationModel: AppNavigationModel
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel
    @EnvironmentObject private var comparisonViewModel: ComparisonWorkspaceViewModel

    var body: some View {
        ZStack {
            WorkbenchBackground()

            VStack(spacing: 0) {
                BlueprintStatusBar()

                HStack(spacing: 0) {
                    PrimaryNavigationRail(navigationModel: navigationModel)
                        .frame(width: AppWindowLayout.navigationRailWidth)

                    Group {
                        switch navigationModel.selectedWorkspace {
                        case .comparison:
                            searchWorkspace
                        case .monitoring:
                            MonitorCenterView()
                                .environmentObject(searchViewModel)
                                .environmentObject(monitorViewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var searchWorkspace: some View {
        HSplitView {
            SearchPanelView()
                .frame(
                    minWidth: AppWindowLayout.searchPanelMinimumWidth,
                    idealWidth: AppWindowLayout.searchPanelIdealWidth,
                    maxWidth: AppWindowLayout.searchPanelMaximumWidth
                )

            if comparisonViewModel.isComparing {
                ComparisonMatrixView()
                    .frame(
                        minWidth: AppWindowLayout.resultsPanelMinimumWidth + AppWindowLayout.detailPanelMinimumWidth,
                        idealWidth: AppWindowLayout.resultsPanelIdealWidth + AppWindowLayout.detailPanelIdealWidth
                    )
            } else {
                ResultPanelView()
                    .frame(minWidth: AppWindowLayout.resultsPanelMinimumWidth, idealWidth: AppWindowLayout.resultsPanelIdealWidth)
                DetailPanelView()
                    .frame(
                        minWidth: AppWindowLayout.detailPanelMinimumWidth,
                        idealWidth: AppWindowLayout.detailPanelIdealWidth,
                        maxWidth: AppWindowLayout.detailPanelMaximumWidth
                    )
            }
        }
        .onChange(of: searchViewModel.searchGeneration) { _, _ in
            comparisonViewModel.resetForNewSearch()
        }
        .onChange(of: searchViewModel.results) { _, results in
            comparisonViewModel.reconcile(with: results)
        }
    }
}

struct PrimaryNavigationRail: View {
    @ObservedObject var navigationModel: AppNavigationModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(AppWorkspace.allCases) { workspace in
                Button {
                    navigationModel.selectedWorkspace = workspace
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: workspace.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(workspace.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        navigationModel.selectedWorkspace == workspace
                            ? WorkbenchStyle.decisionBlue
                            : WorkbenchStyle.muted
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                navigationModel.selectedWorkspace == workspace
                                    ? WorkbenchStyle.decisionBlue.opacity(0.12)
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workspace.title)
                .help(workspace.title)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .background(WorkbenchStyle.panelSurface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(WorkbenchStyle.hairline).frame(width: 1)
        }
    }
}

struct BlueprintStatusBar: View {
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [WorkbenchStyle.decisionBlue, WorkbenchStyle.signalTeal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.appName).font(.headline.weight(.bold))
                    Text("Route Blueprint · v\(AppInfo.version)")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                }

                Spacer(minLength: 12)

                lastSearchTile
                selectedRecommendationTile
                monitorHealthTile
                StatusPill(
                    text: searchViewModel.isSearching ? "查询中" : "官方 API",
                    color: searchViewModel.isSearching ? WorkbenchStyle.riskAmber : WorkbenchStyle.decisionBlue,
                    systemImage: searchViewModel.isSearching ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle.fill"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            StatusLightRail(
                isActive: searchViewModel.isSearching,
                tone: searchViewModel.isSearching ? .active : .idle
            )
        }
        .background(WorkbenchStyle.panelSurface)
    }

    private var monitorValue: String {
        let summary = monitorViewModel.healthSummary
        guard summary.totalCount > 0 else { return "0" }
        return summary.needsAttentionCount > 0
            ? "\(summary.needsAttentionCount)/\(summary.totalCount) 需处理"
            : "\(summary.activeCount)/\(summary.totalCount) 正常"
    }

    @ViewBuilder
    private var lastSearchTile: some View {
        if searchViewModel.lastSuccessfulSearchAt == nil {
            TaskStatusTile(
                title: "上次搜索",
                value: lastSuccessfulSearch,
                icon: "clock.badge.checkmark",
                tone: .idle
            )
        } else {
            TaskStatusTile(
                title: "上次搜索",
                value: lastSuccessfulSearch,
                icon: "clock.badge.checkmark",
                tone: .success
            )
        }
    }

    @ViewBuilder
    private var selectedRecommendationTile: some View {
        if searchViewModel.selected == nil {
            TaskStatusTile(
                title: "当前推荐",
                value: selectedTotal,
                icon: "yensign.circle",
                tone: .idle
            )
        } else {
            TaskStatusTile(
                title: "当前推荐",
                value: selectedTotal,
                icon: "yensign.circle",
                tone: .active
            )
        }
    }

    @ViewBuilder
    private var monitorHealthTile: some View {
        if monitorViewModel.healthSummary.needsAttentionCount > 0 {
            TaskStatusTile(
                title: "监控状态",
                value: monitorValue,
                icon: "bell.badge",
                tone: .warning
            )
        } else {
            TaskStatusTile(
                title: "监控状态",
                value: monitorValue,
                icon: "bell.badge",
                tone: .success
            )
        }
    }

    private var selectedTotal: String {
        guard let selected = searchViewModel.selected else { return "--" }
        return formatMoney(selected.bestTotal)
    }

    private var lastSuccessfulSearch: String {
        guard let lastSuccessfulSearchAt = searchViewModel.lastSuccessfulSearchAt else { return "--" }
        return formatCompactDateTime(lastSuccessfulSearchAt)
    }
}
