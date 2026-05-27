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
      if (store.distanceKm >= 80) {
        const taxiMinutes = Math.round(store.distanceKm * 0.75);
        const transitMinutes = Math.round(store.distanceKm * 0.35 + 15);
        const transitCost = Math.round(30 + store.distanceKm * 0.24);

        return {
          taxi: {
            mode: "taxi",
            cost: Math.round(90 + store.distanceKm * 2.5),
            durationMinutes: taxiMinutes,
            distanceKm: store.distanceKm,
            summary: `跨城打车约 ${taxiMinutes} 分钟`
          },
          transit: {
            mode: "transit",
            cost: transitCost,
            durationMinutes: transitMinutes,
            distanceKm: store.distanceKm,
            summary: `高铁+市内交通约 ${transitMinutes} 分钟`
          }
        };
      }

      const taxiMinutes = Math.max(8, Math.round(store.distanceKm * 1.6 + 12));
      const transitMinutes = Math.max(15, Math.round(store.distanceKm * 2 + 24));
      const transitCost = store.distanceKm < 1 ? 2 : Math.max(5, Math.round(4 + store.distanceKm * 0.16));

      return {
        taxi: {
          mode: "taxi",
          cost: Math.max(12, Math.round(14 + store.distanceKm * 2.3)),
          durationMinutes: taxiMinutes,
          distanceKm: store.distanceKm,
          summary: `打车约 ${taxiMinutes} 分钟`
        },
        transit: {
          mode: "transit",
          cost: transitCost,
          durationMinutes: transitMinutes,
          distanceKm: store.distanceKm,
          summary: `公交/地铁约 ${transitMinutes} 分钟`
        }
      };
    }
  };
}
