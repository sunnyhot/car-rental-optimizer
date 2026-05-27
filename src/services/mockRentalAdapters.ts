import type { PlatformId, RentalListing, SearchRequest } from "../domain/types";
import { distanceKmBetween } from "../domain/geo";
import { calculateRentalDays } from "../domain/searchSummary";

export interface RentalAdapter {
  platform: PlatformId;
  search(request: SearchRequest): Promise<RentalListing[]>;
}

const STORES = {
  ehiTongzhou: {
    id: "ehi-tongzhou",
    platform: "ehi" as const,
    name: "北京通州万达店",
    city: "北京",
    address: "北京市通州区万达广场附近",
    location: { lat: 39.909, lng: 116.657 },
    distanceKm: 6.8,
    hours: "08:00-22:00"
  },
  ehiDezhou: {
    id: "ehi-dezhou-east",
    platform: "ehi" as const,
    name: "德州东站店",
    city: "德州",
    address: "德州市德州东站出站口附近",
    location: { lat: 37.443, lng: 116.374 },
    distanceKm: 286,
    hours: "08:00-20:00"
  },
  carSouth: {
    id: "car-beijing-south",
    platform: "car-inc" as const,
    name: "北京南站店",
    city: "北京",
    address: "北京市丰台区北京南站",
    location: { lat: 39.865, lng: 116.379 },
    distanceKm: 32,
    hours: "07:30-22:30"
  },
  carTongzhouCompact: {
    id: "car-tongzhou-compact",
    platform: "car-inc" as const,
    name: "北京通州北苑店",
    city: "北京",
    address: "北京市通州区北苑附近",
    location: { lat: 39.903, lng: 116.642 },
    distanceKm: 4.2,
    hours: "08:00-21:00"
  }
};

export function createMockRentalAdapters(): RentalAdapter[] {
  return [
    {
      platform: "ehi",
      async search(request) {
        const rentalDays = calculateRentalDays(request);

        return filterByRadius(
          [
            {
              id: "ehi-tongzhou-tiggo8",
              platform: "ehi" as const,
              store: STORES.ehiTongzhou,
              vehicleName: "奇瑞 瑞虎8 1.6T 自动",
              vehicleClass: "中型SUV",
              basePrice: dailyTotal(328, rentalDays),
              platformFees: 36,
              insuranceFees: 50,
              oneWayFee: request.returnMode === "different-store" ? 120 : 0,
              currency: "CNY" as const,
              sourceUrl: "https://www.1hai.cn/",
              dataCompleteness: 0.98,
              warnings: [] as RentalListing["warnings"]
            },
            {
              id: "ehi-dezhou-tiggo8",
              platform: "ehi" as const,
              store: STORES.ehiDezhou,
              vehicleName: "奇瑞 瑞虎8",
              vehicleClass: "中型SUV",
              basePrice: dailyTotal(120, rentalDays),
              platformFees: 25,
              insuranceFees: 40,
              oneWayFee: request.returnMode === "different-store" ? 180 : 0,
              currency: "CNY" as const,
              sourceUrl: "https://www.1hai.cn/",
              dataCompleteness: 0.92,
              warnings: ["cross-city-pickup"] as RentalListing["warnings"]
            }
          ].map((listing) => withDynamicDistance(listing, request)),
          request.radiusKm
        );
      }
    },
    {
      platform: "car-inc",
      async search(request) {
        const rentalDays = calculateRentalDays(request);

        return filterByRadius(
          [
            {
              id: "car-south-haval-h6",
              platform: "car-inc" as const,
              store: STORES.carSouth,
              vehicleName: "哈弗 H6 自动",
              vehicleClass: "紧凑型SUV",
              basePrice: dailyTotal(268, rentalDays),
              platformFees: 42,
              insuranceFees: 55,
              oneWayFee: request.returnMode === "different-store" ? 150 : 0,
              currency: "CNY" as const,
              sourceUrl: "https://www.zuche.com/",
              dataCompleteness: 0.95,
              warnings: [] as RentalListing["warnings"]
            },
            {
              id: "car-tongzhou-lavida",
              platform: "car-inc" as const,
              store: STORES.carTongzhouCompact,
              vehicleName: "大众 朗逸 自动",
              vehicleClass: "紧凑型轿车",
              basePrice: dailyTotal(98, rentalDays),
              platformFees: 30,
              insuranceFees: 45,
              oneWayFee: request.returnMode === "different-store" ? 100 : 0,
              currency: "CNY" as const,
              sourceUrl: "https://www.zuche.com/",
              dataCompleteness: 0.94,
              warnings: [] as RentalListing["warnings"]
            }
          ].map((listing) => withDynamicDistance(listing, request)),
          request.radiusKm
        );
      }
    }
  ];
}

function filterByRadius(listings: RentalListing[], radiusKm: number): RentalListing[] {
  return listings.filter((listing) => listing.store.distanceKm <= radiusKm);
}

function dailyTotal(dailyPrice: number, rentalDays: number): number {
  return dailyPrice * rentalDays;
}

function withDynamicDistance(listing: RentalListing, request: SearchRequest): RentalListing {
  const distanceKm = distanceKmBetween(request.origin, listing.store.location);
  const warnings = new Set(listing.warnings);

  if (distanceKm >= 80) {
    warnings.add("cross-city-pickup");
  } else {
    warnings.delete("cross-city-pickup");
  }

  return {
    ...listing,
    store: {
      ...listing.store,
      distanceKm
    },
    warnings: Array.from(warnings)
  };
}
