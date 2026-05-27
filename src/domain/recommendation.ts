import type { Recommendation, RentalListing, RouteEstimate, VehicleMatch } from "./types";

const MATCH_PRIORITY: Record<VehicleMatch["kind"], number> = {
  exact: 3,
  "similar-class": 2,
  "low-confidence": 1
};

export function buildRecommendation(
  listing: RentalListing,
  match: VehicleMatch,
  taxiRoute: RouteEstimate,
  transitRoute: RouteEstimate
): Recommendation {
  const rentalTotal = roundMoney(
    listing.basePrice + listing.platformFees + listing.insuranceFees + listing.oneWayFee
  );
  const taxiTotal = roundMoney(rentalTotal + taxiRoute.cost);
  const transitTotal = roundMoney(rentalTotal + transitRoute.cost);
  const bestRouteMode = taxiTotal <= transitTotal ? "taxi" : "transit";

  return {
    listing,
    match,
    taxiRoute,
    transitRoute,
    rentalTotal,
    taxiTotal,
    transitTotal,
    bestTotal: bestRouteMode === "taxi" ? taxiTotal : transitTotal,
    bestRouteMode,
    warnings: Array.from(new Set(listing.warnings))
  };
}

export function rankRecommendations(recommendations: Recommendation[]): Recommendation[] {
  return [...recommendations].sort((left, right) => {
    const totalDelta = left.bestTotal - right.bestTotal;
    if (totalDelta !== 0) {
      return totalDelta;
    }

    const matchDelta = MATCH_PRIORITY[right.match.kind] - MATCH_PRIORITY[left.match.kind];
    if (matchDelta !== 0) {
      return matchDelta;
    }

    const durationDelta = bestDuration(left) - bestDuration(right);
    if (durationDelta !== 0) {
      return durationDelta;
    }

    return right.listing.dataCompleteness - left.listing.dataCompleteness;
  });
}

function bestDuration(recommendation: Recommendation): number {
  return recommendation.bestRouteMode === "taxi"
    ? recommendation.taxiRoute.durationMinutes
    : recommendation.transitRoute.durationMinutes;
}

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}
