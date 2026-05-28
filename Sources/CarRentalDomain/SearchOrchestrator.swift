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

    // Filter out low-confidence matches when user specified a vehicle
    let filtered = request.vehicleQuery.trimmingCharacters(in: .whitespaces).isEmpty
        ? recommendations
        : recommendations.filter { $0.match.kind != .lowConfidence }

    return rankRecommendations(filtered)
}
