import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = Date()
    @State private var returnDate = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Panel header
                HStack {
                    Text("搜索条件")
                        .font(.headline)
                    Spacer()
                    Text("默认 100km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Current location
                FieldView(label: "当前位置") {
                    TextField("位置", text: $viewModel.request.originLabel)
                        .textFieldStyle(.roundedBorder)
                }

                // Pickup / Return dates
                HStack(spacing: 10) {
                    FieldView(label: "取车时间") {
                        DatePicker("", selection: $pickupDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .onChange(of: pickupDate) { _, newValue in
                                viewModel.request.pickupAt = formatDateTime(newValue)
                            }
                    }
                    FieldView(label: "还车时间") {
                        DatePicker("", selection: $returnDate, in: pickupDate..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .onChange(of: returnDate) { _, newValue in
                                viewModel.request.returnAt = formatDateTime(newValue)
                            }
                    }
                }

                // Vehicle query
                FieldView(label: "车型") {
                    TextField("瑞虎8", text: $viewModel.request.vehicleQuery)
                        .textFieldStyle(.roundedBorder)
                }

                // Radius slider
                FieldView(label: "搜索半径：\(Int(viewModel.request.radiusKm)) km") {
                    Slider(value: $viewModel.request.radiusKm, in: 10...500, step: 10)
                }

                // Return mode
                FieldView(label: "还车方式") {
                    Picker("", selection: $viewModel.request.returnMode) {
                        ForEach(ReturnMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Platform toggles
                VStack(alignment: .leading, spacing: 6) {
                    Text("平台选择")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(PlatformId.allCases, id: \.self) { platform in
                            Toggle(platform.label, isOn: Binding(
                                get: { viewModel.request.platforms.contains(platform) },
                                set: { _ in viewModel.togglePlatform(platform) }
                            ))
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .tint(viewModel.request.platforms.contains(platform) ? .blue : .gray)
                        }
                    }
                }

                // Platform login state
                VStack(alignment: .leading, spacing: 8) {
                    Text("平台登录态")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(PlatformId.allCases, id: \.self) { platform in
                        PlatformLoginRow(platform: platform)
                    }
                }
                .padding(.vertical, 4)

                // Search button
                Button {
                    Task { await viewModel.runSearch() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSearching {
                            ProgressView()
                                .controlSize(.small)
                            Text("查询中...")
                        } else {
                            Text("开始比较")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isSearching)

                // Notice
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mock 数据说明")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("当前使用 Mock 车源数据。点击「开始比较」将展示基于模拟数据的排序结果。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(16)
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Field Wrapper

struct FieldView<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: - Platform Login Row

struct PlatformLoginRow: View {
    let platform: PlatformId
    @EnvironmentObject var viewModel: SearchViewModel

    var body: some View {
        let authState = viewModel.platformSession.authStates.first { $0.platform == platform }

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.label)
                    .font(.caption)
                Text(authState?.hasCookies == true ? "已保存 \(authState?.cookieCount ?? 0) 个 Cookie" : "未检测到 Cookie")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开/登录") {
                Task { await viewModel.openPlatform(platform) }
            }
            .controlSize(.small)
            Button("清除") {
                Task { await viewModel.clearPlatform(platform) }
            }
            .controlSize(.small)
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
}
