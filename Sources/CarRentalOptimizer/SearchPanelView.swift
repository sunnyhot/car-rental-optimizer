import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = AppDateRules.today
    @State private var returnDate = AppDateRules.addingDays(1, to: AppDateRules.today)
    @State private var showingEhiLogin = false

    var body: some View {
        WorkbenchPanel(
            title: "查询控制台",
            subtitle: "真实车源 + 到店成本",
            trailing: AnyView(
                StatusPill(
                    text: "静默 API",
                    color: WorkbenchStyle.accent,
                    systemImage: "bolt.horizontal.circle.fill"
                )
            )
        ) {
            VStack(spacing: 0) {
                ScrollView {
                    searchControls
                        .padding(16)
                        .onAppear {
                            pickupDate = AppDateRules.parseRequestDate(viewModel.request.pickupAt) ?? AppDateRules.today
                            returnDate = AppDateRules.parseRequestDate(viewModel.request.returnAt) ?? AppDateRules.addingDays(1, to: pickupDate)
                            viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
                        }
                }

                Rectangle()
                    .fill(WorkbenchStyle.line)
                    .frame(height: 1)

                compareButton
                    .padding(16)
                    .background(WorkbenchStyle.panel)
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
            .sheet(isPresented: $showingEhiLogin) {
                EhiLoginSheet {
                    Task { await viewModel.runSearch() }
                }
            }
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuerySection(icon: "mappin.and.ellipse", title: "行程") {
                FieldView(label: "当前位置") {
                    TextField("北京通州", text: $viewModel.request.originLabel)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }

                HStack(alignment: .top, spacing: 10) {
                    FieldView(label: "取车日期") {
                        DatePicker(
                            "",
                            selection: $pickupDate,
                            in: AppDateRules.today...,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }

                    FieldView(label: "还车日期") {
                        DatePicker(
                            "",
                            selection: $returnDate,
                            in: pickupDate...,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                }
            }

            QuerySection(icon: "car", title: "车辆与范围") {
                FieldView(label: "车型") {
                    TextField("瑞虎8 / SUV / 留空查最近门店", text: $viewModel.request.vehicleQuery)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("搜索半径")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.muted)
                        Spacer()
                        Text("\(Int(viewModel.request.radiusKm)) km")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                            .monospacedDigit()
                    }

                    Slider(value: $viewModel.request.radiusKm, in: 10...500, step: 10)

                    Text(viewModel.request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "车型为空：最近门店模式，半径不参与筛选。"
                        : "车型已填写：半径内车型匹配。")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            QuerySection(icon: "arrow.triangle.2.circlepath", title: "取还规则") {
                FieldView(label: "还车方式") {
                    Picker("", selection: $viewModel.request.returnMode) {
                        ForEach(ReturnMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            QuerySection(icon: "link", title: "平台") {
                HStack(spacing: 8) {
                    ForEach(PlatformId.allCases, id: \.self) { platform in
                        PlatformToggleButton(
                            platform: platform,
                            isSelected: viewModel.request.platforms.contains(platform)
                        ) {
                            viewModel.togglePlatform(platform)
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.request.platforms.enumerated()), id: \.element) { index, platform in
                        PlatformStatusRow(platform: platform) {
                            showingEhiLogin = true
                        }

                        if index < viewModel.request.platforms.count - 1 {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }

    private var compareButton: some View {
        Button {
            Task { await viewModel.runSearch() }
        } label: {
            HStack(spacing: 8) {
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                    Text("查询中...")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text("开始比较")
                }
                Spacer()
            }
            .font(.headline.weight(.semibold))
            .frame(minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(WorkbenchStyle.accent)
        .disabled(viewModel.isSearching)
    }
}

private struct QuerySection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        SurfaceBox(padding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(WorkbenchStyle.accent)
                        .frame(width: 17)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct PlatformToggleButton: View {
    let platform: PlatformId
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                Text(platform.label)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? WorkbenchStyle.accentSoft : Color.black.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isSelected ? WorkbenchStyle.accent.opacity(0.35) : WorkbenchStyle.line)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlatformStatusRow: View {
    @EnvironmentObject var viewModel: SearchViewModel
    let platform: PlatformId
    let loginAction: () -> Void

    var body: some View {
        let status = viewModel.platformStatus(for: platform)

        HStack(alignment: .top, spacing: 9) {
            Image(systemName: WorkbenchStyle.statusIcon(status.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.statusColor(status.kind))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(platform.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Spacer()
                    Text(statusLabel(status.kind))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.statusColor(status.kind))
                }

                Text(status.message)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if platform == .ehi && status.kind == .loginRequired {
                    Button {
                        loginAction()
                    } label: {
                        Label("登录一嗨", systemImage: "person.badge.key.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func statusLabel(_ kind: PlatformEvidenceStatusKind) -> String {
        switch kind {
        case .ready:
            return "已获取"
        case .loginRequired:
            return "需登录"
        case .captchaRequired:
            return "需验证"
        case .unavailable:
            return "无车"
        case .parseFailed:
            return "失败"
        case .waitingForEvidence:
            return "等待"
        }
    }
}

struct FieldView<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)
            content
        }
    }
}
