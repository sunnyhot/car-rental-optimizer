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

public struct PriceTrendSummary: Equatable {
    public let validPoints: [PriceSnapshot]
    public let latestPlatformRentalPrice: Double?
    public let previousPlatformRentalPrice: Double?
    public let platformRentalDelta: Double?

    public init(snapshots: [PriceSnapshot]) {
        self.validPoints = snapshots
            .filter { $0.status == .successful && $0.platformRentalPrice != nil }
            .sorted { $0.checkedAt < $1.checkedAt }
        self.latestPlatformRentalPrice = validPoints.last?.platformRentalPrice
        self.previousPlatformRentalPrice = validPoints.dropLast().last?.platformRentalPrice
        if let latestPlatformRentalPrice, let previousPlatformRentalPrice {
            self.platformRentalDelta = latestPlatformRentalPrice - previousPlatformRentalPrice
        } else {
            self.platformRentalDelta = nil
        }
    }
}
