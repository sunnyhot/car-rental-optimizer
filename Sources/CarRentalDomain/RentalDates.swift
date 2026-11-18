import Foundation

/// Legacy day-only records remain readable; new searches must carry explicit minutes.
public func parseRentalDate(_ value: String) -> Date? {
    let format: String
    switch value.count {
    case 10: format = "yyyy-MM-dd"
    case 16: format = value.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd HH:mm"
    default: return nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = format
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
    return date
}
