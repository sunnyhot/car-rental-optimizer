import CarRentalDomain
import CoreLocation
import Foundation
import MapKit

struct AppleRailStationSuggestionProvider: RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var suggestions: [RailStationSuggestion] = []
        for searchQuery in railStationSearchQueries(for: trimmed) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchQuery
            request.resultTypes = [.address, .pointOfInterest]
            if let origin {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: origin.lat, longitude: origin.lng),
                    latitudinalMeters: 250_000,
                    longitudinalMeters: 250_000
                )
            }

            let response = try await MKLocalSearch(request: request).start()
            let mapped = response.mapItems.compactMap { item -> RailStationSuggestion? in
                railStationSuggestion(from: item, query: trimmed)
            }
            suggestions.append(contentsOf: mapped)
        }

        return Array(rankedUniqueRailStationSuggestions(suggestions).prefix(6))
    }
}

func railStationSearchQueries(for query: String) -> [String] {
    let trimmed = localizedChineseLocationText(query)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    if isRailStationCandidateText(trimmed) {
        return [trimmed]
    }
    return uniqueRailStationSearchQueries([
        "\(trimmed) 高铁站",
        "\(trimmed) 火车站",
        "\(trimmed)站",
        trimmed,
    ])
}

func isRailStationCandidateText(_ text: String) -> Bool {
    let localized = localizedChineseLocationText(text)
    guard !isRejectedRailStationCandidateText(localized) else { return false }
    let explicitTokens = ["火车站", "高铁站", "动车站", "铁路", "客运站"]
    if explicitTokens.contains(where: { localized.contains($0) }) {
        return true
    }
    let compact = localized.replacingOccurrences(of: " ", with: "")
    return compact.hasSuffix("站")
        || compact.contains("东站")
        || compact.contains("西站")
        || compact.contains("南站")
        || compact.contains("北站")
}

func isRejectedRailStationCandidateText(_ text: String) -> Bool {
    let localized = localizedChineseLocationText(text)
    let rejectedTokens = ["机场", "机场大巴", "公交站", "地铁站", "汽车站", "客运中心"]
    return rejectedTokens.contains(where: { localized.contains($0) })
}

func rankedUniqueRailStationSuggestions(_ suggestions: [RailStationSuggestion]) -> [RailStationSuggestion] {
    var seen = Set<String>()
    let unique = suggestions.filter { suggestion in
        let key = localizedChineseLocationText(suggestion.title)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }

    return unique.sorted {
        if stationRank($0) != stationRank($1) {
            return stationRank($0) < stationRank($1)
        }
        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
}

private func railStationSuggestion(from item: MKMapItem, query: String) -> RailStationSuggestion? {
    guard let coordinate = item.placemark.location?.coordinate else { return nil }
    let itemName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = localizedChineseLocationText(itemName?.isEmpty == false ? itemName! : query)
    let subtitle = localizedChineseLocationText([
        item.placemark.locality,
        item.placemark.administrativeArea,
        item.placemark.subLocality,
    ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .joined(separator: " "))
    let combined = "\(title) \(subtitle)"
    guard isRailStationCandidateText(combined) else { return nil }

    let kind: RailStationSuggestionKind = title.contains("东站")
        || title.contains("南站")
        || title.contains("高铁")
        ? .recommended
        : .station

    return RailStationSuggestion(
        id: "rail-\(title)-\(subtitle)-\(coordinate.latitude)-\(coordinate.longitude)",
        title: title,
        subtitle: subtitle,
        point: GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude),
        kind: kind,
        fallbackNote: nil
    )
}

private func stationRank(_ suggestion: RailStationSuggestion) -> Int {
    switch suggestion.kind {
    case .recommended:
        return 0
    case .station:
        return 1
    case .nearestFallback:
        return 2
    }
}

private func uniqueRailStationSearchQueries(_ queries: [String]) -> [String] {
    var seen = Set<String>()
    return queries.filter { query in
        let key = query.replacingOccurrences(of: " ", with: "")
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
}
