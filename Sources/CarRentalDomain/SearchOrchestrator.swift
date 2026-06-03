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
    guard !hasVehicleQuery || isSpecificVehicleQuery else {
        return ranked
    }
    return dedupeVehicleRecommendations(ranked, specificVehicleKey: isSpecificVehicleQuery ? vehicleQuery : nil)
}

private func dedupeVehicleRecommendations(
    _ recommendations: [Recommendation],
    specificVehicleKey: String? = nil
) -> [Recommendation] {
    var seen = Set<String>()
    return recommendations.filter { recommendation in
        let key = specificVehicleKey.map(normalizedVehicleKey) ?? normalizedVehicleKey(recommendation.listing.vehicleName)
        return seen.insert(key).inserted
    }
}

private func normalizedVehicleKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: "（", with: "(")
        .replacingOccurrences(of: "）", with: ")")
}
