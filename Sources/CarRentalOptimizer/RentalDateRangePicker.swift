import CarRentalDomain
import Foundation
import SwiftUI

struct DateRangeField: View {
    @Binding var pickupDate: Date
    @Binding var returnDate: Date
    let onCalendarOpen: () -> Void
    @State private var showingRangePicker = false
    @State private var focusedEndpoint: DateRangeEndpoint = .pickup
    @State private var draft = RentalDateTimeSelection(pickup: Date(), returnDate: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CalendarDateCard(title: "取车", date: pickupDate, accent: WorkbenchStyle.accent, isActive: showingRangePicker && focusedEndpoint == .pickup) { openRangePicker(.pickup) }
                CalendarDateCard(title: "还车", date: returnDate, accent: WorkbenchStyle.teal, isActive: showingRangePicker && focusedEndpoint == .return) { openRangePicker(.return) }
            }
            Text(RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).defaultTimeSummary)
                .font(.caption2).foregroundStyle(WorkbenchStyle.muted)
        }
        .popover(isPresented: $showingRangePicker, arrowEdge: .bottom) {
            DateRangePickerPopover(
                pickupDate: Binding(get: { draft.pickup }, set: { draft.pickup = $0 }),
                returnDate: Binding(get: { draft.returnDate }, set: { draft.returnDate = $0 }),
                focusedEndpoint: $focusedEndpoint,
                onDone: {
                    guard draft.validationMessage(now: Date()) == nil else { return }
                    pickupDate = draft.pickup
                    returnDate = draft.returnDate
                    showingRangePicker = false
                },
                onCancel: { showingRangePicker = false }
            )
        }
    }

    private func openRangePicker(_ endpoint: DateRangeEndpoint) {
        onCalendarOpen()
        draft = RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).applyingDefaultTimes(now: Date())
        focusedEndpoint = endpoint
        showingRangePicker = true
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

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppDateRules.formatRequestDate(date))
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
        .accessibilityLabel("\(title)日期 \(AppDateRules.formatRequestDate(date)) \(AppDateRules.formatWeekday(date))")
    }
}

private struct DateRangePickerPopover: View {
    @Binding var pickupDate: Date
    @Binding var returnDate: Date
    @Binding var focusedEndpoint: DateRangeEndpoint
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var visibleMonth = AppDateRules.monthStart(containing: AppDateRules.today)

    private var rentalDays: Int {
        RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).estimatedDays
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

            Text(RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).defaultTimeSummary)
                .font(.caption).foregroundStyle(WorkbenchStyle.muted)
                .padding(.horizontal, 16).padding(.bottom, 12)

            Divider()

            HStack(alignment: .top, spacing: 18) {
                DateRangeCalendarMonthView(
                    month: visibleMonth,
                    pickupDate: pickupDate,
                    returnDate: returnDate,
                    minimumDate: focusedEndpoint == .return ? max(AppDateRules.today, AppDateRules.calendar.startOfDay(for: pickupDate)) : AppDateRules.today,
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
                    minimumDate: focusedEndpoint == .return ? max(AppDateRules.today, AppDateRules.calendar.startOfDay(for: pickupDate)) : AppDateRules.today,
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

            if let message = RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).validationMessage(now: Date()) {
                Text(message).font(.caption).foregroundStyle(WorkbenchStyle.riskAmber)
                    .padding(.horizontal, 16).padding(.top, 10)
            } else {
                Text("先选取车日期，再选还车日期；修改仅在点击确定后生效。")
                    .font(.caption).foregroundStyle(WorkbenchStyle.muted)
                    .padding(.horizontal, 16).padding(.top, 10)
            }

            HStack {
                Button("回到本月") {
                    visibleMonth = AppDateRules.monthStart(containing: AppDateRules.today)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WorkbenchStyle.accent)

                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确定", action: onDone)
                    .disabled(RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).validationMessage(now: Date()) != nil)
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
            visibleMonth = AppDateRules.monthStart(containing: focusedEndpoint == .pickup ? pickupDate : max(pickupDate, returnDate))
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
                    Text("\(AppDateRules.formatRequestDate(date)) \(AppDateRules.formatWeekday(date))")
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
        visibleMonth = max(AppDateRules.monthStart(containing: AppDateRules.today), AppDateRules.month(byAdding: months, to: visibleMonth))
    }

    private func selectDate(_ date: Date) {
        let normalized = AppDateRules.calendar.startOfDay(for: date)
        guard normalized >= AppDateRules.today else { return }

        switch focusedEndpoint {
        case .pickup:
            pickupDate = RentalDateTimeSelection.replacingDay(of: pickupDate, with: normalized)
            focusedEndpoint = .return
        case .return:
            guard normalized >= AppDateRules.calendar.startOfDay(for: pickupDate) else { return }
            returnDate = RentalDateTimeSelection.replacingDay(of: returnDate, with: normalized)
        }
        let defaults = RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate).applyingDefaultTimes(now: Date())
        pickupDate = defaults.pickup
        returnDate = defaults.returnDate
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
        .accessibilityLabel(help)
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
        "\(AppDateRules.formatRequestDate(date)) \(AppDateRules.formatWeekday(date))"
    }
}

private struct DateRangeDurationBadge: View {
    let days: Int

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
            Text(days > 0 ? "约\(days)天" : "待选")
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
