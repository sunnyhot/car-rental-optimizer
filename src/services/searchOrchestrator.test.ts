import { describe, expect, it } from "vitest";
import { createMockMapService } from "./mockMapService";
import { createMockRentalAdapters } from "./mockRentalAdapters";
import { rankRentalListings, searchRentalOptions } from "./searchOrchestrator";
import type { RentalListing, SearchRequest } from "../domain/types";

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

  it("uses the selected rental duration when calculating mock rental prices", async () => {
    const twoDayResults = await searchRentalOptions(baseRequest, {
      rentalAdapters: createMockRentalAdapters(),
      mapService: createMockMapService()
    });
    const thirtyDayResults = await searchRentalOptions(
      {
        ...baseRequest,
        pickupAt: "2026-09-11T09:00",
        returnAt: "2026-10-11T18:00"
      },
      {
        rentalAdapters: createMockRentalAdapters(),
        mapService: createMockMapService()
      }
    );

    const twoDaySouth = twoDayResults.find((result) => result.listing.store.name === "北京南站店");
    const thirtyDaySouth = thirtyDayResults.find((result) => result.listing.store.name === "北京南站店");

    expect(twoDaySouth?.listing.basePrice).toBe(804);
    expect(thirtyDaySouth?.listing.basePrice).toBe(8_308);
    expect(thirtyDaySouth!.rentalTotal).toBeGreaterThan(twoDaySouth!.rentalTotal);
  });

  it("does not include unrelated vehicle classes when a specific model is requested", async () => {
    const results = await searchRentalOptions(baseRequest, {
      rentalAdapters: createMockRentalAdapters(),
      mapService: createMockMapService()
    });

    expect(results.some((result) => result.listing.vehicleName.includes("朗逸"))).toBe(false);
  });

  it("shows all available vehicle classes when the vehicle query is empty", async () => {
    const results = await searchRentalOptions(
      { ...baseRequest, vehicleQuery: "" },
      {
        rentalAdapters: createMockRentalAdapters(),
        mapService: createMockMapService()
      }
    );

    const sedan = results.find((result) => result.listing.vehicleName.includes("朗逸"));

    expect(sedan).toBeDefined();
    expect(sedan?.match.kind).toBe("not-specified");
  });

  it("uses the origin coordinates to filter nearby stores", async () => {
    const results = await searchRentalOptions(
      {
        ...baseRequest,
        origin: { lat: 37.443, lng: 116.374 },
        originLabel: "德州东站",
        radiusKm: 100
      },
      {
        rentalAdapters: createMockRentalAdapters(),
        mapService: createMockMapService()
      }
    );

    expect(results.map((result) => result.listing.store.name)).toEqual(["德州东站店"]);
    expect(results[0].taxiRoute.distanceKm).toBeLessThan(1);
  });

  it("ranks parsed live listings without needing mock rental adapters", async () => {
    const liveListing: RentalListing = {
      id: "live-ehi-1",
      platform: "ehi",
      store: {
        id: "live-store",
        platform: "ehi",
        name: "德州东站店",
        city: "德州",
        address: "德州东站店",
        location: { lat: 37.443, lng: 116.374 },
        distanceKm: 286,
        hours: "以平台页面为准"
      },
      vehicleName: "奇瑞 瑞虎8 1.6T 自动",
      vehicleClass: "中型SUV",
      basePrice: 268,
      platformFees: 0,
      insuranceFees: 0,
      oneWayFee: 0,
      currency: "CNY",
      sourceUrl: "https://booking.1hai.cn/",
      dataCompleteness: 0.72,
      warnings: ["partial-price"]
    };

    const results = await rankRentalListings(baseRequest, [liveListing], createMockMapService());

    expect(results).toHaveLength(1);
    expect(results[0].listing.sourceUrl).toBe("https://booking.1hai.cn/");
    expect(results[0].match.kind).toBe("exact");
  });
});
