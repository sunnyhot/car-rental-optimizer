import { describe, expect, it } from "vitest";
import type { RentalListing, RouteEstimate, VehicleMatch } from "./types";
import { buildRecommendation, rankRecommendations } from "./recommendation";

const baseListing: RentalListing = {
  id: "listing-1",
  platform: "ehi",
  store: {
    id: "store-1",
    platform: "ehi",
    name: "北京通州万达店",
    city: "北京",
    address: "通州区",
    location: { lat: 39.9, lng: 116.65 },
    distanceKm: 8,
    hours: "08:00-22:00"
  },
  vehicleName: "奇瑞 瑞虎8",
  vehicleClass: "中型SUV",
  basePrice: 320,
  platformFees: 35,
  insuranceFees: 50,
  oneWayFee: 0,
  currency: "CNY",
  sourceUrl: "https://www.1hai.cn/",
  dataCompleteness: 0.98,
  warnings: []
};

const exactMatch: VehicleMatch = {
  kind: "exact",
  score: 1,
  label: "精确车型"
};

const taxiRoute: RouteEstimate = {
  mode: "taxi",
  cost: 42,
  durationMinutes: 25,
  distanceKm: 8,
  summary: "打车约 25 分钟"
};

const transitRoute: RouteEstimate = {
  mode: "transit",
  cost: 6,
  durationMinutes: 45,
  distanceKm: 8,
  summary: "地铁+步行约 45 分钟"
};

describe("buildRecommendation", () => {
  it("calculates rental, taxi, transit, and best totals", () => {
    const recommendation = buildRecommendation(baseListing, exactMatch, taxiRoute, transitRoute);

    expect(recommendation.rentalTotal).toBe(405);
    expect(recommendation.taxiTotal).toBe(447);
    expect(recommendation.transitTotal).toBe(411);
    expect(recommendation.bestTotal).toBe(411);
    expect(recommendation.bestRouteMode).toBe("transit");
  });
});

describe("rankRecommendations", () => {
  it("lets a cross-city low rental price win when total cost is lower", () => {
    const local = buildRecommendation(baseListing, exactMatch, taxiRoute, transitRoute);
    const dezhou = buildRecommendation(
      {
        ...baseListing,
        id: "listing-dezhou",
        store: {
          ...baseListing.store,
          id: "store-dezhou",
          name: "德州东站店",
          city: "德州",
          distanceKm: 285
        },
        basePrice: 120,
        platformFees: 25,
        insuranceFees: 40,
        warnings: ["cross-city-pickup"]
      },
      exactMatch,
      {
        mode: "taxi",
        cost: 620,
        durationMinutes: 210,
        distanceKm: 285,
        summary: "跨城打车约 210 分钟"
      },
      {
        mode: "transit",
        cost: 98,
        durationMinutes: 115,
        distanceKm: 285,
        summary: "高铁+市内交通约 115 分钟"
      }
    );

    const ranked = rankRecommendations([local, dezhou]);

    expect(ranked[0].listing.store.name).toBe("德州东站店");
    expect(ranked[0].bestTotal).toBe(283);
    expect(ranked[0].warnings).toContain("cross-city-pickup");
  });

  it("uses exact vehicle match as a tie breaker after total cost", () => {
    const similarMatch: VehicleMatch = {
      kind: "similar-class",
      score: 0.72,
      label: "同级 SUV"
    };
    const exact = buildRecommendation(baseListing, exactMatch, taxiRoute, transitRoute);
    const similar = buildRecommendation(
      {
        ...baseListing,
        id: "listing-similar",
        vehicleName: "哈弗 H6",
        dataCompleteness: 1
      },
      similarMatch,
      taxiRoute,
      transitRoute
    );

    const ranked = rankRecommendations([similar, exact]);

    expect(ranked[0].match.kind).toBe("exact");
  });
});
