import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Rental calendar and time selection")
struct RentalDateTimeSelectionTests {
    @Test func selectingAnotherDayPreservesHourAndMinuteAcrossYear() throws {
        let original = try date("2026-12-31 10:17")
        let selected = try date("2027-01-15 00:00")
        #expect(AppDateRules.formatRequestDateTime(RentalDateTimeSelection.replacingDay(of: original, with: selected)) == "2027-01-15 10:17")
    }

    @Test func choosingTimeDoesNotChangeDateOrRoundMinutes() throws {
        let original = try date("2027-02-14 10:17")
        #expect(AppDateRules.formatRequestDateTime(RentalDateTimeSelection.replacingTime(of: original, hour: 23, minute: 59)) == "2027-02-14 23:59")
        #expect(RentalDateTimeSelection.replacingTime(of: original, hour: 24, minute: 0) == original)
    }

    @Test func draftChangesDoNotAlterCommittedRange() throws {
        let committed = RentalDateTimeSelection(pickup: try date("2027-01-15 10:00"), returnDate: try date("2027-02-14 10:00"))
        var draft = committed
        draft.pickup = RentalDateTimeSelection.replacingDay(of: draft.pickup, with: try date("2027-03-01 00:00"))
        #expect(committed.pickup == (try date("2027-01-15 10:00")))
        #expect(draft.returnDate == committed.returnDate)
        #expect(draft.validationMessage(now: try date("2026-11-16 12:00")) != nil)
    }

    @Test func sameDayRentalsRequireLaterReturnTime() throws {
        let now = try date("2027-01-15 09:00")
        let valid = RentalDateTimeSelection(pickup: try date("2027-01-15 10:00"), returnDate: try date("2027-01-15 18:30"))
        #expect(valid.validationMessage(now: now) == nil)
        #expect(valid.estimatedDays == 1)
        let equal = RentalDateTimeSelection(pickup: valid.pickup, returnDate: valid.pickup)
        #expect(equal.validationMessage(now: now) != nil)
        #expect(valid.validationMessage(now: valid.pickup) != nil)
    }

    @Test func interfaceUsesDraftCalendarAndDefaultTimes() throws {
        let panel = try String(contentsOfFile: "Sources/CarRentalOptimizer/SearchPanelView.swift", encoding: .utf8)
        let picker = try String(contentsOfFile: "Sources/CarRentalOptimizer/RentalDateRangePicker.swift", encoding: .utf8)
        #expect(panel.contains("DateRangeField("))
        #expect(!panel.contains("returnDate = newValue.addingTimeInterval"))
        #expect(picker.contains("draft = RentalDateTimeSelection(pickup: pickupDate, returnDate: returnDate)"))
        #expect(picker.contains("onCancel: { showingRangePicker = false }"))
        #expect(picker.contains("DateRangeCalendarMonthView("))
        #expect(!picker.contains("RentalTimePicker"))
        #expect(picker.contains("defaultTimeSummary"))
        #expect(!picker.contains("pickupDate = normalized"))
    }

    @Test func futureDatesUseTenAMAndWholeRentalDays() throws {
        let selected = RentalDateTimeSelection(pickup: try date("2027-01-15 16:15"), returnDate: try date("2027-02-14 18:00"))
            .applyingDefaultTimes(now: try date("2026-11-16 13:20"))
        #expect(AppDateRules.formatRequestDateTime(selected.pickup) == "2027-01-15 10:00")
        #expect(AppDateRules.formatRequestDateTime(selected.returnDate) == "2027-02-14 10:00")
        #expect(selected.estimatedDays == 30)
    }

    @Test func todayUsesFutureHourAndAlignsReturnHour() throws {
        let now = try date("2026-11-16 13:20")
        let selected = RentalDateTimeSelection(pickup: now, returnDate: try date("2026-11-17 10:00")).applyingDefaultTimes(now: now)
        #expect(AppDateRules.formatRequestDateTime(selected.pickup) == "2026-11-16 16:00")
        #expect(AppDateRules.formatRequestDateTime(selected.returnDate) == "2026-11-17 16:00")
        #expect(selected.pickup.timeIntervalSince(now) >= 7200)
    }

    @Test func sameDayDefaultsToEveningButNeverSilentlyMovesTheDate() throws {
        let selected = RentalDateTimeSelection(pickup: try date("2027-01-15 00:00"), returnDate: try date("2027-01-15 00:00"))
            .applyingDefaultTimes(now: try date("2026-11-16 13:20"))
        #expect(AppDateRules.formatRequestDateTime(selected.returnDate) == "2027-01-15 18:00")
        let late = try date("2026-11-16 23:00")
        let unavailable = RentalDateTimeSelection(pickup: late, returnDate: late.addingTimeInterval(86400)).applyingDefaultTimes(now: late)
        #expect(AppDateRules.calendar.isDate(unavailable.pickup, inSameDayAs: late))
        #expect(unavailable.validationMessage(now: late) != nil)
    }

    private func date(_ value: String) throws -> Date { try #require(AppDateRules.parseRequestDate(value)) }
}
