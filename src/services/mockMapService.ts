import type { GeoPoint, RouteEstimate, Store } from "../domain/types";

export interface MapService {
  estimateRoutes(origin: GeoPoint, store: Store): Promise<{
    taxi: RouteEstimate;
    transit: RouteEstimate;
  }>;
}

export function createMockMapService(): MapService {
  return {
    async estimateRoutes(_origin, store) {
      if (store.name === "德州东站店") {
        return {
          taxi: {
            mode: "taxi",
            cost: 620,
            durationMinutes: 210,
            distanceKm: store.distanceKm,
            summary: "跨城打车约 210 分钟"
          },
          transit: {
            mode: "transit",
            cost: 98,
            durationMinutes: 115,
            distanceKm: store.distanceKm,
            summary: "高铁+市内交通约 115 分钟"
          }
        };
      }

      if (store.name === "北京南站店") {
        return {
          taxi: {
            mode: "taxi",
            cost: 88,
            durationMinutes: 55,
            distanceKm: store.distanceKm,
            summary: "打车约 55 分钟"
          },
          transit: {
            mode: "transit",
            cost: 9,
            durationMinutes: 70,
            distanceKm: store.distanceKm,
            summary: "地铁换乘约 70 分钟"
          }
        };
      }

      return {
        taxi: {
          mode: "taxi",
          cost: 36,
          durationMinutes: 22,
          distanceKm: store.distanceKm,
          summary: "打车约 22 分钟"
        },
        transit: {
          mode: "transit",
          cost: 5,
          durationMinutes: 38,
          distanceKm: store.distanceKm,
          summary: "公交/地铁约 38 分钟"
        }
      };
    }
  };
}
