import Foundation

public enum PriceMonitorStatus: String, Codable, Equatable, CaseIterable {
    case active
    case paused
    case checking
    case needsAttention = "needs-attention"
    case expired

    public func shouldPauseAfterPickup(now: Date, pickupAt: Date) -> Bool {
        switch self {
        case .active, .checking, .needsAttention:
            return now >= pickupAt
        case .paused, .expired:
            return false
        }
    }
}

public enum MonitoringFrequency: String, Codable, Equatable, CaseIterable {
    case smart
    case fixed30Minutes = "fixed-30-minutes"
    case fixed1Hour = "fixed-1-hour"
    case fixed3Hours = "fixed-3-hours"
    case fixed1Day = "fixed-1-day"

    public func nextCheck(
        after checkedAt: Date,
        pickupAt: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date? {
        _ = calendar
        guard checkedAt < pickupAt else { return nil }

        let secondsUntilPickup = pickupAt.timeIntervalSince(checkedAt)
        let interval: TimeInterval

        switch self {
        case .smart:
            if secondsUntilPickup <= 12 * 60 * 60 {
                interval = 30 * 60
            } else if secondsUntilPickup <= 2 * 24 * 60 * 60 {
                interval = 60 * 60
            } else if secondsUntilPickup <= 7 * 24 * 60 * 60 {
                interval = 3 * 60 * 60
            } else {
                interval = 24 * 60 * 60
            }
        case .fixed30Minutes:
            interval = 30 * 60
        case .fixed1Hour:
            interval = 60 * 60
        case .fixed3Hours:
            interval = 3 * 60 * 60
        case .fixed1Day:
            interval = 24 * 60 * 60
        }

        return checkedAt.addingTimeInterval(interval)
    }
}

public struct PriceDropRule: Codable, Equatable {
    public var notifyOnAnyDecrease: Bool
    public var minimumDropAmount: Double?
    public var minimumDropPercent: Double?

    public init(
        notifyOnAnyDecrease: Bool = false,
        minimumDropAmount: Double? = nil,
        minimumDropPercent: Double? = nil
    ) {
        self.notifyOnAnyDecrease = notifyOnAnyDecrease
        self.minimumDropAmount = minimumDropAmount
        self.minimumDropPercent = minimumDropPercent
    }

    public static let defaultRule = PriceDropRule(notifyOnAnyDecrease: true)

    public func isSatisfied(previous: Double, current: Double) -> Bool {
        guard previous > 0, current < previous else { return false }
        let amountDrop = previous - current
        let percentDrop = amountDrop / previous

        if notifyOnAnyDecrease { return true }
        if let minimumDropAmount, amountDrop >= minimumDropAmount { return true }
        if let minimumDropPercent, percentDrop >= minimumDropPercent { return true }
        return false
    }
}

public struct ListingSignature: Codable, Equatable {
    public let platform: PlatformId
    public let storeID: String
    public let normalizedStoreName: String
    public let normalizedVehicleName: String
    public let normalizedVehicleClass: String

    public init(
        platform: PlatformId,
        storeID: String,
        normalizedStoreName: String,
        normalizedVehicleName: String,
        normalizedVehicleClass: String
    ) {
        self.platform = platform
        self.storeID = storeID
        self.normalizedStoreName = normalizedStoreName
        self.normalizedVehicleName = normalizedVehicleName
        self.normalizedVehicleClass = normalizedVehicleClass
    }
}

public struct PriceMonitor: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var request: SearchRequest
    public var targetVehicleQuery: String
    public var targetPlatform: PlatformId?
    public var targetListingSignature: ListingSignature?
    public var frequency: MonitoringFrequency
    public var alertRule: PriceDropRule
    public var systemNotificationsEnabled: Bool
    public var status: PriceMonitorStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var lastCheckedAt: Date?
    public var nextCheckAt: Date?

    public init(
        id: String,
        name: String,
        request: SearchRequest,
        targetVehicleQuery: String,
        targetPlatform: PlatformId? = nil,
        targetListingSignature: ListingSignature? = nil,
        frequency: MonitoringFrequency = .smart,
        alertRule: PriceDropRule = .defaultRule,
        systemNotificationsEnabled: Bool = false,
        status: PriceMonitorStatus = .active,
        createdAt: Date,
        updatedAt: Date,
        lastCheckedAt: Date? = nil,
        nextCheckAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.request = request
        self.targetVehicleQuery = targetVehicleQuery
        self.targetPlatform = targetPlatform
        self.targetListingSignature = targetListingSignature
        self.frequency = frequency
        self.alertRule = alertRule
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCheckedAt = lastCheckedAt
        self.nextCheckAt = nextCheckAt
    }
}

