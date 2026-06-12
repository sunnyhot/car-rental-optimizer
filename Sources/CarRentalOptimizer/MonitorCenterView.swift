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
            subtitle: "\(monitorViewModel.monitors.count) 个价格监控",
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
            List(selection: $monitorViewModel.selectedMonitorID) {
                ForEach(monitorViewModel.monitors) { monitor in
                    MonitorListRow(monitor: monitor)
                        .tag(monitor.id)
                }
            }
            .listStyle(.sidebar)
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
                        MonitorTrendChart(snapshots: monitorViewModel.selectedSnapshots)
                            .frame(height: 220)
                        MonitorEventList(events: monitorViewModel.selectedEvents)
                        MonitorSnapshotTable(snapshots: monitorViewModel.selectedSnapshots)
                        HStack {
                            Button(monitor.status == .paused ? "恢复监控" : "暂停监控") {
                                Task {
                                    if monitor.status == .paused {
                                        try? await monitorViewModel.resumeMonitor(id: monitor.id)
                                    } else {
                                        try? await monitorViewModel.pauseMonitor(id: monitor.id)
                                    }
                                }
                            }
                            Button("立即巡查") {
                                Task { await monitorViewModel.runDueChecks() }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                EmptyStateBlock(icon: "bell.badge", title: "暂无监控", message: "从候选方案或这里新建价格监控。")
            }
        }
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
        }
        .padding(.vertical, 5)
    }
}

private struct MonitorSummaryBox: View {
    let monitor: PriceMonitor
    let trend: PriceTrendSummary

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.accentSoft) {
            HStack {
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
            }
        }
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
                        Text(event.message)
                            .font(.caption)
                            .foregroundStyle(event.kind == .priceDrop ? WorkbenchStyle.green : WorkbenchStyle.muted)
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
                            Text(snapshot.platformRentalPrice.map(formatMoney) ?? snapshot.status.rawValue)
                            Text("历史快照，可能已失效")
                                .font(.caption2)
                                .foregroundStyle(WorkbenchStyle.orange)
                        }
                        .font(.caption)
                    }
                }
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
