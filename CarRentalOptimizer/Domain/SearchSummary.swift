import Foundation

func calculateRentalDays(pickupAt: String, returnAt: String) -> Int {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

    guard let pickup = formatter.date(from: pickupAt),
          let returnDate = formatter.date(from: returnAt) else {
        return 1
    }

    let hours = max(1, returnDate.timeIntervalSince(pickup) / 3600)
    return max(1, Int(ceil(hours / 24)))
}

func formatSearchCompletionStatus(request: SearchRequest, resultCount: Int) -> String {
    let timeRange = "\(formatDateTime(request.pickupAt)) - \(formatDateTime(request.returnAt))"
    let billableDays = calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)

    if resultCount == 0 {
        return "已按 \(timeRange) 查询，按 \(billableDays) 天计费，没有找到候选车辆。"
    }

    return "已按 \(timeRange) 查询，按 \(billableDays) 天计费，找到 \(resultCount) 个候选方案。"
}

private func formatDateTime(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

    guard let date = formatter.date(from: value) else { return value }

    let output = DateFormatter()
    output.dateFormat = "yyyy/MM/dd HH:mm"
    return output.string(from: date)
}
