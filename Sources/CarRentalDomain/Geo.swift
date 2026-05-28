import Foundation

private let EARTH_RADIUS_KM: Double = 6371

/// Calculates the Haversine distance (in km) between two geographic points.
/// Result is rounded to one decimal place.
public func distanceKmBetween(from: GeoPoint, to: GeoPoint) -> Double {
    let latDelta = toRadians(to.lat - from.lat)
    let lngDelta = toRadians(to.lng - from.lng)
    let fromLat = toRadians(from.lat)
    let toLat = toRadians(to.lat)

    let haversine =
        sin(latDelta / 2) * sin(latDelta / 2) +
        cos(fromLat) * cos(toLat) * sin(lngDelta / 2) * sin(lngDelta / 2)

    return round(2 * EARTH_RADIUS_KM * asin(sqrt(haversine)) * 10) / 10
}

private func toRadians(_ value: Double) -> Double {
    value * .pi / 180
}
