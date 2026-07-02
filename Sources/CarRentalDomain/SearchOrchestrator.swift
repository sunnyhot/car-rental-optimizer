import Foundation

// MARK: - Protocols

/// Provides route estimates between an origin and a store.
public protocol MapService {
    func estimateRoutes(origin: GeoPoint, store: Store) async -> (taxi: RouteEstimate, transit: RouteEstimate)
}

/// Searches a specific rental platform for available listings.
public protocol RentalAdapter {
    var platform: PlatformId { get }
    func search(request: SearchRequest) async -> [RentalListing]
}

// MARK: - Orchestrator

/// Searches multiple rental platforms and returns ranked recommendations.
public func searchRentalOptions(
    request: SearchRequest,
    rentalAdapters: [RentalAdapter],
    mapService: MapService
) async -> [Recommendation] {
    let activeAdapters = rentalAdapters.filter { request.platforms.contains($0.platform) }

    let listings = await withTaskGroup(of: [RentalListing].self) { group in
        for adapter in activeAdapters {
            group.addTask { await adapter.search(request: request) }
        }
        return await group.reduce(into: [RentalListing]()) { $0.append(contentsOf: $1) }
    }

    return await rankRentalListings(request: request, listings: listings, mapService: mapService)
}

/// Ranks raw rental listings into scored recommendations.
public func rankRentalListings(
    request: SearchRequest,
    listings: [RentalListing],
    mapService: MapService
) async -> [Recommendation] {
    let recommendations = await withTaskGroup(of: Recommendation?.self) { group in
        for listing in listings {
            group.addTask {
                let routes = await mapService.estimateRoutes(origin: request.origin, store: listing.store)
                let match = matchVehicle(
                    query: request.vehicleQuery,
                    vehicleName: listing.vehicleName,
                    vehicleClass: listing.vehicleClass
                )
                return buildRecommendation(
                    listing: listing,
                    match: match,
                    taxiRoute: routes.taxi,
                    transitRoute: routes.transit
                )
            }
        }
        return await group.reduce(into: [Recommendation?]()) { $0.append($1) }.compactMap { $0 }
    }

    let vehicleQuery = request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasVehicleQuery = !vehicleQuery.isEmpty
    let isSpecificVehicleQuery = isSpecificVehicleModelQuery(vehicleQuery)

    let filtered: [Recommendation]
    if !hasVehicleQuery {
        filtered = recommendations
    } else if isSpecificVehicleQuery {
        filtered = recommendations.filter { $0.match.kind == .exact }
    } else {
        filtered = recommendations.filter { $0.match.kind != .lowConfidence }
    }

    let ranked = rankRecommendations(filtered)
    if !hasVehicleQuery {
        return mergeBlankVehicleRecommendations(ranked)
    }
    return ranked
}

private func mergeBlankVehicleRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
    var groups: [String: [Recommendation]] = [:]
    var orderedKeys: [String] = []

    for recommendation in recommendations {
        let key = normalizedComparableVehicleKey(recommendation.listing.vehicleName)
        if groups[key] == nil {
            orderedKeys.append(key)
        }
        groups[key, default: []].append(recommendation.withComparisonQuotes([]))
    }

    return orderedKeys.compactMap { key in
        guard let group = groups[key] else { return nil }
        let quotes = bestPlatformQuotes(from: group)
        guard let winner = quotes.first else { return nil }
        return winner.withComparisonQuotes(quotes)
    }
}

private func bestPlatformQuotes(from recommendations: [Recommendation]) -> [Recommendation] {
    let ranked = rankRecommendations(recommendations)
    var bestByPlatform: [PlatformId: Recommendation] = [:]

    for recommendation in ranked where bestByPlatform[recommendation.listing.platform] == nil {
        bestByPlatform[recommendation.listing.platform] = recommendation.withComparisonQuotes([])
    }

    return rankRecommendations(Array(bestByPlatform.values))
}

private func normalizedVehicleKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: "（", with: "(")
        .replacingOccurrences(of: "）", with: ")")
}

private func normalizedComparableVehicleKey(_ value: String) -> String {
    var result = normalizedVehicleKey(value)
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "/", with: "")

    for token in ["自动挡", "手动挡", "自动", "手动", "at", "mt"] {
        result = result.replacingOccurrences(of: token, with: "")
    }

    return result
}
