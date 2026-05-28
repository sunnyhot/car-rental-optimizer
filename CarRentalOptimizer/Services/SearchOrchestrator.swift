import Foundation

func rankRentalListings(
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
                    candidate: VehicleCandidate(vehicleName: listing.vehicleName, vehicleClass: listing.vehicleClass)
                )
                return buildRecommendation(listing: listing, match: match, taxiRoute: routes.taxi, transitRoute: routes.transit)
            }
        }

        var results: [Recommendation] = []
        for await recommendation in group {
            if let recommendation = recommendation {
                results.append(recommendation)
            }
        }
        return results
    }

    let filtered: [Recommendation]
    if request.vehicleQuery.trimmingCharacters(in: .whitespaces).isEmpty {
        filtered = recommendations
    } else {
        filtered = recommendations.filter { $0.match.kind != .lowConfidence }
    }

    return rankRecommendations(filtered)
}
