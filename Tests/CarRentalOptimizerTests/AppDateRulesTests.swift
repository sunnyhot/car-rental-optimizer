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
}
