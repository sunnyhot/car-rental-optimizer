import CarRentalDomain
import SwiftUI
import WebKit

struct PlatformBrowserPanel: View {
    @EnvironmentObject var browserStore: PlatformBrowserStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("官方页面")
                    .font(.headline)

                Picker("", selection: $browserStore.selectedPlatform) {
                    ForEach(PlatformId.allCases, id: \.self) { platform in
                        Text(platform.label).tag(platform)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: browserStore.selectedPlatform) { _, platform in
                    browserStore.select(platform)
                }

                Spacer()

                let platform = browserStore.selectedPlatform
                Button {
                    browserStore.goBack(platform)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("后退")

                Button {
                    browserStore.goForward(platform)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("前进")

                Button {
                    browserStore.reload(platform)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")

                Button {
                    browserStore.loadHome(platform)
                } label: {
                    Image(systemName: "house")
                }
                .help("回到平台官网")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            let state = browserStore.state(for: browserStore.selectedPlatform)
            HStack(spacing: 8) {
                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(state.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(state.url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(state.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Divider()

            PlatformWebView(store: browserStore, platform: browserStore.selectedPlatform)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PlatformWebView: NSViewRepresentable {
    @ObservedObject var store: PlatformBrowserStore
    let platform: PlatformId

    func makeNSView(context: Context) -> WKWebView {
        store.webView(for: platform)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        _ = store.webView(for: platform)
    }
}
