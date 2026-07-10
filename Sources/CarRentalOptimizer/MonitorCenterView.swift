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
            title: "价格监控",
            subtitle: monitorListSubtitle,
            trailing: AnyView(
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkbenchStyle.decisionBlue)
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
                BlueprintStatePanel(
                    icon: "bell.badge",
                    title: "暂无监控",
                    message: "从候选方案创建监控，或点击左上角“新建”手动配置巡查条件。",
                    tone: .idle,
                    isActive: false
                )
                .padding(16)
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
                Label(
                    monitor.status.label,
                    systemImage: monitor.status == .needsAttention ? "exclamationmark.triangle.fill" : "circle.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(monitor.status == .needsAttention ? WorkbenchStyle.riskAmber : WorkbenchStyle.decisionBlue)
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
            Text("\(monitor.request.originLabel) · \(monitor.targetVehicleQuery.isEmpty ? "未指定车型" : monitor.targetVehicleQuery)")
                .font(.caption2)
                .foregroundStyle(WorkbenchStyle.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityLabel("\(monitor.name)，\(monitor.status.label)，\(monitor.frequency.label)，\(monitor.request.originLabel)")
    }
}

private struct MonitorSummaryBox: View {
    let monitor: PriceMonitor
    let trend: PriceTrendSummary

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 8)]
    }

    var body: some View {
        WorkbenchCard(
            fill: WorkbenchStyle.decisionBlue.opacity(0.08),
            stroke: WorkbenchStyle.decisionBlue.opacity(0.24),
            padding: 12
        ) {
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(
                    icon: "waveform.path.ecg.rectangle",
                    title: "监控摘要",
                    step: "LIVE",
                    trailing: monitor.status.label
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    BlueprintMetricTile(title: "最近租车价", value: trend.latestPlatformRentalPrice.map(formatMoney) ?? "--", icon: "yensign.circle", tone: .active)
                    BlueprintMetricTile(
                        title: "相比上次",
                        value: formatSignedMoney(trend.platformRentalDelta),
                        icon: "arrow.left.arrow.right",
                        tone: (trend.platformRentalDelta ?? 0) < 0 ? .success : .idle
                    )
                    BlueprintMetricTile(title: "下次巡查", value: monitor.nextCheckAt.map(formatCompactDateTime) ?? "--", icon: "clock.badge", tone: .idle)
                    BlueprintMetricTile(title: "历史低点", value: trend.lowestPlatformRentalPrice.map(formatMoney) ?? "--", icon: "arrow.down.circle", tone: .success)
                    BlueprintMetricTile(title: "历史高点", value: trend.highestPlatformRentalPrice.map(formatMoney) ?? "--", icon: "arrow.up.circle", tone: .idle)
                    BlueprintMetricTile(
                        title: "首次至今",
                        value: formatSignedMoney(trend.platformRentalDeltaFromFirst),
                        icon: "calendar.badge.clock",
                        tone: (trend.platformRentalDeltaFromFirst ?? 0) < 0 ? .success : .idle
                    )
                }
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
        MonitorCommandSurface(title: "价格趋势", icon: "chart.xyaxis.line", step: "TREND") {
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
            .chartForegroundStyleScale([
                "平台租车价": WorkbenchStyle.decisionBlue,
                "推荐总成本": WorkbenchStyle.signalTeal,
            ])
        }
    }
}

private struct MonitorEventList: View {
    let events: [PriceMonitorEvent]

    var body: some View {
        MonitorCommandSurface(title: "事件", icon: "bell.badge") {
            if events.isEmpty {
                Text("暂无降价或异常事件。")
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        MonitorEventPulseRow(event: event, index: index)
                    }
                }
            }
        }
    }
}

private struct MonitorSnapshotTable: View {
    let snapshots: [PriceSnapshot]

    var body: some View {
        MonitorCommandSurface(title: "历史快照", icon: "chart.line.uptrend.xyaxis") {
            if snapshots.isEmpty {
                Text("等待首次巡查。")
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(snapshots.reversed())) { snapshot in
                        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: WorkbenchStyle.hairline, padding: 9) {
                            HStack {
                                Text(DateFormatter.localizedString(from: snapshot.checkedAt, dateStyle: .short, timeStyle: .short))
                                Spacer()
                                Text(snapshot.platformRentalPrice.map(formatMoney) ?? snapshot.status.label)
                                Text(snapshot.status == .successful ? "历史快照，可能已失效" : snapshot.message)
                                    .font(.caption2)
                                    .foregroundStyle(snapshot.status == .successful ? WorkbenchStyle.amberAlert : WorkbenchStyle.muted)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }
}

private struct MonitorHealthStrip: View {
    let summary: MonitorHealthSummary
    let backgroundMonitoringEnabled: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 98), spacing: 8)]
    }

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, padding: 10) {
            VStack(alignment: .leading, spacing: 9) {
                BlueprintSectionHeader(
                    icon: "heart.text.square.fill",
                    title: "巡查健康",
                    step: "STATUS",
                    trailing: backgroundMonitoringEnabled ? "后台开启" : "手动巡查"
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                    BlueprintMetricTile(title: "总数", value: "\(summary.totalCount)", icon: "number", tone: .idle)
                    BlueprintMetricTile(
                        title: "需处理",
                        value: "\(summary.needsAttentionCount)",
                        icon: "exclamationmark.triangle.fill",
                        tone: summary.needsAttentionCount > 0 ? .warning : .idle
                    )
                    BlueprintMetricTile(
                        title: "近期降价",
                        value: "\(summary.recentPriceDropCount)",
                        icon: "arrow.down.circle.fill",
                        tone: summary.recentPriceDropCount > 0 ? .success : .idle
                    )
                    BlueprintMetricTile(title: "今日巡查", value: "\(summary.dueTodayCount)", icon: "calendar.badge.clock", tone: .active)
                }
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

private struct MonitorCommandSurface<Content: View>: View {
    let title: String
    let icon: String
    var step = "HISTORY"
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.elevatedSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(icon: icon, title: title, step: step)
                content
            }
        }
    }
}

private struct MonitorEventPulseRow: View {
    let event: PriceMonitorEvent
    let index: Int

    var body: some View {
        ActionStatusRow(
            icon: event.kind == .priceDrop ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill",
            title: event.kind == .priceDrop ? "价格下降" : "监控异常",
            message: event.message,
            tone: event.kind == .priceDrop ? .success : .warning
        )
        .commandCenterTransition(isEnabled: true, index: index)
    }
}
