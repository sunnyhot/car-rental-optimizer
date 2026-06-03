import CarRentalDomain
import Foundation

struct EstimatedMapService: MapService {
    func estimateRoutes(origin: GeoPoint, store: Store) async -> (taxi: RouteEstimate, transit: RouteEstimate) {
        if store.distanceKm >= 80 {
            let taxiMinutes = (store.distanceKm * 0.75).rounded()
            let transitMinutes = (store.distanceKm * 0.35 + 15).rounded()
            let transitCost = (30 + store.distanceKm * 0.24).rounded()

            return (
                taxi: RouteEstimate(
                    mode: .taxi,
                    cost: (90 + store.distanceKm * 2.5).rounded(),
                    durationMinutes: taxiMinutes,
                    distanceKm: store.distanceKm,
                    summary: "跨城打车估算约 \(Int(taxiMinutes)) 分钟"
                ),
                transit: RouteEstimate(
                    mode: .transit,
                    cost: transitCost,
                    durationMinutes: transitMinutes,
                    distanceKm: store.distanceKm,
                    summary: "高铁+市内交通估算约 \(Int(transitMinutes)) 分钟"
                )
            )
        }

        let taxiMinutes = max(8, (store.distanceKm * 1.6 + 12).rounded())
        let transitMinutes = max(15, (store.distanceKm * 2 + 24).rounded())
        let transitCost = store.distanceKm < 1 ? 2 : max(5, (4 + store.distanceKm * 0.16).rounded())

        return (
            taxi: RouteEstimate(
                mode: .taxi,
                cost: max(12, (14 + store.distanceKm * 2.3).rounded()),
                durationMinutes: taxiMinutes,
                distanceKm: store.distanceKm,
                summary: "打车估算约 \(Int(taxiMinutes)) 分钟"
            ),
            transit: RouteEstimate(
                mode: .transit,
                cost: transitCost,
                durationMinutes: transitMinutes,
                distanceKm: store.distanceKm,
                summary: "公交/地铁估算约 \(Int(transitMinutes)) 分钟"
            )
        )
    }
}
