import SwiftUI

struct ComparisonSelectionBar: View {
    @EnvironmentObject private var comparisonViewModel: ComparisonWorkspaceViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(comparisonViewModel.selectedRecommendations) { recommendation in
                HStack(spacing: 5) {
                    Text(recommendation.listing.vehicleName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Button {
                        comparisonViewModel.remove(id: recommendation.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除\(recommendation.listing.vehicleName)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(WorkbenchStyle.decisionBlue.opacity(0.10)))
            }

            Spacer(minLength: 8)

            Text("已选 \(comparisonViewModel.selectedRecommendations.count)/4")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)

            Button("开始对比") {
                comparisonViewModel.beginComparison()
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkbenchStyle.decisionBlue)
            .disabled(!comparisonViewModel.canBeginComparison)
            .help(comparisonViewModel.canBeginComparison ? "打开原位对比矩阵" : "至少选择两个候选")
        }
        .padding(10)
        .background(WorkbenchStyle.panelSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
        }
    }
}
