import SwiftUI

/// Main content view — three-column layout matching the original Electron design.
/// Left: search parameters | Center: ranked results | Right: recommendation detail.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            // Left panel: Search Parameters (placeholder)
            SearchPanelView()
                .navigationTitle("搜索条件")
        } content: {
            // Center panel: Ranked Results (placeholder)
            ResultListView()
                .navigationTitle("候选方案")
        } detail: {
            // Right panel: Recommendation Detail (placeholder)
            DetailPanelView()
                .navigationTitle("推荐明细")
        }
        .frame(minWidth: 1120, minHeight: 720)
    }
}

// MARK: - Search Panel (Placeholder)

struct SearchPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("搜索条件")
                .font(.headline)

            LabeledContent("当前位置") {
                TextField("位置", text: .constant("北京通州"))
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("取车时间") {
                TextField("日期", text: .constant("2026-06-05 09:00"))
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("还车时间") {
                TextField("日期", text: .constant("2026-06-07 18:00"))
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("车型") {
                TextField("车型", text: .constant("瑞虎8"))
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("搜索半径") {
                Slider(value: .constant(100), in: 10...500, step: 10)
                Text("100 km").font(.caption)
            }

            LabeledContent("还车方式") {
                Picker("还车方式", selection: .constant(0)) {
                    Text("同店取还").tag(0)
                    Text("异店/异地还车").tag(1)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            Text("平台选择")
                .font(.subheadline.weight(.medium))

            HStack {
                Toggle("一嗨", isOn: .constant(true))
                Toggle("神州", isOn: .constant(true))
            }
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                // Placeholder: will trigger search in future tasks
            } label: {
                Label("开始比较", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("原生骨架占位：业务逻辑将在后续任务中迁移接入。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Result List (Placeholder)

struct ResultListView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "car.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("等待搜索结果")
                .font(.title2)

            Text("配置搜索条件后点击「开始比较」，\n候选租车方案将在此处展示。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("原生骨架占位界面")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail Panel (Placeholder)

struct DetailPanelView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("推荐明细")
                .font(.title2)

            Text("选择候选方案后，\n费用拆分和路线明细将在此处展示。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("原生骨架占位界面")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Content View") {
    ContentView()
}
