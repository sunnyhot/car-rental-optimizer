import CarRentalDomain
import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("候选方案")
                    .font(.headline)
                Spacer()
                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if viewModel.isSearching {
                LoadingResultsView()
            } else if viewModel.results.isEmpty {
                EmptyResultsView(statuses: viewModel.platformStatuses)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            ResultRowView(
                                rank: index + 1,
                                recommendation: result,
                                isSelected: viewModel.selectedId == result.id
                            )
                            .contentShape(Rectangle())
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

private struct LoadingResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("正在比较")
                .font(.headline)
            Text("正在读取官方页面，并计算到店路线估算。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyResultsView: View {
    let statuses: [PlatformEvidenceStatus]

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("等待官方页面")
                .font(.headline)
            Text("没有可排序的官方车源时，这里不会显示推测价格。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(statuses) { status in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: statusIcon(status.kind))
                            .foregroundStyle(statusColor(status.kind))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.platform.label)
                                .font(.caption.bold())
                            Text(status.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: 360, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusIcon(_ kind: PlatformEvidenceStatusKind) -> String {
        switch kind {
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "calendar.badge.exclamationmark"
        case .loginRequired:
            return "person.crop.circle.badge.exclamationmark"
        case .captchaRequired:
            return "shield.lefthalf.filled"
        case .parseFailed:
            return "exclamationmark.triangle.fill"
        case .waitingForEvidence:
            return "clock"
        }
    }

    private func statusColor(_ kind: PlatformEvidenceStatusKind) -> Color {
        switch kind {
        case .ready:
            return .green
        case .unavailable:
            return .orange
        case .loginRequired, .captchaRequired:
            return .yellow
        case .parseFailed:
            return .red
        case .waitingForEvidence:
            return .secondary
        }
    }
}

private struct ResultRowView: View {
    let rank: Int
    let recommendation: Recommendation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.title2.bold())
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

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
                    CostBadge(title: "打车估", value: recommendation.taxiTotal, highlight: false)
                    CostBadge(title: "公交估", value: recommendation.transitTotal, highlight: false)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

private struct CostBadge: View {
    let title: String
    let value: Double
    let highlight: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatMoney(value))
                .font(highlight ? .caption.bold() : .caption)
                .foregroundStyle(highlight ? .primary : .secondary)
        }
    }
}