public enum PriceSnapshotStatus: String, Codable, Equatable {
    case successful
    case waitingForFirstCheck = "waiting-for-first-check"
    case noMatch = "no-match"
    case loginRequired = "login-required"
    case captchaRequired = "captcha-required"
    case unavailable
    case noCar = "no-car"
    case parseFailed = "parse-failed"
    case networkFailed = "network-failed"

    public var isSuccessful: Bool { self == .successful }
}

public struct PriceSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let monitorID: String
    public let checkedAt: Date
    public let status: PriceSnapshotStatus
    public let platformRentalPrice: Double?
    public let recommendationTotalCost: Double?
    public let platform: PlatformId?
    public let storeName: String?
    public let vehicleName: String?
    public let dataCompleteness: Double?
    public let warnings: [ResultWarning]
    public let sourceURL: String?
    public let message: String

    public init(
        id: String,
        monitorID: String,
        checkedAt: Date,
        status: PriceSnapshotStatus,
        platformRentalPrice: Double? = nil,
        recommendationTotalCost: Double? = nil,
        platform: PlatformId? = nil,
        storeName: String? = nil,
        vehicleName: String? = nil,
        dataCompleteness: Double? = nil,
        warnings: [ResultWarning] = [],
        sourceURL: String? = nil,
        message: String
    ) {
        self.id = id
        self.monitorID = monitorID
        self.checkedAt = checkedAt
        self.status = status
        self.platformRentalPrice = platformRentalPrice
        self.recommendationTotalCost = recommendationTotalCost
        self.platform = platform
        self.storeName = storeName
        self.vehicleName = vehicleName
        self.dataCompleteness = dataCompleteness
        self.warnings = warnings
        self.sourceURL = sourceURL
        self.message = message
    }

    public func isHistoricalSnapshot(comparedToLatestID latestID: String?) -> Bool {
        guard status == .successful, let latestID else { return false }
        return id != latestID
    }
}

public enum PriceMonitorEventKind: String, Codable, Equatable {
    case priceDrop = "price-drop"
    case repeatedFailure = "repeated-failure"
    case recovered
    case pausedAfterPickup = "paused-after-pickup"
}

public struct PriceMonitorEvent: Codable, Equatable, Identifiable {
    public let id: String
    public let monitorID: String
    public let occurredAt: Date
    public let kind: PriceMonitorEventKind
    public let previousSnapshotID: String?
    public let currentSnapshotID: String?
    public let platformRentalDelta: Double?
    public let totalCostDelta: Double?
    public let message: String

    public init(
        id: String,
        monitorID: String,
        occurredAt: Date,
        kind: PriceMonitorEventKind,
        previousSnapshotID: String? = nil,
        currentSnapshotID: String? = nil,
        platformRentalDelta: Double? = nil,
        totalCostDelta: Double? = nil,
        message: String
    ) {
        self.id = id
        self.monitorID = monitorID
        self.occurredAt = occurredAt
        self.kind = kind
        self.previousSnapshotID = previousSnapshotID
        self.currentSnapshotID = currentSnapshotID
        self.platformRentalDelta = platformRentalDelta
        self.totalCostDelta = totalCostDelta
        self.message = message
    }
}

public enum MonitorCenterFilter: String, Codable, Equatable, CaseIterable {
    case all
    case active
    case needsAttention = "needs-attention"
    case paused
    case expired
}

public struct MonitorHealthSummary: Equatable {
    public let totalCount: Int
    public let activeCount: Int
    public let needsAttentionCount: Int
    public let recentPriceDropCount: Int
    public let dueTodayCount: Int

