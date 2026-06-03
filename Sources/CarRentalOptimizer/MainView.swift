import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Car rental optimizer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppInfo.appName)
                        .font(.title2.bold())
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("真实数据工作流")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            HSplitView {
                SearchPanelView()
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)

                ResultPanelView()
                    .frame(minWidth: 360, idealWidth: 440)

                DetailPanelView()
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
