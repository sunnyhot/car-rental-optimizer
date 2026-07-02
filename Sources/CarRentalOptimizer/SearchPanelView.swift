import CarRentalDomain
import SwiftUI

struct SearchPanelView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @State private var pickupDate = AppDateRules.today
    @State private var returnDate = AppDateRules.addingDays(1, to: AppDateRules.today)
    @State private var showingEhiLogin = false
    @State private var showingCarIncLogin = false
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

                StatusLightRail(isActive: viewModel.isSearching, tone: viewModel.hasBlockingPreflightIssues ? .warning : .active)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                compareButton
                    .padding(16)
                    .background(WorkbenchStyle.panelSurface)
            }
            .onChange(of: pickupDate) { _, newValue in
                dismissOriginInput()
                viewModel.dismissVehicleSuggestions()
                if returnDate < newValue {
                    returnDate = newValue
                }
                viewModel.applyDates(pickup: pickupDate, returnDate: returnDate)
            }
            .onChange(of: returnDate) { _, _ in
                dismissOriginInput()
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
            QueryConsoleSection(icon: "mappin.and.ellipse", title: "行程") {
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

            QueryConsoleSection(icon: "car", title: "车辆与范围") {
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

            QueryConsoleSection(icon: "arrow.triangle.2.circlepath", title: "取还规则") {
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

            QueryConsoleSection(icon: "link", title: "平台") {
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

    private var compareButton: some View {
        CompareCommandButton(
            isSearching: viewModel.isSearching,
            isDisabled: viewModel.isSearching || viewModel.hasBlockingPreflightIssues
        ) {
            dismissOriginInput()
            viewModel.dismissVehicleSuggestions()
            Task { await viewModel.runSearch() }
        }
    }

    private func dismissOriginInput() {
        originInputTask?.cancel()
        originInputDismissRequest += 1
        viewModel.dismissOriginSuggestions()
        viewModel.dismissVehicleSuggestions()
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
                .fill(WorkbenchStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(WorkbenchStyle.commandBlue.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: WorkbenchStyle.cardShadow.opacity(0.62), radius: 14, x: 0, y: 8)
        )
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
    @State private var visibleMonth = AppDateRules.monthStart(containing: AppDateRules.today)

    private var rentalDays: Int {
        AppDateRules.rentalDaySpan(pickup: pickupDate, returnDate: returnDate)
    }

    private var trailingMonth: Date {
        AppDateRules.month(byAdding: 1, to: visibleMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                rangeSummaryButton(endpoint: .pickup, title: "取车", date: pickupDate, accent: WorkbenchStyle.accent)
                DateRangeDurationBadge(days: rentalDays)
                rangeSummaryButton(endpoint: .return, title: "还车", date: returnDate, accent: WorkbenchStyle.teal)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(WorkbenchStyle.surface)

            Divider()

            HStack(alignment: .top, spacing: 18) {
                DateRangeCalendarMonthView(
                    month: visibleMonth,
                    pickupDate: pickupDate,
                    returnDate: returnDate,
                    minimumDate: AppDateRules.today,
                    focusedEndpoint: focusedEndpoint,
                    showsLeadingNavigation: true,
                    showsTrailingNavigation: false,
                    onMonthChange: moveVisibleMonth,
                    onSelect: selectDate
                )

                Divider()

                DateRangeCalendarMonthView(
                    month: trailingMonth,
                    pickupDate: pickupDate,
                    returnDate: returnDate,
                    minimumDate: AppDateRules.today,
                    focusedEndpoint: focusedEndpoint,
                    showsLeadingNavigation: false,
                    showsTrailingNavigation: true,
                    onMonthChange: moveVisibleMonth,
                    onSelect: selectDate
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            Divider()

            HStack {
                Button("清除已选") {
                    resetSelection()
                }
                .buttonStyle(.plain)
                .foregroundStyle(WorkbenchStyle.accent)

                Spacer()

                Button("完成") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(WorkbenchStyle.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(WorkbenchStyle.surface)
        }
        .frame(width: 666)
        .environment(\.calendar, AppDateRules.calendar)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onAppear {
            visibleMonth = AppDateRules.monthStart(containing: pickupDate)
        }
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

    private func moveVisibleMonth(by months: Int) {
        visibleMonth = AppDateRules.month(byAdding: months, to: visibleMonth)
    }

    private func selectDate(_ date: Date) {
        let normalized = AppDateRules.calendar.startOfDay(for: date)
        guard normalized >= AppDateRules.today else { return }

        switch focusedEndpoint {
        case .pickup:
            pickupDate = normalized
            if returnDate < normalized {
                returnDate = normalized
            }
            focusedEndpoint = .return
        case .return:
            if normalized < pickupDate {
                pickupDate = normalized
                returnDate = normalized
            } else {
                returnDate = normalized
            }
            focusedEndpoint = .return
        }
    }

    private func resetSelection() {
        let today = AppDateRules.today
        pickupDate = today
        returnDate = AppDateRules.addingDays(1, to: today)
        focusedEndpoint = .pickup
        visibleMonth = AppDateRules.monthStart(containing: today)
    }
}

private struct DateRangeCalendarMonthView: View {
    let month: Date
    let pickupDate: Date
    let returnDate: Date
    let minimumDate: Date
    let focusedEndpoint: DateRangeEndpoint
    let showsLeadingNavigation: Bool
    let showsTrailingNavigation: Bool
    let onMonthChange: (Int) -> Void
    let onSelect: (Date) -> Void

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            monthHeader

            HStack(spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.muted)
                        .frame(width: 34)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppDateRules.monthGrid(containing: month), id: \.self) { day in
                    DateRangeCalendarDayButton(
                        date: day,
                        displayMonth: month,
                        pickupDate: pickupDate,
                        returnDate: returnDate,
                        minimumDate: minimumDate,
                        focusedEndpoint: focusedEndpoint
                    ) {
                        onSelect(day)
                    }
                }
            }
        }
        .frame(width: 274, alignment: .top)
    }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            if showsLeadingNavigation {
                monthButton(systemImage: "chevron.left.2", offset: -12, help: "上一年")
                monthButton(systemImage: "chevron.left", offset: -1, help: "上个月")
            } else {
                Color.clear
                    .frame(width: 54, height: 24)
            }

            Spacer(minLength: 8)

            Text(AppDateRules.monthTitle(for: month))
                .font(.title3.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
                .monospacedDigit()

            Spacer(minLength: 8)

            if showsTrailingNavigation {
                monthButton(systemImage: "chevron.right", offset: 1, help: "下个月")
                monthButton(systemImage: "chevron.right.2", offset: 12, help: "下一年")
            } else {
                Color.clear
                    .frame(width: 54, height: 24)
            }
        }
        .frame(height: 34)
    }

    private func monthButton(systemImage: String, offset: Int, help: String) -> some View {
        Button {
            onMonthChange(offset)
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(WorkbenchStyle.ink)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DateRangeCalendarDayButton: View {
    let date: Date
    let displayMonth: Date
    let pickupDate: Date
    let returnDate: Date
    let minimumDate: Date
    let focusedEndpoint: DateRangeEndpoint
    let action: () -> Void

    private var dayNumber: Int {
        AppDateRules.calendar.component(.day, from: date)
    }

    private var normalizedDate: Date {
        AppDateRules.calendar.startOfDay(for: date)
    }

    private var normalizedPickup: Date {
        AppDateRules.calendar.startOfDay(for: pickupDate)
    }

    private var normalizedReturn: Date {
        AppDateRules.calendar.startOfDay(for: returnDate)
    }

    private var isInDisplayedMonth: Bool {
        AppDateRules.calendar.isDate(date, equalTo: displayMonth, toGranularity: .month)
    }

    private var isDisabled: Bool {
        normalizedDate < AppDateRules.calendar.startOfDay(for: minimumDate)
    }

    private var isPickup: Bool {
        AppDateRules.calendar.isDate(normalizedDate, inSameDayAs: normalizedPickup)
    }

    private var isReturn: Bool {
        AppDateRules.calendar.isDate(normalizedDate, inSameDayAs: normalizedReturn)
    }

    private var isSelected: Bool {
        isPickup || isReturn
    }

    private var isInRange: Bool {
        normalizedDate >= normalizedPickup && normalizedDate <= normalizedReturn
    }

    private var isToday: Bool {
        AppDateRules.calendar.isDateInToday(date)
    }

    private var selectionColor: Color {
        isReturn && !isPickup ? WorkbenchStyle.teal : WorkbenchStyle.accent
    }

    private var textColor: Color {
        if isDisabled {
            return WorkbenchStyle.muted.opacity(0.32)
        }
        if isSelected {
            return .white
        }
        if isInDisplayedMonth {
            return WorkbenchStyle.ink
        }
        return WorkbenchStyle.muted.opacity(0.46)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isInRange && !isSelected ? WorkbenchStyle.accent.opacity(0.12) : Color.clear)
                    .frame(width: 34, height: 30)

                Circle()
                    .fill(isSelected ? selectionColor : Color.clear)
                    .frame(width: 30, height: 30)

                Circle()
                    .stroke(isToday && !isSelected ? WorkbenchStyle.accent.opacity(0.42) : Color.clear, lineWidth: 1)
                    .frame(width: 30, height: 30)

                Text("\(dayNumber)")
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
            }
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isInDisplayedMonth ? 1 : 0.72)
        .accessibilityLabel(accessibilityLabel)
        .help(focusedEndpoint.rawValue)
    }

    private var accessibilityLabel: String {
        "\(AppDateRules.formatDisplayDate(date)) \(AppDateRules.formatWeekday(date))"
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
                .fill(WorkbenchStyle.quietFill)
        )
        .accessibilityLabel("租期 \(days) 天")
    }
}

private struct QueryConsoleSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(WorkbenchStyle.signalTeal)
                        .frame(width: 18)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Spacer()
                }

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

                if status.kind == .loginRequired {
                    Button {
                        loginAction()
                    } label: {
                        Label(loginButtonTitle(for: platform), systemImage: "person.badge.key.fill")
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

    private func loginButtonTitle(for platform: PlatformId) -> String {
        switch platform {
        case .ehi:
            return "登录一嗨"
        case .carInc:
            return "登录神州补费用"
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
