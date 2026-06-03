import CarRentalDomain
import Foundation
import MapKit

struct AppleMapService: MapService {
    private let fallback = EstimatedMapService()

    func estimateRoutes(origin: GeoPoint, store: Store) async -> (taxi: RouteEstimate, transit: RouteEstimate) {
        async let driving = route(origin: origin, destination: store.location, transportType: .automobile)
        async let transit = route(origin: origin, destination: store.location, transportType: .transit)

        let drivingRoute = await driving
        let transitRoute = await transit

        if drivingRoute == nil && transitRoute == nil {
            return await fallback.estimateRoutes(origin: origin, store: store)
        }

        let fallbackRoutes = await fallback.estimateRoutes(origin: origin, store: store)
        let taxiEstimate = drivingRoute.map { route in
            let km = route.distance / 1000
            let minutes = max(1, route.expectedTravelTime / 60)
            return RouteEstimate(
                mode: .taxi,
                cost: estimateTaxiCost(distanceKm: km),
                durationMinutes: minutes.rounded(),
                distanceKm: km,
                summary: "驾车路线约 \(Int(minutes.rounded())) 分钟"
            )
        } ?? fallbackRoutes.taxi

        let transitEstimate = transitRoute.map { route in
            let km = route.distance / 1000
            let minutes = max(1, route.expectedTravelTime / 60)
            return RouteEstimate(
                mode: .transit,
                cost: estimateTransitCost(distanceKm: km),
                durationMinutes: minutes.rounded(),
                distanceKm: km,
                summary: "公共交通路线约 \(Int(minutes.rounded())) 分钟"
            )
        } ?? fallbackRoutes.transit

        return (taxi: taxiEstimate, transit: transitEstimate)
    }

    private func route(origin: GeoPoint, destination: GeoPoint, transportType: MKDirectionsTransportType) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transportType

        do {
            return try await MKDirections(request: request).calculate().routes.first
        } catch {
            return nil
        }
    }

    private func estimateTaxiCost(distanceKm: Double) -> Double {
        let base = 13.0
        let chargedDistance = max(0, distanceKm - 3)
        return max(base, (base + chargedDistance * 2.3).rounded())
    }

    private func estimateTransitCost(distanceKm: Double) -> Double {
        switch distanceKm {
        case ..<6:
            return 3
        case ..<12:
            return 4
        case ..<22:
            return 5
        case ..<32:
            return 6
        default:
            return (6 + ceil((distanceKm - 32) / 20)).rounded()
        }
    }
}

private extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
