import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("AppDateRules")
struct AppDateRulesTests {
    @Test("Date display uses compact Chinese calendar labels")
    func dateDisplayUsesCompactChineseCalendarLabels() {
        let date = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 4))!

        #expect(AppDateRules.formatDisplayDate(date) == "6月4日")
        #expect(AppDateRules.formatWeekday(date) == "周四")
    }

    @Test("Rental day span never drops below one day")
    func rentalDaySpanNeverDropsBelowOneDay() {
        let pickup = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 4))!
        let nextDay = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 5))!
        let sameDay = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 4))!

        #expect(AppDateRules.rentalDaySpan(pickup: pickup, returnDate: nextDay) == 1)
        #expect(AppDateRules.rentalDaySpan(pickup: pickup, returnDate: sameDay) == 1)
    }

    @Test("Normalized range keeps return date linked to pickup date")
    func normalizedRangeKeepsReturnDateLinkedToPickupDate() {
        let today = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let pickup = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let earlierReturn = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))!

        let range = AppDateRules.normalizedRange(pickup: pickup, returnDate: earlierReturn, today: today)

        #expect(range.pickup == pickup)
        #expect(range.returnDate == pickup)
    }

    @Test("Normalized range moves past pickup to fixed today")
    func normalizedRangeMovesPastPickupToFixedToday() {
        let today = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 12))!
        let pickup = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let returnDate = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 11))!

        let range = AppDateRules.normalizedRange(pickup: pickup, returnDate: returnDate, today: today)

        #expect(range.pickup == today)
        #expect(range.returnDate == today)
    }

    @Test("Month grid uses six Sunday-first weeks around visible month")
    func monthGridUsesSixSundayFirstWeeksAroundVisibleMonth() {
        let month = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let days = AppDateRules.monthGrid(containing: month)

        #expect(days.count == 42)
        #expect(AppDateRules.formatRequestDate(days[0]) == "2026-05-31")
        #expect(AppDateRules.formatRequestDate(days[10]) == "2026-06-10")
        #expect(AppDateRules.formatRequestDate(days[41]) == "2026-07-11")
    }

    @Test("Month title and month navigation use calendar month starts")
    func monthTitleAndMonthNavigationUseCalendarMonthStarts() {
        let date = AppDateRules.calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!

        let nextMonth = AppDateRules.month(byAdding: 1, to: date)
        let previousYear = AppDateRules.month(byAdding: -6, to: date)

        #expect(AppDateRules.monthTitle(for: date) == "2026 年 6 月")
        #expect(AppDateRules.formatRequestDate(nextMonth) == "2026-07-01")
        #expect(AppDateRules.formatRequestDate(previousYear) == "2025-12-01")
    }
}
