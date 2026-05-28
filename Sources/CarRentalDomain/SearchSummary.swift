import Foundation

/// Calculates the number of billable rental days from pickup to return timestamps.
/// Returns at least 1 day, ceiling fractional days.
public func calculateRentalDays(pickupAt: String, returnAt: String) -> Int {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

    // Try ISO 8601 first; fall back to a lenient "yyyy-MM-dd'T'HH:mm" parser.
    guard let pickupDate = formatter.date(from: pickupAt) ?? parseLenient(pickupAt),
          let returnDate = formatter.date(from: returnAt) ?? parseLenient(returnAt)
    else { return 1 }

    let hours = max(1, returnDate.timeIntervalSince(pickupDate) / 3600)
    return max(1, Int(ceil(hours / 24)))
}

private func parseLenient(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: string)
}
