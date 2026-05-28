import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Car rental optimizer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("租车总成本比较")
                        .font(.title2.bold())
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("本地登录态自动化架构")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Workspace: three-panel layout
            HSplitView {
                // Left: Search Panel
                SearchPanelView()
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

                // Center: Result Panel
                ResultPanelView()
                    .frame(minWidth: 360, idealWidth: 440)

                // Right: Detail Panel
                DetailPanelView()
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
            }
            .padding(.horizontal, 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
