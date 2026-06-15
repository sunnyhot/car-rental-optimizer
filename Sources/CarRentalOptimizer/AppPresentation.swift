import CarRentalDomain
import Foundation

extension Notification.Name {
    static let openMonitorCenter = Notification.Name("OpenMonitorCenter")
}

enum AppDefaults {
    static var searchRequest: SearchRequest {
        let pickupDate = AppDateRules.today
        let returnDate = AppDateRules.addingDays(1, to: pickupDate)

        return SearchRequest(
            origin: GeoPoint(lat: 39.9169, lng: 116.6462),
            originLabel: "北京通州",
            pickupAt: AppDateRules.formatRequestDate(pickupDate),
            returnAt: AppDateRules.formatRequestDate(returnDate),
            returnMode: .sameStore,
            radiusKm: 100,
            vehicleQuery: "瑞虎8",
            platforms: [.ehi, .carInc]
        )
    }
}

enum AppDateRules {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    static var today: Date {
        calendar.startOfDay(for: Date())
    }

    static func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }

    static func monthStart(containing date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: calendar.startOfDay(for: date))
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func month(byAdding months: Int, to date: Date) -> Date {
        let monthStart = monthStart(containing: date)
        return calendar.date(byAdding: .month, value: months, to: monthStart) ?? monthStart
    }

    static func monthTitle(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: monthStart(containing: date))
        return "\(components.year ?? 0) 年 \(components.month ?? 0) 月"
    }

    static func monthGrid(containing date: Date) -> [Date] {
        let firstOfMonth = monthStart(containing: date)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDays = max(0, weekday - 1)
        let firstGridDay = calendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) ?? firstOfMonth

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: firstGridDay)
        }
    }

    static func normalizedRange(
        pickup: Date,
        returnDate: Date,
        today: Date = AppDateRules.today
    ) -> (pickup: Date, returnDate: Date) {
        let normalizedPickup = maxDay(calendar.startOfDay(for: pickup), calendar.startOfDay(for: today))
        let normalizedReturn = maxDay(calendar.startOfDay(for: returnDate), normalizedPickup)
        return (normalizedPickup, normalizedReturn)
    }

    static func formatRequestDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: calendar.startOfDay(for: date))
    }

    static func formatDisplayDate(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: calendar.startOfDay(for: date))
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    static func formatWeekday(_ date: Date) -> String {
        let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = calendar.component(.weekday, from: calendar.startOfDay(for: date))
        return weekdaySymbols[max(0, min(weekday - 1, weekdaySymbols.count - 1))]
    }

    static func rentalDaySpan(pickup: Date, returnDate: Date) -> Int {
        let pickupDay = calendar.startOfDay(for: pickup)
        let returnDay = calendar.startOfDay(for: returnDate)
        let days = calendar.dateComponents([.day], from: pickupDay, to: returnDay).day ?? 1
        return max(1, days)
    }

    static func parseRequestDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.date(from: value)
    }

    private static func maxDay(_ lhs: Date, _ rhs: Date) -> Date {
        lhs < rhs ? rhs : lhs
    }
}

extension PlatformId {
    var label: String {
        switch self {
        case .ehi:
            return "一嗨"
        case .carInc:
            return "神州"
        }
    }
}

extension ReturnMode {
    var label: String {
        switch self {
        case .sameStore:
            return "同店取还"
        case .differentStore:
            return "异店/异地还车"
        }
    }
}

extension RouteMode {
    var label: String {
        switch self {
        case .taxi:
            return "打车"
        case .transit:
            return "公共交通"
        }
    }
}

extension MonitoringFrequency {
    var label: String {
        switch self {
        case .smart:
            return "智能频率"
        case .fixed30Minutes:
            return "每 30 分钟"
        case .fixed1Hour:
            return "每 1 小时"
        case .fixed3Hours:
            return "每 3 小时"
        case .fixed1Day:
            return "每天"
        }
    }
}

extension PriceMonitorStatus {
    var label: String {
        switch self {
        case .active:
            return "监控中"
        case .paused:
            return "已暂停"
        case .checking:
            return "巡查中"
        case .needsAttention:
            return "需处理"
        case .expired:
            return "已过期"
        }
    }
}

func renderWarnings(_ warnings: [ResultWarning]) -> String {
    if warnings.contains(.crossCityPickup) {
        return "这是跨城取车方案，租车价格低，但需要额外关注高铁班次、门店营业时间和行李不便。"
    }

    if warnings.contains(.partialPrice) {
        return "该方案存在部分价格缺失，建议打开原始平台复核。"
    }

    if warnings.contains(.mapCostMissing) {
        return "交通成本暂不可用，当前排序主要参考租车价格。"
    }

    return "该方案存在数据完整度提醒，建议打开原始平台复核。"
}

func formatMoney(_ value: Double) -> String {
    "¥\(Int(value.rounded()))"
}

func formatSignedMoney(_ value: Double?) -> String {
    guard let value else { return "--" }
    let prefix = value > 0 ? "+" : ""
    return "\(prefix)\(formatMoney(value))"
}
