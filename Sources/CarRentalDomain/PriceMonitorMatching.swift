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

public func selectMonitoredRecommendation(
    from recommendations: [Recommendation],
    signature: ListingSignature?,
    targetVehicleQuery: String,
    targetPlatform: PlatformId?
) -> Recommendation? {
    let ranked = rankRecommendations(recommendations)

    if let signature {
        if let exact = ranked.first(where: { signature.exactMatch($0) }) {
            return exact
        }
        if let samePlatformVehicle = ranked.first(where: { signature.samePlatformVehicle($0) }) {
            return samePlatformVehicle
        }
        if let sameVehicle = ranked.first(where: { signature.sameVehicle($0) }) {
            return sameVehicle
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
        return queryMatch
    }
    return platformFiltered.first
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
