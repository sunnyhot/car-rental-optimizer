import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = AppDateRules.today
    @State private var returnDate = AppDateRules.addingDays(1, to: AppDateRules.today)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("搜索条件")
                        .font(.headline)
                    Spacer()
                    Text("真实证据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                FieldView(label: "当前位置") {
                    TextField("位置", text: $viewModel.request.originLabel)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    FieldView(label: "取车日期") {
                        DatePicker("", selection: $pickupDate, in: AppDateRules.today..., displayedComponents: [.date])
                            .labelsHidden()
                    }

                    FieldView(label: "还车日期") {
                        DatePicker("", selection: $returnDate, in: pickupDate..., displayedComponents: [.date])
                            .labelsHidden()
                    }
                }
                .onChange(of: pickupDate) { _, newValue in
                    if returnDate < newValue {
                        returnDate = newValue
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
                    Text("平台与官方页面")
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

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.request.platforms, id: \.self) { platform in
                        PlatformEvidenceEditor(platform: platform)
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

                Spacer(minLength: 0)
            }
            .padding(16)
            .onAppear {
                pickupDate = AppDateRules.parseRequestDate(viewModel.request.pickupAt) ?? AppDateRules.today
                returnDate = AppDateRules.parseRequestDate(viewModel.request.returnAt) ?? AppDateRules.addingDays(1, to: pickupDate)
                viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
            }
        }
    }
}

private struct PlatformEvidenceEditor: View {
    @EnvironmentObject var viewModel: SearchViewModel
    let platform: PlatformId

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(kind: viewModel.platformStatus(for: platform).kind)
                Text(platform.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if let url = URL(string: officialPlatformURL(for: platform)) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开\(platform.label)官方页面")
                }
            }

            Text(viewModel.platformStatus(for: platform).message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            TextEditor(text: Binding(
                get: { viewModel.evidenceText(for: platform) },
                set: { viewModel.updateEvidenceText($0, for: platform) }
            ))
            .font(.caption)
            .frame(minHeight: 82)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .cornerRadius(5)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}

private struct StatusDot: View {
    let kind: PlatformEvidenceStatusKind

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
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
            return .gray
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