    public static func make(
        monitors: [PriceMonitor],
        eventsByMonitorID: [String: [PriceMonitorEvent]],
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> MonitorHealthSummary {
        let recentCutoff = now.addingTimeInterval(-24 * 60 * 60)
        let recentPriceDropIDs = Set(eventsByMonitorID.flatMap { monitorID, events in
            events.contains { $0.kind == .priceDrop && $0.occurredAt >= recentCutoff } ? [monitorID] : []
        })
        let dueTodayCount = monitors.filter { monitor in
            guard monitor.status == .active || monitor.status == .needsAttention,
                  let nextCheckAt = monitor.nextCheckAt
            else { return false }
            return calendar.isDate(nextCheckAt, inSameDayAs: now)
        }.count

        return MonitorHealthSummary(
            totalCount: monitors.count,
            activeCount: monitors.filter { $0.status == .active }.count,
            needsAttentionCount: monitors.filter { $0.status == .needsAttention }.count,
            recentPriceDropCount: recentPriceDropIDs.count,
            dueTodayCount: dueTodayCount
        )
    }
}

public func filterMonitorsForCenter(
    _ monitors: [PriceMonitor],
    filter: MonitorCenterFilter
) -> [PriceMonitor] {
    switch filter {
    case .all:
        return monitors
    case .active:
        return monitors.filter { $0.status == .active || $0.status == .checking }
    case .needsAttention:
        return monitors.filter { $0.status == .needsAttention }
    case .paused:
        return monitors.filter { $0.status == .paused }
    case .expired:
        return monitors.filter { $0.status == .expired }
    }
}

public func sortMonitorsForCenter(
    _ monitors: [PriceMonitor],
    eventsByMonitorID: [String: [PriceMonitorEvent]] = [:],
    now: Date,
    calendar: Calendar = Calendar(identifier: .gregorian)
) -> [PriceMonitor] {
    monitors.sorted { lhs, rhs in
        monitorCenterSortKey(lhs, events: eventsByMonitorID[lhs.id, default: []], now: now, calendar: calendar)
            < monitorCenterSortKey(rhs, events: eventsByMonitorID[rhs.id, default: []], now: now, calendar: calendar)
    }
}

public func makeMonitorLifecycleEvents(
    monitor: PriceMonitor,
    previousSnapshots: [PriceSnapshot],
    currentSnapshot: PriceSnapshot,
    checkedAt: Date,
    repeatedFailureThreshold: Int = 3,
    id: () -> String
) -> [PriceMonitorEvent] {
    let orderedPrevious = previousSnapshots.sorted { $0.checkedAt < $1.checkedAt }

    if currentSnapshot.status == .successful {
        guard let previous = orderedPrevious.last,
              !previous.status.isSuccessful
        else { return [] }

        return [
            PriceMonitorEvent(
                id: id(),
                monitorID: monitor.id,
                occurredAt: checkedAt,
                kind: .recovered,
                previousSnapshotID: previous.id,
                currentSnapshotID: currentSnapshot.id,
                message: "\(monitor.name) 已从 \(previous.status.label) 恢复，重新记录到官方报价。"
            )
        ]
    }

    let sameFailureCount = orderedPrevious
        .reversed()
        .prefix { $0.status == currentSnapshot.status }
        .count
    guard sameFailureCount == repeatedFailureThreshold - 1 else { return [] }

    return [
        PriceMonitorEvent(
            id: id(),
            monitorID: monitor.id,
            occurredAt: checkedAt,
            kind: .repeatedFailure,
            previousSnapshotID: orderedPrevious.last?.id,
            currentSnapshotID: currentSnapshot.id,
            message: "\(monitor.name) 连续 \(repeatedFailureThreshold) 次出现\(currentSnapshot.status.label)，需要处理后再继续巡查。"
        )
    ]
}

public struct PriceTrendSummary: Equatable {
    public let validPoints: [PriceSnapshot]
    public let latestPlatformRentalPrice: Double?
    public let previousPlatformRentalPrice: Double?
    public let platformRentalDelta: Double?
    public let firstPlatformRentalPrice: Double?
    public let lowestPlatformRentalPrice: Double?
    public let highestPlatformRentalPrice: Double?
    public let platformRentalDeltaFromFirst: Double?
    public let latestRecommendationTotalCost: Double?
    public let previousRecommendationTotalCost: Double?
    public let recommendationTotalDelta: Double?
    public let latestSuccessfulCheckAt: Date?

