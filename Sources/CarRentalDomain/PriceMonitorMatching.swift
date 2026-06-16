import Foundation

public extension ListingSignature {
    init(recommendation: Recommendation) {
        self.init(
            platform: recommendation.listing.platform,
            storeID: recommendation.listing.store.id,
            normalizedStoreName: normalizeMonitorToken(recommendation.listing.store.name + recommendation.listing.store.address),
            normalizedVehicleName: normalizeMonitorToken(recommendation.listing.vehicleName),
            normalizedVehicleClass: normalizeMonitorToken(recommendation.listing.vehicleClass)
        )
    }

    func exactMatch(_ recommendation: Recommendation) -> Bool {
        recommendation.listing.platform == platform
            && recommendation.listing.store.id == storeID
            && normalizeMonitorToken(recommendation.listing.vehicleName) == normalizedVehicleName
    }

    func samePlatformVehicle(_ recommendation: Recommendation) -> Bool {
        recommendation.listing.platform == platform
            && normalizeMonitorToken(recommendation.listing.vehicleName) == normalizedVehicleName
    }

    func sameVehicle(_ recommendation: Recommendation) -> Bool {
        normalizeMonitorToken(recommendation.listing.vehicleName) == normalizedVehicleName
    }
}

public enum MonitorMatchStrategy: String, Codable, Equatable {
    case exactSignature = "exact-signature"
    case samePlatformVehicle = "same-platform-vehicle"
    case sameVehicle = "same-vehicle"
    case targetPlatformQuery = "target-platform-query"
    case fallbackRanked = "fallback-ranked"

    public var summary: String {
        switch self {
        case .exactSignature:
            return "原门店与车型完全一致"
        case .samePlatformVehicle:
            return "同平台同车型，门店已变化"
        case .sameVehicle:
            return "跨平台同车型匹配"
        case .targetPlatformQuery:
            return "目标平台内按车型关键词匹配"
        case .fallbackRanked:
            return "未命中原车型，使用当前排序最优结果"
        }
    }
}

public struct MonitoredRecommendationSelection: Equatable {
    public let recommendation: Recommendation
    public let strategy: MonitorMatchStrategy

    public var summary: String {
        strategy.summary
    }
}

public func selectMonitoredRecommendation(
    from recommendations: [Recommendation],
    signature: ListingSignature?,
    targetVehicleQuery: String,
    targetPlatform: PlatformId?
) -> Recommendation? {
    selectMonitoredRecommendationWithExplanation(
        from: recommendations,
        signature: signature,
        targetVehicleQuery: targetVehicleQuery,
        targetPlatform: targetPlatform
    )?.recommendation
}

public func selectMonitoredRecommendationWithExplanation(
    from recommendations: [Recommendation],
    signature: ListingSignature?,
    targetVehicleQuery: String,
    targetPlatform: PlatformId?
) -> MonitoredRecommendationSelection? {
    let ranked = rankRecommendations(recommendations)

    if let signature {
        if let exact = ranked.first(where: { signature.exactMatch($0) }) {
            return MonitoredRecommendationSelection(recommendation: exact, strategy: .exactSignature)
        }
        if let samePlatformVehicle = ranked.first(where: { signature.samePlatformVehicle($0) }) {
            return MonitoredRecommendationSelection(recommendation: samePlatformVehicle, strategy: .samePlatformVehicle)
        }
        if let sameVehicle = ranked.first(where: { signature.sameVehicle($0) }) {
            return MonitoredRecommendationSelection(recommendation: sameVehicle, strategy: .sameVehicle)
        }
    }

    let normalizedQuery = normalizeMonitorToken(targetVehicleQuery)
    let platformFiltered = targetPlatform.map { platform in
        ranked.filter { $0.listing.platform == platform }
    } ?? ranked
    if let queryMatch = platformFiltered.first(where: {
        let vehicleName = normalizeMonitorToken($0.listing.vehicleName)
        return vehicleName.contains(normalizedQuery) || normalizedQuery.contains(vehicleName)
    }) {
        return MonitoredRecommendationSelection(recommendation: queryMatch, strategy: .targetPlatformQuery)
    }
    return platformFiltered.first.map {
        MonitoredRecommendationSelection(recommendation: $0, strategy: .fallbackRanked)
    }
}

public func normalizeMonitorToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "（", with: "(")
        .replacingOccurrences(of: "）", with: ")")
}
