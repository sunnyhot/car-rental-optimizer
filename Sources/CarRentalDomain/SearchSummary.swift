import Foundation

/// Calculates the number of billable rental days from pickup to return timestamps.
/// Returns at least 1 day, ceiling fractional days.
public func calculateRentalDays(pickupAt: String, returnAt: String) -> Int {
    if let pickupDate = parseDateOnly(pickupAt),
       let returnDate = parseDateOnly(returnAt) {
        let calendar = chinaCalendar()
        let days = calendar.dateComponents([.day], from: pickupDate, to: returnDate).day ?? 0
        return max(1, days)
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

    // Try ISO 8601 first; fall back to a lenient "yyyy-MM-dd'T'HH:mm" parser.
    guard let pickupDate = formatter.date(from: pickupAt) ?? parseLenient(pickupAt),
          let returnDate = formatter.date(from: returnAt) ?? parseLenient(returnAt)
    else { return 1 }

    let hours = max(1, returnDate.timeIntervalSince(pickupDate) / 3600)
    return max(1, Int(ceil(hours / 24)))
}

/// Formats a concise user-facing summary for a completed search.
public func formatSearchCompletionStatus(request: SearchRequest, resultCount: Int) -> String {
    let timeRange = "\(formatDateTime(request.pickupAt)) - \(formatDateTime(request.returnAt))"
    let billableDays = calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)

    if resultCount == 0 {
        return "已按 \(timeRange) 查询，按 \(billableDays) 天计费，没有找到候选车辆。"
    }

    return "已按 \(timeRange) 查询，按 \(billableDays) 天计费，找到 \(resultCount) 个候选方案。"
}

private func parseLenient(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: string)
}

private func parseDateOnly(_ string: String) -> Date? {
    guard string.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
        return nil
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: string)
}

private func formatDateTime(_ value: String) -> String {
    if let date = parseDateOnly(value) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: date)
    }

    guard let date = parseLenient(value) else { return value }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.string(from: date)
}

private func chinaCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    return calendar
}