    public init(snapshots: [PriceSnapshot]) {
        self.validPoints = snapshots
            .filter { $0.status == .successful && $0.platformRentalPrice != nil }
            .sorted { $0.checkedAt < $1.checkedAt }
        self.latestPlatformRentalPrice = validPoints.last?.platformRentalPrice
        self.previousPlatformRentalPrice = validPoints.dropLast().last?.platformRentalPrice
        self.firstPlatformRentalPrice = validPoints.first?.platformRentalPrice
        self.lowestPlatformRentalPrice = validPoints.compactMap(\.platformRentalPrice).min()
        self.highestPlatformRentalPrice = validPoints.compactMap(\.platformRentalPrice).max()
        self.latestRecommendationTotalCost = validPoints.last?.recommendationTotalCost
        self.previousRecommendationTotalCost = validPoints.dropLast().last?.recommendationTotalCost
        self.latestSuccessfulCheckAt = validPoints.last?.checkedAt
        if let latestPlatformRentalPrice, let previousPlatformRentalPrice {
            self.platformRentalDelta = latestPlatformRentalPrice - previousPlatformRentalPrice
        } else {
            self.platformRentalDelta = nil
        }
        if let latestPlatformRentalPrice, let firstPlatformRentalPrice {
            self.platformRentalDeltaFromFirst = latestPlatformRentalPrice - firstPlatformRentalPrice
        } else {
            self.platformRentalDeltaFromFirst = nil
        }
        if let latestRecommendationTotalCost, let previousRecommendationTotalCost {
            self.recommendationTotalDelta = latestRecommendationTotalCost - previousRecommendationTotalCost
        } else {
            self.recommendationTotalDelta = nil
        }
    }
}

private func monitorCenterSortKey(
    _ monitor: PriceMonitor,
    events: [PriceMonitorEvent],
    now: Date,
    calendar: Calendar
) -> MonitorCenterSortKey {
    MonitorCenterSortKey(
        statusPriority: statusPriority(monitor.status),
        recentDropPriority: hasRecentPriceDrop(events, now: now) ? 0 : 1,
        pickupUrgencyPriority: pickupUrgencyPriority(monitor, now: now, calendar: calendar),
        duePriority: (monitor.nextCheckAt ?? .distantFuture) <= now ? 0 : 1,
        nextCheckAt: monitor.nextCheckAt ?? .distantFuture,
        updatedAt: monitor.updatedAt,
        id: monitor.id
    )
}

private struct MonitorCenterSortKey: Comparable {
    let statusPriority: Int
    let recentDropPriority: Int
    let pickupUrgencyPriority: Int
    let duePriority: Int
    let nextCheckAt: Date
    let updatedAt: Date
    let id: String

    static func < (lhs: MonitorCenterSortKey, rhs: MonitorCenterSortKey) -> Bool {
        if lhs.statusPriority != rhs.statusPriority { return lhs.statusPriority < rhs.statusPriority }
        if lhs.recentDropPriority != rhs.recentDropPriority { return lhs.recentDropPriority < rhs.recentDropPriority }
        if lhs.pickupUrgencyPriority != rhs.pickupUrgencyPriority { return lhs.pickupUrgencyPriority < rhs.pickupUrgencyPriority }
        if lhs.duePriority != rhs.duePriority { return lhs.duePriority < rhs.duePriority }
        if lhs.nextCheckAt != rhs.nextCheckAt { return lhs.nextCheckAt < rhs.nextCheckAt }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id < rhs.id
    }
}

private func statusPriority(_ status: PriceMonitorStatus) -> Int {
    switch status {
    case .needsAttention:
        return 0
    case .checking:
        return 1
    case .active:
        return 2
    case .paused:
        return 3
    case .expired:
        return 4
    }
}

private func hasRecentPriceDrop(_ events: [PriceMonitorEvent], now: Date) -> Bool {
    let cutoff = now.addingTimeInterval(-24 * 60 * 60)
    return events.contains { $0.kind == .priceDrop && $0.occurredAt >= cutoff }
}

private func pickupUrgencyPriority(
    _ monitor: PriceMonitor,
    now: Date,
    calendar: Calendar
) -> Int {
    guard let pickupAt = parseMonitorRequestDate(monitor.request.pickupAt, calendar: calendar) else {
        return 2
    }
    if pickupAt <= now { return 0 }
    return pickupAt.timeIntervalSince(now) <= 48 * 60 * 60 ? 0 : 1
}

private func parseMonitorRequestDate(_ value: String, calendar: Calendar) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private extension PriceSnapshotStatus {
    var label: String {
        switch self {
        case .successful:
            return "成功报价"
        case .waitingForFirstCheck:
            return "等待首次巡查"
        case .noMatch:
            return "未匹配车型"
        case .loginRequired:
            return "登录失效"
        case .captchaRequired:
            return "验证阻断"
        case .unavailable:
            return "平台不可用"
        case .noCar:
            return "暂无车辆"
        case .parseFailed:
            return "解析失败"
        case .networkFailed:
            return "网络失败"
        }
    }
}
