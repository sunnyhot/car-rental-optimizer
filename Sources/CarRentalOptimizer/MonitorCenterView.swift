import CarRentalDomain
import Charts
import SwiftUI

struct MonitorCenterView: View {
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @EnvironmentObject var searchViewModel: SearchViewModel
    @State private var showingCreateSheet = false

    var body: some View {
        HSplitView {
            monitorList
                .frame(minWidth: 300, idealWidth: 340)
            monitorDetail
                .frame(minWidth: 560, idealWidth: 680)
        }
        .frame(minWidth: 920, minHeight: 620)
        .task {
            try? await monitorViewModel.reload()
        }
        .onChange(of: monitorViewModel.selectedMonitorID) { _, _ in
            Task { try? await monitorViewModel.reloadSelection() }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateMonitorSheet(
                recommendation: nil,
                request: searchViewModel.request,
                onSaveFromRecommendation: { _, _, _ in },
                onSaveManual: { name, request, vehicleQuery, frequency, rule, notifications in
                    try await monitorViewModel.saveManualMonitor(
                        name: name,
                        request: request,
                        targetVehicleQuery: vehicleQuery,
                        frequency: frequency,
                        alertRule: rule,
                        systemNotificationsEnabled: notifications
                    )
                }
            )
        }
    }

    private var monitorList: some View {
        WorkbenchPanel(
            title: "监控中心",
            subtitle: monitorListSubtitle,
            trailing: AnyView(
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("新建价格监控")
            )
        ) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    MonitorHealthStrip(
                        summary: monitorViewModel.healthSummary,
                        backgroundMonitoringEnabled: monitorViewModel.backgroundMonitoringEnabled
                    )
                    MonitorFilterBar(
                        filter: $monitorViewModel.filter,
                        count: { monitorViewModel.filterCount(for: $0) }
                    )
                    if let message = monitorViewModel.operationFeedbackMessage {
                        StatusMessageRow(message: message, systemImage: "checkmark.circle.fill")
                    }
                }
                .padding(12)

                List(selection: $monitorViewModel.selectedMonitorID) {
                    ForEach(monitorViewModel.displayedMonitors) { monitor in
                        MonitorListRow(monitor: monitor)
                            .tag(monitor.id)
                    }
                }
                .listStyle(.sidebar)

                HStack(spacing: 8) {
                    Button {
                        Task { await monitorViewModel.runShownChecks() }
                    } label: {
                        Label("巡查当前", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(shownMonitorIDs.isEmpty)

                    Button {
                        Task { try? await monitorViewModel.pauseMonitors(ids: shownMonitorIDs) }
                    } label: {
                        Label("暂停当前", systemImage: "pause.circle")
                    }
                    .disabled(shownMonitorIDs.isEmpty)

                    Button {
                        Task { try? await monitorViewModel.resumeMonitors(ids: shownMonitorIDs) }
                    } label: {
                        Label("恢复当前", systemImage: "play.circle")
                    }
                    .disabled(shownMonitorIDs.isEmpty)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(12)
                .subtleDividerOverlay()
            }
        }
    }

