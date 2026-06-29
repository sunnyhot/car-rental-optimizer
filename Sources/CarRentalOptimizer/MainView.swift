import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @State private var showingMonitorCenter = false

    var body: some View {
        ZStack {
            WorkbenchBackground()

            VStack(spacing: 0) {
                WorkbenchHeader {
                    showingMonitorCenter = true
                }

                HSplitView {
                    SearchPanelView()
                        .frame(
                            minWidth: AppWindowLayout.searchPanelMinimumWidth,
                            idealWidth: AppWindowLayout.searchPanelIdealWidth,
                            maxWidth: AppWindowLayout.searchPanelMaximumWidth
                        )

                    ResultPanelView()
                        .frame(
                            minWidth: AppWindowLayout.resultsPanelMinimumWidth,
                            idealWidth: AppWindowLayout.resultsPanelIdealWidth
                        )

                    DetailPanelView()
                        .frame(
                            minWidth: AppWindowLayout.detailPanelMinimumWidth,
                            idealWidth: AppWindowLayout.detailPanelIdealWidth,
                            maxWidth: AppWindowLayout.detailPanelMaximumWidth
                        )
                }
            }
        }
        .sheet(isPresented: $showingMonitorCenter) {
            MonitorCenterView()
                .environmentObject(viewModel)
                .environmentObject(monitorViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMonitorCenter)) { _ in
            showingMonitorCenter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .retryLatestSearch)) { _ in
            Task { await viewModel.retrySearch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runDueMonitorChecks)) { _ in
            Task { await monitorViewModel.runDueChecks() }
        }
    }
}

private struct WorkbenchHeader: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    let onOpenMonitorCenter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [WorkbenchStyle.commandBlue, WorkbenchStyle.signalTeal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "car.side.front.open")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppInfo.appName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(WorkbenchStyle.ink)
                        Text("Car rental optimizer · v\(AppInfo.version)")
                            .font(.caption)
                            .foregroundStyle(WorkbenchStyle.muted)
                    }
                }

                Spacer(minLength: 18)

                lastSearchTile

                selectedRecommendationTile

                monitorHealthTile

                Button {
                    onOpenMonitorCenter()
                } label: {
                    Label("监控中心", systemImage: "bell.badge")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                StatusPill(
                    text: viewModel.isSearching ? "查询中" : "真实 API",
                    color: viewModel.isSearching ? WorkbenchStyle.amberAlert : WorkbenchStyle.commandBlue,
                    systemImage: viewModel.isSearching ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle.fill"
                )

                StatusPill(
                    text: monitorViewModel.backgroundMonitoringEnabled ? "后台巡查" : "手动巡查",
                    color: monitorViewModel.backgroundMonitoringEnabled ? WorkbenchStyle.routeGreen : WorkbenchStyle.muted,
                    systemImage: monitorViewModel.backgroundMonitoringEnabled ? "checkmark.circle.fill" : "pause.circle"
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            StatusLightRail(isActive: viewModel.isSearching, tone: viewModel.isSearching ? .active : .idle)
        }
        .background(WorkbenchStyle.panelSurface)
    }

    @ViewBuilder
    private var lastSearchTile: some View {
        if viewModel.lastSuccessfulSearchAt == nil {
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
        if viewModel.selected == nil {
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
                value: monitorHealthValue,
                icon: "bell.badge",
                tone: .warning
            )
        } else {
            TaskStatusTile(
                title: "监控状态",
                value: monitorHealthValue,
                icon: "bell.badge",
                tone: .success
            )
        }
    }

    private var selectedTotal: String {
        guard let selected = viewModel.selected else { return "--" }
        return formatMoney(selected.bestTotal)
    }

    private var lastSuccessfulSearch: String {
        guard let lastSuccessfulSearchAt = viewModel.lastSuccessfulSearchAt else { return "--" }
        return formatCompactDateTime(lastSuccessfulSearchAt)
    }

    private var monitorHealthValue: String {
        let summary = monitorViewModel.healthSummary
        guard summary.totalCount > 0 else { return "0" }
        if summary.needsAttentionCount > 0 {
            return "\(summary.needsAttentionCount)/\(summary.totalCount) 需处理"
        }
        return "\(summary.activeCount)/\(summary.totalCount) 正常"
    }
}
