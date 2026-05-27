import { describe, expect, it } from "vitest";
import { createMockMapService } from "./mockMapService";
import { createMockRentalAdapters } from "./mockRentalAdapters";
import { searchRentalOptions } from "./searchOrchestrator";
import type { SearchRequest } from "../domain/types";

const baseRequest: SearchRequest = {
  origin: { lat: 39.9169, lng: 116.6462 },
  originLabel: "北京通州",
  pickupAt: "2026-06-05T09:00",
  returnAt: "2026-06-07T18:00",
  returnMode: "same-store",
  radiusKm: 100,
  vehicleQuery: "瑞虎8",
  platforms: ["ehi", "car-inc"]
};

describe("searchRentalOptions", () => {
  it("queries both platforms and ranks normalized cost breakdowns", async () => {
    const results = await searchRentalOptions(baseRequest, {
      rentalAdapters: createMockRentalAdapters(),
      mapService: createMockMapService()
    });

    expect(results.length).toBeGreaterThan(1);
    expect(new Set(results.map((result) => result.listing.platform))).toEqual(
      new Set(["ehi", "car-inc"])
    );
    expect(results[0].rentalTotal).toBeGreaterThan(0);
    expect(results[0].taxiTotal).toBeGreaterThan(results[0].rentalTotal);
    expect(results[0].transitTotal).toBeGreaterThan(results[0].rentalTotal);
  });

  it("excludes Dezhou East Station when radius is 100 km", async () => {
    const results = await searchRentalOptions(baseRequest, {
      rentalAdapters: createMockRentalAdapters(),
      mapService: createMockMapService()
    });

    expect(results.some((result) => result.listing.store.name === "德州东站店")).toBe(false);
  });

  it("includes Dezhou East Station at 500 km and can rank it first by total cost", async () => {
    const results = await searchRentalOptions(
      { ...baseRequest, radiusKm: 500 },
      {
        rentalAdapters: createMockRentalAdapters(),
        mapService: createMockMapService()
      }
    );

    expect(results.some((result) => result.listing.store.name === "德州东站店")).toBe(true);
    expect(results[0].listing.store.name).toBe("德州东站店");
    expect(results[0].warnings).toContain("cross-city-pickup");
  });
});
