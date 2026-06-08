import Foundation

/// Priority ordering for match kinds (higher = better).
private let MATCH_PRIORITY: [MatchKind: Int] = [
    .exact: 3,
    .similarClass: 2,
    .lowConfidence: 1,
    .notSpecified: 0
]

/// Builds a fully scored recommendation from a listing, match, and route estimates.
public func buildRecommendation(
    listing: RentalListing,
    match: VehicleMatch,
    taxiRoute: RouteEstimate,
    transitRoute: RouteEstimate
) -> Recommendation {
    let rentalTotal = roundMoney(listing.basePrice + listing.platformFees + listing.insuranceFees + listing.oneWayFee)
    let taxiTotal = roundMoney(rentalTotal + taxiRoute.cost)
    let transitTotal = roundMoney(rentalTotal + transitRoute.cost)
    let bestRouteMode: RouteMode = taxiTotal <= transitTotal ? .taxi : .transit
    let bestTotal = bestRouteMode == .taxi ? taxiTotal : transitTotal

    // Deduplicate warnings
    var seen = Set<ResultWarning>()
    let uniqueWarnings = listing.warnings.filter { seen.insert($0).inserted }

    return Recommendation(
        listing: listing,
        match: match,
        taxiRoute: taxiRoute,
        transitRoute: transitRoute,
        rentalTotal: rentalTotal,
        taxiTotal: taxiTotal,
        transitTotal: transitTotal,
        bestTotal: bestTotal,
        bestRouteMode: bestRouteMode,
        warnings: uniqueWarnings
    )
}

/// Ranks recommendations by: best total cost → match priority → route duration → data completeness.
public func rankRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
    recommendations.sorted { left, right in
        let totalDelta = left.bestTotal - right.bestTotal
        if totalDelta != 0 { return totalDelta < 0 }

        let matchDelta = (MATCH_PRIORITY[right.match.kind] ?? 0) - (MATCH_PRIORITY[left.match.kind] ?? 0)
        if matchDelta != 0 { return matchDelta < 0 }

        let durationDelta = bestDuration(left) - bestDuration(right)
        if durationDelta != 0 { return durationDelta < 0 }

        return left.listing.dataCompleteness > right.listing.dataCompleteness
    }
}

// MARK: - Private Helpers

private func bestDuration(_ recommendation: Recommendation) -> Double {
    recommendation.bestRouteMode == .taxi
        ? recommendation.taxiRoute.durationMinutes
        : recommendation.transitRoute.durationMinutes
}

private func roundMoney(_ value: Double) -> Double {
    round(value * 100) / 100
}
