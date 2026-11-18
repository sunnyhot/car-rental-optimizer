import SwiftUI

struct CurrentLocationView: View {
    @EnvironmentObject private var viewModel: SearchViewModel

    var body: some View {
        FieldView(label: "当前位置") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    if viewModel.isLocatingOrigin {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location.fill").foregroundStyle(WorkbenchStyle.muted)
                    }
                    Text(viewModel.currentLocationLabel)
                        .font(.callout)
                        .foregroundStyle(WorkbenchStyle.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("当前位置：\(viewModel.currentLocationLabel)")
                    Button {
                        Task { await viewModel.refreshCurrentLocation() }
                    } label: {
                        Label("重新定位", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(viewModel.isLocatingOrigin || viewModel.isSearching)
                    .help("重新获取系统当前位置")
                }
                if !viewModel.isCurrentLocationReady && !viewModel.isLocatingOrigin {
                    Text(viewModel.originStatus)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.riskAmber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
