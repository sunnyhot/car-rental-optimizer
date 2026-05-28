import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                Text("候选方案")
                    .font(.headline)
                Spacer()
                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if viewModel.isSearching {
                // Loading state
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("正在比较")
                        .font(.headline)
                    Text("正在计算车辆价格和交通成本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "car.2")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("等待查询")
                        .font(.headline)
                    Text("设置搜索条件后，点击「开始比较」查看排序结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if !viewModel.snapshotDiagnostics.isEmpty {
                        DiagnosticsView(diagnostics: viewModel.snapshotDiagnostics)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Result list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            ResultRowView(
                                rank: index + 1,
                                recommendation: result,
                                isSelected: viewModel.selectedId == result.id
                            )
                            .onTapGesture {
                                viewModel.selectResult(result.id)
                            }

                            if index < viewModel.results.count - 1 {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Result Row

struct ResultRowView: View {
    let rank: Int
    let recommendation: Recommendation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("\(rank)")
                .font(.title2.bold())
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

            // Main content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recommendation.listing.store.name)
                        .fontWeight(.medium)
                    Text(recommendation.listing.platform.label)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }

                Text("\(recommendation.listing.vehicleName) · \(recommendation.match.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    CostBadge(title: "最佳", value: recommendation.bestTotal, highlight: true)
                    CostBadge(title: "打车", value: recommendation.taxiTotal, highlight: false)
                    CostBadge(title: "公交", value: recommendation.transitTotal, highlight: false)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

// MARK: - Cost Badge

struct CostBadge: View {
    let title: String
    let value: Double
    let highlight: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("¥\(Int(value))")
                .font(highlight ? .caption.bold() : .caption)
                .foregroundStyle(highlight ? .primary : .secondary)
        }
    }
}

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    let diagnostics: [SnapshotDiagnostics]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(diagnostics, id: \.url) { diag in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(diag.platform.label).fontWeight(.medium)
                        Text(diag.title).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Text("文本: \(diag.textLength) 字")
                        Text("价格: \(diag.priceCandidateCount)")
                        Text("车型: \(diag.vehicleCandidateCount)")
                        Text("门店: \(diag.storeCandidateCount)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
    }
}
