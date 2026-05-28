import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        Group {
            if let recommendation = viewModel.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        HStack {
                            Text("推荐明细")
                                .font(.headline)
                            Spacer()
                            Text(recommendation.match.label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        }

                        // Hero metric
                        VStack(spacing: 4) {
                            Text("推荐总成本")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("¥\(recommendation.bestTotal, specifier: "%.0f")")
                                .font(.system(size: 32, weight: .bold))
                            Text(recommendation.bestRouteMode == .taxi ? "按打车到店计算" : "按公共交通到店计算")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor.opacity(0.06))
                        .cornerRadius(8)

                        // Store info
                        DetailSection {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recommendation.listing.store.name)
                                    .font(.headline)
                                Text("\(recommendation.listing.store.city) · \(recommendation.listing.store.address)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(recommendation.listing.store.hours) · 距离约 \(recommendation.listing.store.distanceKm, specifier: "%.1f") km")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Cost breakdown
                        DetailSection(header: "费用拆分") {
                            VStack(spacing: 0) {
                                CostLineView(label: "租车基础价", value: recommendation.listing.basePrice)
                                CostLineView(label: "平台服务费", value: recommendation.listing.platformFees)
                                CostLineView(label: "保险/保障", value: recommendation.listing.insuranceFees)
                                CostLineView(label: "异店还车费", value: recommendation.listing.oneWayFee)
                                Divider()
                                CostLineView(label: "租车小计", value: recommendation.rentalTotal, bold: true)
                            }
                        }

                        // Route grid
                        HStack(spacing: 12) {
                            RouteBoxView(
                                title: "打车",
                                total: recommendation.taxiTotal,
                                summary: recommendation.taxiRoute.summary
                            )
                            RouteBoxView(
                                title: "公共交通",
                                total: recommendation.transitTotal,
                                summary: recommendation.transitRoute.summary
                            )
                        }

                        // Warnings
                        if !recommendation.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text("提醒")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                Text(renderWarnings(recommendation.warnings))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.08))
                            .cornerRadius(6)
                        }

                        // Source link
                        if let url = URL(string: recommendation.listing.sourceUrl) {
                            Link(destination: url) {
                                HStack {
                                    Spacer()
                                    Text("打开原始平台")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(16)
                }
            } else {
                // No selection
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("等待结果")
                        .font(.headline)
                    Text("点击「开始比较」后，这里会显示最优方案、费用拆分和路线明细。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func renderWarnings(_ warnings: [ResultWarning]) -> String {
        if warnings.contains(.crossCityPickup) {
            return "这是跨城取车方案，租车价格低，但需要额外关注高铁班次、门店营业时间和行李不便。"
        }
        return "该方案存在数据完整度提醒，建议打开原始平台复核。"
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let header: String?
    @ViewBuilder let content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = header {
                Text(header)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

// MARK: - Cost Line

struct CostLineView: View {
    let label: String
    let value: Double
    var bold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(bold ? .caption.bold() : .caption)
            Spacer()
            Text("¥\(value, specifier: "%.0f")")
                .font(bold ? .caption.bold() : .caption)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Route Box

struct RouteBoxView: View {
    let title: String
    let total: Double
    let summary: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("¥\(Int(total))")
                .font(.caption.bold())
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}
