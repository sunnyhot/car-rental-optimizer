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
}
