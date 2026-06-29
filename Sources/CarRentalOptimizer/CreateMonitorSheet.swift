import CarRentalDomain
import SwiftUI

struct CreateMonitorSheet: View {
    let recommendation: Recommendation?
    let request: SearchRequest
    let onSaveFromRecommendation: (MonitoringFrequency, PriceDropRule, Bool) async throws -> Void
    let onSaveManual: (String, SearchRequest, String, MonitoringFrequency, PriceDropRule, Bool) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var vehicleQuery = ""
    @State private var frequency: MonitoringFrequency = .smart
    @State private var notifyOnAnyDecrease = true
    @State private var minimumDropAmount = ""
    @State private var minimumDropPercent = ""
    @State private var systemNotificationsEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        WorkbenchSheetShell(
            title: recommendation == nil ? "新建价格监控" : "监控这个方案",
            subtitle: recommendation == nil ? "手动配置巡查条件" : "保存当前报价并持续巡查",
            icon: "bell.badge",
            tone: .active
        ) {
            VStack(alignment: .leading, spacing: 16) {
                summary
                controls

                if let errorMessage {
                    ActionStatusRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "保存失败",
                        message: errorMessage,
                        tone: .critical
                    )
                }

                HStack {
                    Spacer()
                    Button("取消") { dismiss() }
                    Button("保存监控") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WorkbenchStyle.commandBlue)
                }
            }
            .padding(20)
        }
        .frame(width: 460)
        .onAppear {
            name = recommendation.map { "\($0.listing.vehicleName) \(request.pickupAt)" } ?? "租车价格监控"
            vehicleQuery = recommendation?.listing.vehicleName ?? request.vehicleQuery
        }
    }

    private var summary: some View {
        WorkbenchCard(fill: WorkbenchStyle.elevatedSurface, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                MonitorSheetFactLine(icon: "calendar", text: "\(request.pickupAt) 至 \(request.returnAt)")
                MonitorSheetFactLine(icon: "mappin.circle.fill", text: request.originLabel)
                MonitorSheetFactLine(icon: "car.fill", text: vehicleQuery.isEmpty ? "未指定车型" : vehicleQuery)
                if let recommendation {
                    MonitorSheetFactLine(icon: "yensign.circle", text: "租车价 \(formatMoney(recommendation.rentalTotal)) · 总成本 \(formatMoney(recommendation.bestTotal))")
                    MonitorSheetFactLine(icon: "building.2.fill", text: "\(recommendation.listing.platform.label) · \(recommendation.listing.store.name)")
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recommendation == nil {
                TextField("监控名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("车型", text: $vehicleQuery)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("巡查频率", selection: $frequency) {
                ForEach(MonitoringFrequency.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }

            Toggle("只要平台租车价下降就提醒", isOn: $notifyOnAnyDecrease)
            TextField("固定金额阈值，例如 20", text: $minimumDropAmount)
                .textFieldStyle(.roundedBorder)
            TextField("百分比阈值，例如 5", text: $minimumDropPercent)
                .textFieldStyle(.roundedBorder)
            Toggle("允许 macOS 系统通知", isOn: $systemNotificationsEnabled)
        }
    }

    private func save() async {
        do {
            let rule = PriceDropRule(
                notifyOnAnyDecrease: notifyOnAnyDecrease,
                minimumDropAmount: Double(minimumDropAmount),
                minimumDropPercent: Double(minimumDropPercent).map { $0 / 100 }
            )
            if recommendation != nil {
                try await onSaveFromRecommendation(frequency, rule, systemNotificationsEnabled)
            } else {
                var manualRequest = request
                manualRequest.vehicleQuery = vehicleQuery
                try await onSaveManual(name, manualRequest, vehicleQuery, frequency, rule, systemNotificationsEnabled)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MonitorSheetFactLine: View {
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
