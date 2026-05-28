import Foundation

func buildRecommendation(
    listing: RentalListing,
    match: VehicleMatch,
    taxiRoute: RouteEstimate,
    transitRoute: RouteEstimate
) -> Recommendation {
    let rentalTotal = roundMoney(listing.basePrice + listing.platformFees + listing.insuranceFees + listing.oneWayFee)
    let taxiTotal = roundMoney(rentalTotal + taxiRoute.cost)
    let transitTotal = roundMoney(rentalTotal + transitRoute.cost)
    let bestRouteMode: RouteMode = taxiTotal <= transitTotal ? .taxi : .transit

    return Recommendation(
        listing: listing,
        match: match,
        taxiRoute: taxiRoute,
        transitRoute: transitRoute,
        rentalTotal: rentalTotal,
        taxiTotal: taxiTotal,
        transitTotal: transitTotal,
        bestTotal: bestRouteMode == .taxi ? taxiTotal : transitTotal,
        bestRouteMode: bestRouteMode,
        warnings: Array(Set(listing.warnings))
    )
}

func rankRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
    recommendations.sorted { left, right in
        if left.bestTotal != right.bestTotal {
            return left.bestTotal < right.bestTotal
        }
        if left.match.kind != right.match.kind {
            return left.match.kind > right.match.kind
        }
        let leftDuration = bestDuration(left)
        let rightDuration = bestDuration(right)
        if leftDuration != rightDuration {
            return leftDuration < rightDuration
        }
        return left.listing.dataCompleteness > right.listing.dataCompleteness
    }
}

private func bestDuration(_ recommendation: Recommendation) -> Int {
    recommendation.bestRouteMode == .taxi
        ? recommendation.taxiRoute.durationMinutes
        : recommendation.transitRoute.durationMinutes
}

private func roundMoney(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}
