import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = Date(timeIntervalSince1970: 1_780_623_600)
    @State private var returnDate = Date(timeIntervalSince1970: 1_780_828_400)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("搜索条件")
                        .font(.headline)
                    Spacer()
                    Text("默认 100km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                FieldView(label: "当前位置") {
                    TextField("位置", text: $viewModel.request.originLabel)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    FieldView(label: "取车时间") {
                        DatePicker("", selection: $pickupDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }

                    FieldView(label: "还车时间") {
                        DatePicker("", selection: $returnDate, in: pickupDate..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }
                .onChange(of: pickupDate) { _, newValue in
                    if returnDate < newValue {
                        returnDate = newValue.addingTimeInterval(24 * 60 * 60)
                    }
                    viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
                }
                .onChange(of: returnDate) { _, _ in
                    viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
                }

                FieldView(label: "车型") {
                    TextField("瑞虎8", text: $viewModel.request.vehicleQuery)
                        .textFieldStyle(.roundedBorder)
                }

                FieldView(label: "搜索半径：\(Int(viewModel.request.radiusKm)) km") {
                    Slider(value: $viewModel.request.radiusKm, in: 10...500, step: 10)
                }

                FieldView(label: "还车方式") {
                    Picker("", selection: $viewModel.request.returnMode) {
                        ForEach(ReturnMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mock 数据说明")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("当前版本使用内置模拟车源和路线成本，点击「开始比较」即可得到完整排序结果。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

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