    private var monitorDetail: some View {
        WorkbenchPanel(
            title: monitorViewModel.selectedMonitor?.name ?? "监控详情",
            subtitle: monitorViewModel.selectedMonitor?.status.label
        ) {
            if let monitor = monitorViewModel.selectedMonitor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let message = monitorViewModel.operationFeedbackMessage {
                            StatusMessageRow(message: message, systemImage: "checkmark.circle.fill")
                        }
                        MonitorSummaryBox(monitor: monitor, trend: monitorViewModel.selectedTrend)
                        Toggle(
                            "关闭窗口后继续巡查",
                            isOn: Binding(
                                get: { monitorViewModel.backgroundMonitoringEnabled },
                                set: { monitorViewModel.setBackgroundMonitoringEnabled($0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .help("应用保持运行时，按设定频率自动巡查价格。退出应用后停止。")
                        HStack {
                            Button {
                                Task {
                                    if monitor.status == .paused {
                                        try? await monitorViewModel.resumeMonitor(id: monitor.id)
                                    } else {
                                        try? await monitorViewModel.pauseMonitor(id: monitor.id)
                                    }
                                }
                            } label: {
                                Label(monitor.status == .paused ? "恢复监控" : "暂停监控", systemImage: monitor.status == .paused ? "play.circle" : "pause.circle")
                            }
                            Button {
                                Task { await monitorViewModel.runDueChecks() }
                            } label: {
                                Label("立即巡查", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.bordered)
                        MonitorTrendChart(snapshots: monitorViewModel.selectedSnapshots)
                            .frame(height: 220)
                        MonitorEventList(events: monitorViewModel.selectedEvents)
                        MonitorSnapshotTable(snapshots: monitorViewModel.selectedSnapshots)
                    }
                    .padding(16)
                }
            } else {
                EmptyStateBlock(icon: "bell.badge", title: "暂无监控", message: "从候选方案或这里新建价格监控。")
            }
        }
    }

    private var monitorListSubtitle: String {
        let summary = monitorViewModel.healthSummary
        if summary.totalCount == 0 {
            return "暂无价格监控"
        }
        return "\(summary.totalCount) 个监控，\(summary.needsAttentionCount) 个需处理，\(summary.dueTodayCount) 个今日巡查"
    }

    private var shownMonitorIDs: [String] {
        monitorViewModel.displayedMonitors.map(\.id)
    }
}

private struct MonitorListRow: View {
    let monitor: PriceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(monitor.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                StatusPill(
                    text: monitor.status.label,
                    color: monitor.status == .needsAttention ? WorkbenchStyle.orange : WorkbenchStyle.accent,
                    systemImage: nil
                )
            }
            Text("\(monitor.request.pickupAt) 至 \(monitor.request.returnAt)")
                .font(.caption)
                .foregroundStyle(WorkbenchStyle.muted)
            Text(monitor.frequency.label)
                .font(.caption2)
                .foregroundStyle(WorkbenchStyle.muted)
            if let nextCheckAt = monitor.nextCheckAt {
                Text("下次 \(formatCompactDateTime(nextCheckAt))")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .accessibilityLabel("\(monitor.name)，\(monitor.status.label)，\(monitor.frequency.label)")
    }
}

private struct MonitorSummaryBox: View {
    let monitor: PriceMonitor
    let trend: PriceTrendSummary

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 8)]
    }

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.accentSoft) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                MetricPill(title: "最近租车价", value: trend.latestPlatformRentalPrice.map(formatMoney) ?? "--")
                MetricPill(
                    title: "相比上次",
                    value: formatSignedMoney(trend.platformRentalDelta),
                    color: (trend.platformRentalDelta ?? 0) < 0 ? WorkbenchStyle.green : WorkbenchStyle.muted
                )
                MetricPill(
                    title: "下次巡查",
                    value: monitor.nextCheckAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "--"
                )
                MetricPill(title: "历史低点", value: trend.lowestPlatformRentalPrice.map(formatMoney) ?? "--", color: WorkbenchStyle.green)
                MetricPill(title: "历史高点", value: trend.highestPlatformRentalPrice.map(formatMoney) ?? "--")
                MetricPill(
                    title: "首次至今",
                    value: formatSignedMoney(trend.platformRentalDeltaFromFirst),
                    color: (trend.platformRentalDeltaFromFirst ?? 0) < 0 ? WorkbenchStyle.green : WorkbenchStyle.muted
                )
            }
        }
        .accessibilityLabel("监控摘要，最近租车价 \(trend.latestPlatformRentalPrice.map(formatMoney) ?? "暂无")")
    }
}

private struct MonitorTrendChart: View {
    let snapshots: [PriceSnapshot]

    private var points: [PriceSnapshot] {
        snapshots.filter { $0.status == .successful }
    }

