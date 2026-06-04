import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = AppDateRules.today
    @State private var returnDate = AppDateRules.addingDays(1, to: AppDateRules.today)
    @State private var showingEhiLogin = false
    @State private var originInputTask: Task<Void, Never>?

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
                            Task { await viewModel.refreshCurrentLocationIfNeeded() }
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
                OriginLocationField(originInputTask: $originInputTask)

                DateRangeField(pickupDate: $pickupDate, returnDate: $returnDate)
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

private struct OriginLocationField: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @Binding var originInputTask: Task<Void, Never>?

    var body: some View {
        FieldView(label: "当前位置") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(
                        "自动定位或输入地址",
                        text: Binding(
                            get: { viewModel.request.originLabel },
                            set: { value in
                                originInputTask?.cancel()
                                viewModel.request.originLabel = value
                                originInputTask = Task {
                                    try? await Task.sleep(nanoseconds: 280_000_000)
                                    guard !Task.isCancelled else { return }
                                    await viewModel.updateOriginInput(value)
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)

                    Button {
                        originInputTask?.cancel()
                        Task { await viewModel.refreshCurrentLocation() }
                    } label: {
                        if viewModel.isLocatingOrigin {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isLocatingOrigin)
                    .help("获取当前定位")
                }

                if viewModel.isLoadingOriginSuggestions {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在联想地址")
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                    }
                } else if !viewModel.originSuggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(viewModel.originSuggestions) { suggestion in
                            Button {
                                originInputTask?.cancel()
                                Task { await viewModel.selectOriginSuggestion(suggestion) }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(WorkbenchStyle.accent)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(WorkbenchStyle.ink)
                                            .lineLimit(1)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(WorkbenchStyle.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if suggestion.id != viewModel.originSuggestions.last?.id {
                                Divider()
                                    .padding(.leading, 33)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.035))
                    )
                } else if !viewModel.originStatus.isEmpty {
                    Text(viewModel.originStatus)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct DateRangeField: View {
    @Binding var pickupDate: Date
    @Binding var returnDate: Date

    private var rentalDays: Int {
        AppDateRules.rentalDaySpan(pickup: pickupDate, returnDate: returnDate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CalendarDateButton(
                title: "取车",
                date: $pickupDate,
                minimumDate: AppDateRules.today,
                accent: WorkbenchStyle.accent
            )

            DateRangeDurationBadge(days: rentalDays)

            CalendarDateButton(
                title: "还车",
                date: $returnDate,
                minimumDate: pickupDate,
                accent: WorkbenchStyle.teal
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CalendarDateButton: View {
    let title: String
    @Binding var date: Date
    let minimumDate: Date
    let accent: Color
    @State private var showingCalendar = false

    var body: some View {
        Button {
            showingCalendar = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2.weight(.bold))
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WorkbenchStyle.muted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AppDateRules.formatDisplayDate(date))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .monospacedDigit()
                    Text(AppDateRules.formatWeekday(date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(accent.opacity(0.28), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)日期 \(AppDateRules.formatDisplayDate(date)) \(AppDateRules.formatWeekday(date))")
        .popover(isPresented: $showingCalendar) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(title)日期")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)

                DatePicker(
                    "",
                    selection: $date,
                    in: minimumDate...,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .environment(\.calendar, AppDateRules.calendar)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .frame(width: 300)

                Divider()

                HStack {
                    Text("\(AppDateRules.formatDisplayDate(date)) \(AppDateRules.formatWeekday(date))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.muted)
                    Spacer()
                    Button("完成") {
                        showingCalendar = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .frame(width: 324)
        }
        .onChange(of: date) { _, newValue in
            let normalized = AppDateRules.calendar.startOfDay(for: newValue)
            if date != normalized {
                date = normalized
            }
        }
    }
}

private struct DateRangeDurationBadge: View {
    let days: Int

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
            Text("\(days)天")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(WorkbenchStyle.muted)
        .frame(width: 42, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.035))
        )
        .accessibilityLabel("租期 \(days) 天")
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
