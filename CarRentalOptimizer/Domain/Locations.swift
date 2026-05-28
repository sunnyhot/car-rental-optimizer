import Foundation

private struct KnownOrigin {
    let keywords: [String]
    let point: GeoPoint
}

private let knownOrigins: [KnownOrigin] = [
    KnownOrigin(keywords: ["北京通州", "通州"], point: GeoPoint(lat: 39.9169, lng: 116.6462)),
    KnownOrigin(keywords: ["北京南站"], point: GeoPoint(lat: 39.865, lng: 116.379)),
    KnownOrigin(keywords: ["德州东站", "德州"], point: GeoPoint(lat: 37.443, lng: 116.374)),
    KnownOrigin(keywords: ["天津南站", "天津"], point: GeoPoint(lat: 39.0622, lng: 117.0669)),
    KnownOrigin(keywords: ["济南西站", "济南"], point: GeoPoint(lat: 36.6683, lng: 116.892)),
    KnownOrigin(keywords: ["上海虹桥", "虹桥"], point: GeoPoint(lat: 31.194, lng: 121.318))
]

func resolveKnownOrigin(_ label: String) -> GeoPoint? {
    let normalized = label.trimmingCharacters(in: .whitespaces).lowercased()
    return knownOrigins.first { origin in
        origin.keywords.contains { keyword in
            normalized.contains(keyword.lowercased())
        }
    }?.point
}
