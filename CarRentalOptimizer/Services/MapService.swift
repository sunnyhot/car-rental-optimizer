import Foundation

protocol MapService {
    func estimateRoutes(origin: GeoPoint, store: Store) async -> (taxi: RouteEstimate, transit: RouteEstimate)
}

struct MockMapService: MapService {
    func estimateRoutes(origin: GeoPoint, store: Store) async -> (taxi: RouteEstimate, transit: RouteEstimate) {
        if store.distanceKm >= 80 {
            let taxiMinutes = Int((store.distanceKm * 0.75).rounded())
            let transitMinutes = Int((store.distanceKm * 0.35 + 15).rounded())
            let transitCost = Int((30 + store.distanceKm * 0.24).rounded())

            return (
                taxi: RouteEstimate(
                    mode: .taxi, cost: Double(Int((90 + store.distanceKm * 2.5).rounded())),
                    durationMinutes: taxiMinutes, distanceKm: store.distanceKm,
                    summary: "跨城打车约 \(taxiMinutes) 分钟"
                ),
                transit: RouteEstimate(
                    mode: .transit, cost: Double(transitCost),
                    durationMinutes: transitMinutes, distanceKm: store.distanceKm,
                    summary: "高铁+市内交通约 \(transitMinutes) 分钟"
                )
            )
        }

        let taxiMinutes = max(8, Int((store.distanceKm * 1.6 + 12).rounded()))
        let transitMinutes = max(15, Int((store.distanceKm * 2 + 24).rounded()))
        let transitCost = store.distanceKm < 1 ? 2 : max(5, Int((4 + store.distanceKm * 0.16).rounded()))

        return (
            taxi: RouteEstimate(
                mode: .taxi, cost: Double(max(12, Int((14 + store.distanceKm * 2.3).rounded()))),
                durationMinutes: taxiMinutes, distanceKm: store.distanceKm,
                summary: "打车约 \(taxiMinutes) 分钟"
            ),
            transit: RouteEstimate(
                mode: .transit, cost: Double(transitCost),
                durationMinutes: transitMinutes, distanceKm: store.distanceKm,
                summary: "公交/地铁约 \(transitMinutes) 分钟"
            )
        )
    }
}
