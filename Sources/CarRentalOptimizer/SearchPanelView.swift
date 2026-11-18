import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = AppDateRules.today
    @State private var returnDate = AppDateRules.addingDays(1, to: AppDateRules.today)
    @State private var showingEhiLogin = false
    @State private var showingCarIncLogin = false

    var body: some View {
        WorkbenchPanel(
            title: "行程配置",
            subtitle: "行程 → 车辆 → 平台",
            trailing: AnyView(
                StatusPill(
                    text: "官方实时",
                    color: WorkbenchStyle.decisionBlue,
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
                            if !AppInfo.isUIValidation { Task { await viewModel.refreshCurrentLocationIfNeeded() } }
                        }
                }

                Rectangle()
                    .fill(WorkbenchStyle.line)
                    .frame(height: 1)

                StatusLightRail(isActive: viewModel.isSearching, tone: viewModel.hasBlockingPreflightIssues ? .warning : .active)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Text(viewModel.hasBlockingPreflightIssues ? "修正上方阻断项后可开始" : "将读取官方报价并计算到店成本")
                    .font(.caption2)
                    .foregroundStyle(viewModel.hasBlockingPreflightIssues ? WorkbenchStyle.riskAmber : WorkbenchStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                compareButton
                    .padding(16)
                    .background(WorkbenchStyle.panelSurface)
            }
            .onChange(of: pickupDate) { _, _ in
                viewModel.dismissVehicleSuggestions()
                viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
            }
            .onChange(of: returnDate) { _, _ in
                viewModel.dismissVehicleSuggestions()
                viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
            }
            .onChange(of: viewModel.request) { _, _ in
                viewModel.refreshPreflightIssues()
            }
            .sheet(isPresented: $showingEhiLogin) {
                EhiLoginSheet {
                    Task { await viewModel.runSearch() }
                }
            }
            .sheet(isPresented: $showingCarIncLogin) {
                PlatformLoginSheet(platform: .carInc) {
                    Task { await viewModel.runSearch() }
                }
            }

            if !viewModel.preflightIssues.isEmpty {
                PreflightIssueList(issues: viewModel.preflightIssues)
            }
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            BlueprintRouteTrail(
                stops: [.active, .idle, .idle],
                activeIndex: viewModel.isSearching ? searchTrailIndex : nil
            )
            .padding(.horizontal, 4)

            QueryConsoleSection(step: "01", icon: "mappin.and.ellipse", title: "行程坐标") {
                CurrentLocationView()

                DateRangeField(pickupDate: $pickupDate, returnDate: $returnDate) {
                    viewModel.dismissVehicleSuggestions()
                }
            }

            QueryConsoleSection(step: "02", icon: "car", title: "车辆与范围") {
                VehicleSuggestionField()

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
                        ? "车型为空：查半径内最近有报价门店。"
                        : "车型已填写：半径内车型匹配。")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            QueryConsoleSection(step: "03", icon: "link", title: "报价平台") {
                HStack(spacing: 8) {
                    ForEach(PlatformId.allCases, id: \.self) { platform in
                        PlatformSignalToggleButton(
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
                            showLogin(for: platform)
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

    private var searchTrailIndex: Int {
        switch viewModel.searchProgressPhase {
        case .idle, .resolvingLocation: return 0
        case .queryingPlatforms: return 2
        case .rankingRoutes, .completed: return 2
        case .failed: return 0
        }
    }

    private var compareButton: some View {
        CompareCommandButton(
            isSearching: viewModel.isSearching,
            isDisabled: viewModel.isSearching || viewModel.hasBlockingPreflightIssues
        ) {
            viewModel.dismissVehicleSuggestions()
            Task { await viewModel.runSearch() }
        }
    }

    private func showLogin(for platform: PlatformId) {
        switch platform {
        case .ehi:
            showingEhiLogin = true
        case .carInc:
            showingCarIncLogin = true
        }
    }
}

private struct PreflightIssueList: View {
    let issues: [SearchPreflightIssue]

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.surface, padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    ActionStatusRow(
                        icon: issue.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                        title: issue.title,
                        message: issue.message,
                        tone: issue.severity == .blocking ? .critical : .warning
                    )
                }
            }
        }
    }
}

private struct VehicleSuggestionField: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @FocusState private var isVehicleFieldFocused: Bool
    @State private var isEditingVehicle = false

    private var shouldShowSuggestionPanel: Bool {
        isEditingVehicle
            && isVehicleFieldFocused
            && viewModel.isVehicleSuggestionPanelVisible
            && !viewModel.vehicleSuggestions.isEmpty
    }

    var body: some View {
        FieldView(label: "车型") {
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "瑞虎8 / SUV / 留空查最近门店",
                    text: Binding(
                        get: { viewModel.request.vehicleQuery },
                        set: { value in
                            isEditingVehicle = true
                            viewModel.request.vehicleQuery = value
                            viewModel.refreshVehicleSuggestions(for: value)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isVehicleFieldFocused)
                .onSubmit {
                    closeSuggestions()
                }
                .onChange(of: isVehicleFieldFocused) { _, focused in
                    if focused {
                        isEditingVehicle = true
                        viewModel.refreshVehicleSuggestions(for: viewModel.request.vehicleQuery)
                    } else {
                        closeSuggestions()
                    }
                }

                if shouldShowSuggestionPanel {
                    VehicleSuggestionDropdown(suggestions: viewModel.vehicleSuggestions) { suggestion in
                        viewModel.selectVehicleSuggestion(suggestion)
                        closeSuggestions()
                    }
                }
            }
        }
    }

    private func closeSuggestions() {
        isEditingVehicle = false
        isVehicleFieldFocused = false
        viewModel.dismissVehicleSuggestions()
    }
}

private struct VehicleSuggestionDropdown: View {
    let suggestions: [VehicleSuggestion]
    let onSelect: (VehicleSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                suggestionButton(suggestion)

                if suggestion.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, 35)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WorkbenchStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(WorkbenchStyle.commandBlue.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: WorkbenchStyle.cardShadow.opacity(0.62), radius: 14, x: 0, y: 8)
        )
    }

    private func suggestionButton(_ suggestion: VehicleSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "car.fill")
                    .foregroundStyle(WorkbenchStyle.accent)
                    .frame(width: 18)

                Text(suggestion.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(suggestion.sourceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.black.opacity(0.001))
    }
}

private struct QueryConsoleSection<Content: View>: View {
    let step: String
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(icon: icon, title: title, step: step)
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
            }
        }
    }
}

private struct PlatformSignalToggleButton: View {
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
            .foregroundStyle(isSelected ? WorkbenchStyle.commandBlue : WorkbenchStyle.muted)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? WorkbenchStyle.commandBlue.opacity(0.12) : WorkbenchStyle.quietFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? WorkbenchStyle.commandBlue.opacity(0.46) : WorkbenchStyle.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(platform.label)平台")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }
}

private struct CompareCommandButton: View {
    let isSearching: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Spacer()
                if isSearching {
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
            .frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(WorkbenchStyle.commandBlue)
        .disabled(isDisabled)
        .accessibilityHint(isDisabled ? "搜索条件存在阻断项" : "读取所选平台的真实报价")
        .animation(WorkbenchStyle.motionFast, value: isSearching)
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

                Group {
                    Button {
                        loginAction()
                    } label: {
                        Label(loginButtonTitle(for: platform), systemImage: "person.badge.key.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isSearching)
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

    private func loginButtonTitle(for platform: PlatformId) -> String {
        switch platform {
        case .ehi:
            return "登录一嗨核价"
        case .carInc:
            return "登录神州核价"
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