    var body: some View {
        SurfaceBox {
            Chart {
                ForEach(points) { snapshot in
                    if let price = snapshot.platformRentalPrice {
                        LineMark(x: .value("时间", snapshot.checkedAt), y: .value("价格", price))
                            .foregroundStyle(by: .value("口径", "平台租车价"))
                    }
                    if let total = snapshot.recommendationTotalCost {
                        LineMark(x: .value("时间", snapshot.checkedAt), y: .value("价格", total))
                            .foregroundStyle(by: .value("口径", "推荐总成本"))
                    }
                }
            }
            .chartLegend(position: .bottom)
        }
    }
}

private struct MonitorEventList: View {
    let events: [PriceMonitorEvent]

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 8) {
                MonitorSectionTitleRow(icon: "bell.badge", title: "事件")
                if events.isEmpty {
                    Text("暂无降价或异常事件。")
                        .font(.caption)
                        .foregroundStyle(WorkbenchStyle.muted)
                } else {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: event.kind == .priceDrop ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(event.kind == .priceDrop ? WorkbenchStyle.green : WorkbenchStyle.orange)
                                .frame(width: 16)
                            Text(event.message)
                                .font(.caption)
                                .foregroundStyle(event.kind == .priceDrop ? WorkbenchStyle.green : WorkbenchStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

private struct MonitorSnapshotTable: View {
    let snapshots: [PriceSnapshot]

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 8) {
                MonitorSectionTitleRow(icon: "chart.line.uptrend.xyaxis", title: "历史快照")
                if snapshots.isEmpty {
                    Text("等待首次巡查。")
                        .font(.caption)
                        .foregroundStyle(WorkbenchStyle.muted)
                } else {
                    ForEach(Array(snapshots.reversed())) { snapshot in
                        HStack {
                            Text(DateFormatter.localizedString(from: snapshot.checkedAt, dateStyle: .short, timeStyle: .short))
                            Spacer()
                            Text(snapshot.platformRentalPrice.map(formatMoney) ?? snapshot.status.label)
                            Text(snapshot.status == .successful ? "历史快照，可能已失效" : snapshot.message)
                                .font(.caption2)
                                .foregroundStyle(snapshot.status == .successful ? WorkbenchStyle.orange : WorkbenchStyle.muted)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

private struct MonitorHealthStrip: View {
    let summary: MonitorHealthSummary
    let backgroundMonitoringEnabled: Bool

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.surface, padding: 10) {
            HStack(spacing: 8) {
                MetricPill(title: "总数", value: "\(summary.totalCount)")
                MetricPill(title: "需处理", value: "\(summary.needsAttentionCount)", color: summary.needsAttentionCount > 0 ? WorkbenchStyle.orange : WorkbenchStyle.muted)
                MetricPill(title: "降价", value: "\(summary.recentPriceDropCount)", color: summary.recentPriceDropCount > 0 ? WorkbenchStyle.green : WorkbenchStyle.muted)
                MetricPill(title: "今日", value: "\(summary.dueTodayCount)")
                StatusPill(
                    text: backgroundMonitoringEnabled ? "后台开" : "后台关",
                    color: backgroundMonitoringEnabled ? WorkbenchStyle.green : WorkbenchStyle.muted,
                    systemImage: backgroundMonitoringEnabled ? "checkmark.circle.fill" : "pause.circle"
                )
            }
        }
    }
}

private struct MonitorFilterBar: View {
    @Binding var filter: MonitorCenterFilter
    let count: (MonitorCenterFilter) -> Int

    var body: some View {
        Picker("监控筛选", selection: $filter) {
            ForEach(MonitorCenterFilter.allCases, id: \.self) { filter in
                Text("\(filter.label) \(count(filter))")
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("监控筛选")
    }
}

private struct StatusMessageRow: View {
    let message: String
    let systemImage: String

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.accentSoft, padding: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(WorkbenchStyle.accent)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.ink)
                    .lineLimit(2)
                Spacer()
            }
        }
    }
}

private struct MonitorSectionTitleRow: View {
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
