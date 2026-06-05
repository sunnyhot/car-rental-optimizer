import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = AppDateRules.today
    @State private var returnDate = AppDateRules.addingDays(1, to: AppDateRules.today)
    @State private var showingEhiLogin = false
    @State private var originInputTask: Task<Void, Never>?
    @State private var originInputDismissRequest = 0

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
                dismissOriginInput()
                if returnDate < newValue {
                    returnDate = newValue
                }
                viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
            }
            .onChange(of: returnDate) { _, _ in
                dismissOriginInput()
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
                OriginLocationField(
                    originInputTask: $originInputTask,
                    dismissRequest: originInputDismissRequest
                )

                DateRangeField(
                    pickupDate: $pickupDate,
                    returnDate: $returnDate
                ) {
                    dismissOriginInput()
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
            dismissOriginInput()
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

    private func dismissOriginInput() {
        originInputTask?.cancel()
        originInputDismissRequest += 1
        viewModel.dismissOriginSuggestions()
    }
}

private struct OriginLocationField: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @Binding var originInputTask: Task<Void, Never>?
    let dismissRequest: Int
    @FocusState private var isOriginFieldFocused: Bool
    @State private var isEditingOrigin = false

    private var shouldShowSuggestionPanel: Bool {
        isEditingOrigin
            && isOriginFieldFocused
            && viewModel.isOriginSuggestionPanelVisible
            && (viewModel.isLoadingOriginSuggestions || !viewModel.originSuggestions.isEmpty)
    }

    var body: some View {
        FieldView(label: "当前位置") {
            VStack(alignment: .leading, spacing: 8) {
                originInputRow

                if shouldShowSuggestionPanel {
                    OriginSuggestionDropdown(
                        isLoading: viewModel.isLoadingOriginSuggestions,
                        suggestions: viewModel.originSuggestions
                    ) { suggestion in
                        closeEditor()
                        Task { await viewModel.selectOriginSuggestion(suggestion) }
                    }
                }

                if !shouldShowSuggestionPanel && !viewModel.originStatus.isEmpty {
                    Text(viewModel.originStatus)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: dismissRequest) { _, _ in
                closeEditor()
            }
        }
    }

    private var originInputRow: some View {
        HStack(spacing: 8) {
            TextField(
                "自动定位或输入地址",
                text: Binding(
                    get: { viewModel.request.originLabel },
                    set: { value in
                        originInputTask?.cancel()
                        isEditingOrigin = true
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
            .focused($isOriginFieldFocused)
            .onSubmit {
                closeEditor()
            }

            Button {
                closeEditor()
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
    }

    private func closeEditor() {
        originInputTask?.cancel()
        isEditingOrigin = false
        isOriginFieldFocused = false
        viewModel.dismissOriginSuggestions()
    }
}

private struct OriginSuggestionDropdown: View {
    let isLoading: Bool
    let suggestions: [AddressSuggestion]
    let onSelect: (AddressSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在联想地址")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.muted)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }

            if !suggestions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            suggestionButton(suggestion)

                            if suggestion.id != suggestions.last?.id {
                                Divider()
                                    .padding(.leading, 35)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WorkbenchStyle.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WorkbenchStyle.accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.13), radius: 14, x: 0, y: 8)
    }

    private func suggestionButton(_ suggestion: AddressSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(WorkbenchStyle.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.black.opacity(0.001))
    }
}

private struct DateRangeField: View {
    @Binding var pickupDate: Date
    @Binding var returnDate: Date
    let onCalendarOpen: () -> Void
    @State private var showingRangePicker = false
    @State private var focusedEndpoint: DateRangeEndpoint = .pickup

    private var rentalDays: Int {
        AppDateRules.rentalDaySpan(pickup: pickupDate, returnDate: returnDate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CalendarDateCard(
                title: "取车",
                date: pickupDate,
                accent: WorkbenchStyle.accent,
                isActive: showingRangePicker && focusedEndpoint == .pickup
            ) {
                openRangePicker(.pickup)
            }

            DateRangeDurationBadge(days: rentalDays)

            CalendarDateCard(
                title: "还车",
                date: returnDate,
                accent: WorkbenchStyle.teal,
                isActive: showingRangePicker && focusedEndpoint == .return
            ) {
                openRangePicker(.return)
            }
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showingRangePicker, arrowEdge: .bottom) {
            DateRangePickerPopover(
                pickupDate: $pickupDate,
                returnDate: $returnDate,
                focusedEndpoint: $focusedEndpoint
            ) {
                showingRangePicker = false
            }
        }
        .onChange(of: pickupDate) { _, _ in
            normalizeRange()
        }
        .onChange(of: returnDate) { _, _ in
            normalizeRange()
        }
    }

    private func openRangePicker(_ endpoint: DateRangeEndpoint) {
        onCalendarOpen()
        focusedEndpoint = endpoint
        showingRangePicker = true
    }

    private func normalizeRange() {
        let normalized = AppDateRules.normalizedRange(pickup: pickupDate, returnDate: returnDate)
        if pickupDate != normalized.pickup {
            pickupDate = normalized.pickup
        }
        if returnDate != normalized.returnDate {
            returnDate = normalized.returnDate
        }
    }
}

private enum DateRangeEndpoint: String, CaseIterable {
    case pickup = "取车"
    case `return` = "还车"
}

private struct CalendarDateCard: View {
    let title: String
    let date: Date
    let accent: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2.weight(.bold))
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isActive ? accent : WorkbenchStyle.muted)
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
                    .fill(accent.opacity(isActive ? 0.14 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(accent.opacity(isActive ? 0.55 : 0.28), lineWidth: isActive ? 1.5 : 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)日期 \(AppDateRules.formatDisplayDate(date)) \(AppDateRules.formatWeekday(date))")
    }
}

private struct DateRangePickerPopover: View {
    @Binding var pickupDate: Date
    @Binding var returnDate: Date
    @Binding var focusedEndpoint: DateRangeEndpoint
    let onDone: () -> Void

    private var rentalDays: Int {
        AppDateRules.rentalDaySpan(pickup: pickupDate, returnDate: returnDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("选择租期")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text("取车和还车日期联动，不能选择过去日期。")
                        .font(.caption)
                        .foregroundStyle(WorkbenchStyle.muted)
                }

                Spacer()

                Button("完成") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(WorkbenchStyle.accent)
            }
            .padding(16)
            .background(WorkbenchStyle.surface)

            Divider()

            HStack(spacing: 10) {
                rangeSummaryButton(endpoint: .pickup, title: "取车", date: pickupDate, accent: WorkbenchStyle.accent)
                DateRangeDurationBadge(days: rentalDays)
                rangeSummaryButton(endpoint: .return, title: "还车", date: returnDate, accent: WorkbenchStyle.teal)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 14) {
                LinkedCalendarColumn(
                    title: "取车日期",
                    date: Binding(
                        get: { pickupDate },
                        set: { newValue in
                            let normalized = AppDateRules.calendar.startOfDay(for: newValue)
                            pickupDate = normalized
                            if returnDate < normalized {
                                returnDate = normalized
                            }
                            focusedEndpoint = .return
                        }
                    ),
                    minimumDate: AppDateRules.today,
                    accent: WorkbenchStyle.accent,
                    isActive: focusedEndpoint == .pickup
                )

                LinkedCalendarColumn(
                    title: "还车日期",
                    date: Binding(
                        get: { returnDate },
                        set: { newValue in
                            returnDate = max(
                                AppDateRules.calendar.startOfDay(for: newValue),
                                AppDateRules.calendar.startOfDay(for: pickupDate)
                            )
                            focusedEndpoint = .return
                        }
                    ),
                    minimumDate: pickupDate,
                    accent: WorkbenchStyle.teal,
                    isActive: focusedEndpoint == .return
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 690)
        .environment(\.calendar, AppDateRules.calendar)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private func rangeSummaryButton(endpoint: DateRangeEndpoint, title: String, date: Date, accent: Color) -> some View {
        Button {
            focusedEndpoint = endpoint
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.muted)
                    Text("\(AppDateRules.formatDisplayDate(date)) \(AppDateRules.formatWeekday(date))")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(focusedEndpoint == endpoint ? 0.14 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(accent.opacity(focusedEndpoint == endpoint ? 0.48 : 0.18), lineWidth: focusedEndpoint == endpoint ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LinkedCalendarColumn: View {
    let title: String
    @Binding var date: Date
    let minimumDate: Date
    let accent: Color
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                Spacer()
            }

            DatePicker(
                "",
                selection: $date,
                in: minimumDate...,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .frame(width: 314)
            .frame(minHeight: 318)
        }
        .padding(12)
        .frame(width: 326, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? accent.opacity(0.08) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? accent.opacity(0.35) : WorkbenchStyle.line, lineWidth: 1)
        )
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
