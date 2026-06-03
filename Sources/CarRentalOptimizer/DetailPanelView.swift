import CarRentalDomain
import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        Group {
            if let recommendation = viewModel.selected {
                RecommendationDetailView(recommendation: recommendation)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("等待结果")
                        .font(.headline)
                    Text("读取到官方车源后，这里会显示费用拆分和路线估算。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct RecommendationDetailView: View {
    let recommendation: Recommendation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                VStack(spacing: 4) {
                    Text("推荐总成本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatMoney(recommendation.bestTotal))
                        .font(.system(size: 32, weight: .bold))
                    Text("按\(recommendation.bestRouteMode.label)到店估算")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)

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

                DetailSection(header: "费用拆分") {
                    VStack(spacing: 0) {
                        CostLineView(label: "平台返回租车价", value: recommendation.listing.basePrice)
                        CostLineView(label: "平台服务费", value: recommendation.listing.platformFees)
                        CostLineView(label: "保险/保障", value: recommendation.listing.insuranceFees)
                        CostLineView(label: "异店还车费", value: recommendation.listing.oneWayFee)
                        Divider()
                        CostLineView(label: "租车小计", value: recommendation.rentalTotal, bold: true)
                    }
                }

                HStack(spacing: 12) {
                    RouteBoxView(
                        title: "打车",
                        total: recommendation.taxiTotal,
                        route: recommendation.taxiRoute
                    )
                    RouteBoxView(
                        title: "公共交通",
                        total: recommendation.transitTotal,
                        route: recommendation.transitRoute
                    )
                }

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
    }
}

private struct DetailSection<Content: View>: View {
    let header: String?
    @ViewBuilder let content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

private struct CostLineView: View {
    let label: String
    let value: Double
    var bold = false

    var body: some View {
        HStack {
            Text(label)
                .font(bold ? .caption.bold() : .caption)
            Spacer()
            Text(formatMoney(value))
                .font(bold ? .caption.bold() : .caption)
        }
        .padding(.vertical, 3)
    }
}

private struct RouteBoxView: View {
    let title: String
    let total: Double
    let route: RouteEstimate

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatMoney(total))
                .font(.caption.bold())
            Text(route.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(route.distanceKm, specifier: "%.1f") km")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}
