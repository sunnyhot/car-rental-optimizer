import type { PlatformId, RentalListing, SearchRequest } from "../domain/types";

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
  }
};

export function createMockRentalAdapters(): RentalAdapter[] {
  return [
    {
      platform: "ehi",
      async search(request) {
        return filterByRadius(
          [
            {
              id: "ehi-tongzhou-tiggo8",
              platform: "ehi",
              store: STORES.ehiTongzhou,
              vehicleName: "奇瑞 瑞虎8 1.6T 自动",
              vehicleClass: "中型SUV",
              basePrice: 328,
              platformFees: 36,
              insuranceFees: 50,
              oneWayFee: request.returnMode === "different-store" ? 120 : 0,
              currency: "CNY",
              sourceUrl: "https://www.1hai.cn/",
              dataCompleteness: 0.98,
              warnings: []
            },
            {
              id: "ehi-dezhou-tiggo8",
              platform: "ehi",
              store: STORES.ehiDezhou,
              vehicleName: "奇瑞 瑞虎8",
              vehicleClass: "中型SUV",
              basePrice: 120,
              platformFees: 25,
              insuranceFees: 40,
              oneWayFee: request.returnMode === "different-store" ? 180 : 0,
              currency: "CNY",
              sourceUrl: "https://www.1hai.cn/",
              dataCompleteness: 0.92,
              warnings: ["cross-city-pickup"]
            }
          ],
          request.radiusKm
        );
      }
    },
    {
      platform: "car-inc",
      async search(request) {
        return filterByRadius(
          [
            {
              id: "car-south-haval-h6",
              platform: "car-inc",
              store: STORES.carSouth,
              vehicleName: "哈弗 H6 自动",
              vehicleClass: "紧凑型SUV",
              basePrice: 268,
              platformFees: 42,
              insuranceFees: 55,
              oneWayFee: request.returnMode === "different-store" ? 150 : 0,
              currency: "CNY",
              sourceUrl: "https://www.zuche.com/",
              dataCompleteness: 0.95,
              warnings: []
            }
          ],
          request.radiusKm
        );
      }
    }
  ];
}

function filterByRadius(listings: RentalListing[], radiusKm: number): RentalListing[] {
  return listings.filter((listing) => listing.store.distanceKm <= radiusKm);
}
