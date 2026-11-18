import Foundation

struct RentalDateTimeSelection: Equatable {
    var pickup: Date
    var returnDate: Date

    static func replacingDay(of value: Date, with day: Date) -> Date {
        var parts = AppDateRules.calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = AppDateRules.calendar.component(.hour, from: value)
        parts.minute = AppDateRules.calendar.component(.minute, from: value)
        parts.second = 0
        return AppDateRules.calendar.date(from: parts) ?? value
    }

    static func replacingTime(of value: Date, hour: Int, minute: Int) -> Date {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return value }
        var parts = AppDateRules.calendar.dateComponents([.year, .month, .day], from: value)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return AppDateRules.calendar.date(from: parts) ?? value
    }

    func applyingDefaultTimes(now: Date) -> RentalDateTimeSelection {
        var hour = 10
        if AppDateRules.calendar.isDate(pickup, inSameDayAs: now) {
            let earliest = AppDateRules.defaultPickupDate(now: now)
            if AppDateRules.calendar.isDate(earliest, inSameDayAs: pickup) {
                hour = max(10, AppDateRules.calendar.component(.hour, from: earliest))
            }
            // If today's lead time crosses midnight, keep the selected date and
            // let validation ask for another day rather than silently moving it.
        }
        let sameDay = AppDateRules.calendar.isDate(pickup, inSameDayAs: returnDate)
        return RentalDateTimeSelection(
            pickup: Self.replacingTime(of: pickup, hour: hour, minute: 0),
            returnDate: Self.replacingTime(of: returnDate, hour: sameDay ? 18 : hour, minute: 0)
        )
    }

    var defaultTimeSummary: String {
        let start = String(AppDateRules.formatRequestDateTime(pickup).suffix(5))
        let end = String(AppDateRules.formatRequestDateTime(returnDate).suffix(5))
        return "默认时刻：取车 \(start) · 还车 \(end)（北京时间）"
    }

    func validationMessage(now: Date) -> String? {
        if pickup <= now { return "默认取车时刻已过或提前时间不足，请重新选择取车日期。" }
        if returnDate <= pickup { return "默认还车时刻需晚于取车，请重新选择还车日期。" }
        return nil
    }

    var estimatedDays: Int {
        let duration = returnDate.timeIntervalSince(pickup)
        return duration > 0 ? max(1, Int(ceil(duration / 86400))) : 0
    }
}
