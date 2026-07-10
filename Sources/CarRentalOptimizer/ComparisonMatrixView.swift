import AppKit
import CarRentalDomain
import SwiftUI

struct ComparisonMatrixView: View {
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel
    @EnvironmentObject private var comparisonViewModel: ComparisonWorkspaceViewModel
    @State private var pendingMonitorRecommendation: Recommendation?

    private var sections: [ComparisonSection] {
        ComparisonPresentation.sections(
            candidates: comparisonViewModel.selectedRecommendations,
            insightStates: comparisonViewModel.insightStates,
            onlyDifferences: comparisonViewModel.onlyShowsDifferences
        )
    }

    var body: some View {
        WorkbenchPanel(title: "方案对比", subtitle: "\(comparisonViewModel.selectedRecommendations.count) 个真实候选") {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        comparisonViewModel.exitComparison()
                    } label: {
                        Label("返回候选", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Toggle("只看差异", isOn: $comparisonViewModel.onlyShowsDifferences)
                        .toggleStyle(.checkbox)

                    Spacer()
                    Text("未确认表示平台或车型库未提供，不能解释为不支持")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                }
                .padding(12)

                ScrollView([.horizontal, .vertical]) {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            matrixHeaderCell("比较项", width: 150)
                            ForEach(comparisonViewModel.selectedRecommendations) { recommendation in
                                candidateHeader(recommendation)
                                    .frame(width: 220)
                            }
                        }

                        ForEach(sections) { section in
                            GridRow {
                                Text(section.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WorkbenchStyle.routeInk)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(9)
                                ForEach(comparisonViewModel.selectedRecommendations) { _ in
                                    Color.clear.frame(width: 220, height: 1)
                                }
                            }
                            .background(WorkbenchStyle.decisionBlue.opacity(0.07))

                            ForEach(section.rows) { row in
                                GridRow {
                                    matrixHeaderCell(row.label, width: 150)
                                    ForEach(row.cells) { cell in
                                        Text(cell.text)
                                            .font(.caption)
                                            .foregroundStyle(cellColor(cell.tone))
                                            .frame(width: 220, alignment: .leading)
                                            .frame(minHeight: 36)
                                            .padding(.horizontal, 9)
                                            .background(cellBackground(cell.tone))
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(item: $pendingMonitorRecommendation) { recommendation in
            CreateMonitorSheet(
                recommendation: recommendation,
                request: searchViewModel.request,
                onSaveFromRecommendation: { frequency, rule, notifications in
                    try await monitorViewModel.createMonitor(
                        from: recommendation,
                        request: searchViewModel.request,
                        frequency: frequency,
                        alertRule: rule,
                        systemNotificationsEnabled: notifications
                    )
                },
                onSaveManual: { _, _, _, _, _, _ in }
            )
        }
    }

    private func candidateHeader(_ recommendation: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(recommendation.listing.vehicleName)
                    .font(.callout.weight(.bold))
                    .lineLimit(2)
                Spacer()
                Button {
                    comparisonViewModel.remove(id: recommendation.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除此候选")
            }
            Text(formatMoney(recommendation.bestTotal))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            HStack(spacing: 6) {
                Button("设为当前方案") {
                    searchViewModel.selectResult(recommendation.id)
                    comparisonViewModel.exitComparison()
                }
                Button("监控") {
                    pendingMonitorRecommendation = recommendation
                }
                Button("打开官方页面") {
                    guard let url = URL(string: recommendation.listing.sourceUrl) else { return }
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            insightStatus(for: recommendation)
        }
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 112, alignment: .top)
        .padding(9)
        .background(WorkbenchStyle.elevatedSurface)
    }

    private func matrixHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WorkbenchStyle.muted)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 36)
            .padding(.horizontal, 9)
    }

    @ViewBuilder
    private func insightStatus(for recommendation: Recommendation) -> some View {
        if let state = comparisonViewModel.insightStates[recommendation.id] {
            switch state {
            case .loading:
                Label("正在读取车型资料", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.decisionBlue)
            case .loaded:
                Label("车型资料已加载", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.signalTeal)
            case .fallback:
                Button("联网资料不可用，重试车型资料") {
                    comparisonViewModel.retryInsight(for: recommendation)
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    private func cellColor(_ tone: ComparisonCellTone) -> Color {
        switch tone {
        case .standard: return WorkbenchStyle.ink
        case .advantage: return WorkbenchStyle.signalTeal
        case .warning: return WorkbenchStyle.riskAmber
        case .unavailable: return WorkbenchStyle.muted
        }
    }

    private func cellBackground(_ tone: ComparisonCellTone) -> Color {
        tone == .advantage ? WorkbenchStyle.signalTeal.opacity(0.08) : Color.clear
    }
}
