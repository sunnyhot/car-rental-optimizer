import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @State private var showingMonitorCenter = false

    var body: some View {
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
        .background(WorkbenchStyle.background)
        .sheet(isPresented: $showingMonitorCenter) {
            MonitorCenterView()
                .environmentObject(viewModel)
                .environmentObject(monitorViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMonitorCenter)) { _ in
            showingMonitorCenter = true
        }
    }
}

private struct WorkbenchHeader: View {
    @EnvironmentObject var viewModel: SearchViewModel
    let onOpenMonitorCenter: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WorkbenchStyle.accent)
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

            HeaderMetric(
                title: "候选方案",
                value: "\(viewModel.results.count)",
                icon: "list.bullet.rectangle"
            )

            HeaderMetric(
                title: "当前推荐",
                value: selectedTotal,
                icon: "yensign.circle"
            )

            Button {
                onOpenMonitorCenter()
            } label: {
                Label("监控中心", systemImage: "bell.badge")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            StatusPill(
                text: viewModel.isSearching ? "查询中" : "真实 API",
                color: viewModel.isSearching ? WorkbenchStyle.orange : WorkbenchStyle.accent,
                systemImage: viewModel.isSearching ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle.fill"
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(WorkbenchStyle.surface)
        .subtleDividerOverlay()
    }

    private var selectedTotal: String {
        guard let selected = viewModel.selected else { return "--" }
        return formatMoney(selected.bestTotal)
    }
}

private struct HeaderMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkbenchStyle.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WorkbenchStyle.accentSoft.opacity(0.75))
        )
    }
}
