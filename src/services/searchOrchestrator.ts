import { buildRecommendation, rankRecommendations } from "../domain/recommendation";
import { matchVehicle } from "../domain/vehicleMatcher";
import type { Recommendation, RentalListing, SearchRequest } from "../domain/types";
import type { MapService } from "./mockMapService";
import type { RentalAdapter } from "./mockRentalAdapters";

export interface SearchDependencies {
  rentalAdapters: RentalAdapter[];
  mapService: MapService;
}

export async function searchRentalOptions(
  request: SearchRequest,
  dependencies: SearchDependencies
): Promise<Recommendation[]> {
  const activeAdapters = dependencies.rentalAdapters.filter((adapter) =>
    request.platforms.includes(adapter.platform)
  );

  const listings = (
    await Promise.all(activeAdapters.map((adapter) => adapter.search(request)))
  ).flat();

  return rankRentalListings(request, listings, dependencies.mapService);
}

export async function rankRentalListings(
  request: SearchRequest,
  listings: RentalListing[],
  mapService: MapService
): Promise<Recommendation[]> {
  const recommendations = await Promise.all(
    listings.map(async (listing) => {
      const routes = await mapService.estimateRoutes(request.origin, listing.store);
      const match = matchVehicle(request.vehicleQuery, listing);

      return buildRecommendation(listing, match, routes.taxi, routes.transit);
    })
  );

  const filteredRecommendations = request.vehicleQuery.trim()
    ? recommendations.filter((recommendation) => recommendation.match.kind !== "low-confidence")
    : recommendations;

  return rankRecommendations(filteredRecommendations);
}
