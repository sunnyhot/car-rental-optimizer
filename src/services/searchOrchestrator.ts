import { buildRecommendation, rankRecommendations } from "../domain/recommendation";
import { matchVehicle } from "../domain/vehicleMatcher";
import type { Recommendation, SearchRequest } from "../domain/types";
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

  const recommendations = await Promise.all(
    listings.map(async (listing) => {
      const routes = await dependencies.mapService.estimateRoutes(request.origin, listing.store);
      const match = matchVehicle(request.vehicleQuery, listing);

      return buildRecommendation(listing, match, routes.taxi, routes.transit);
    })
  );

  return rankRecommendations(recommendations);
}
