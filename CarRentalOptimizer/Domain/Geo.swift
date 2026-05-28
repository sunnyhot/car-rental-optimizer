import Foundation

private let earthRadiusKm: Double = 6371

func distanceKmBetween(_ from: GeoPoint, _ to: GeoPoint) -> Double {
    let latDelta = toRadians(to.lat - from.lat)
    let lngDelta = toRadians(to.lng - from.lng)
    let fromLat = toRadians(from.lat)
    let toLat = toRadians(to.lat)

    let haversine = sin(latDelta / 2) * sin(latDelta / 2)
        + cos(fromLat) * cos(toLat) * sin(lngDelta / 2) * sin(lngDelta / 2)

    return (2 * earthRadiusKm * asin(sqrt(haversine)) * 10).rounded() / 10
}

private func toRadians(_ value: Double) -> Double {
    value * .pi / 180
}
