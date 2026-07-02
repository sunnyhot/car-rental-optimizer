import CarRentalDomain
import Foundation

enum OriginSuggestionKind: Equatable {
    case address
    case railStation
    case nearestRailStationFallback

    var systemImage: String {
        switch self {
        case .address:
            return "mappin.circle.fill"
        case .railStation:
            return "tram.fill"
        case .nearestRailStationFallback:
            return "tram.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .address:
            return "地址"
        case .railStation:
            return "车站"
        case .nearestRailStationFallback:
            return "附近车站"
        }
    }
}

struct OriginSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let point: GeoPoint
    let kind: OriginSuggestionKind
    let fallbackNote: String?

    var displayName: String {
        let localizedTitle = localizedChineseLocationText(title)
        let localizedSubtitle = localizedChineseLocationText(subtitle)
        return localizedSubtitle.isEmpty ? localizedTitle : "\(localizedTitle)，\(localizedSubtitle)"
    }

    static func address(_ suggestion: AddressSuggestion) -> OriginSuggestion {
        OriginSuggestion(
            id: suggestion.id,
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            point: suggestion.point,
            kind: .address,
            fallbackNote: nil
        )
    }

    static func railStation(_ suggestion: RailStationSuggestion) -> OriginSuggestion {
        OriginSuggestion(
            id: suggestion.id,
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            point: suggestion.point,
            kind: suggestion.kind.originSuggestionKind,
            fallbackNote: suggestion.fallbackNote
        )
    }
}

enum RailStationSuggestionKind: Equatable {
    case recommended
    case station
    case nearestFallback

    var originSuggestionKind: OriginSuggestionKind {
        switch self {
        case .recommended, .station:
            return .railStation
        case .nearestFallback:
            return .nearestRailStationFallback
        }
    }
}

struct RailStationSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let point: GeoPoint
    let kind: RailStationSuggestionKind
    let fallbackNote: String?
}

protocol RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion]
}

struct EmptyRailStationSuggestionProvider: RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        []
    }
}

func mergeOriginSuggestions(
    railStations: [RailStationSuggestion],
    addresses: [AddressSuggestion]
) -> [OriginSuggestion] {
    let ordered = railStations.map(OriginSuggestion.railStation) + addresses.map(OriginSuggestion.address)
    var seen = Set<String>()
    return ordered.filter { suggestion in
        let key = normalizedOriginSuggestionKey(suggestion)
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
}

func isKnownCityLevelOrigin(_ value: String) -> Bool {
    let localized = localizedChineseLocationText(value)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard localized.count >= 2 else { return false }

    let detailMarkers = ["站", "区", "县", "镇", "街", "路", "号", "机场", "园区", "广场", "大学", "酒店"]
    if detailMarkers.contains(where: { localized.contains($0) }) {
        return false
    }

    let withoutCitySuffix = localized.hasSuffix("市") ? String(localized.dropLast()) : localized
    let aliases = originCityCandidates(from: localized)
    if aliases.contains(where: { alias in localized == alias || withoutCitySuffix == alias }) {
        return true
    }
    return localized.hasSuffix("市")
}

private func normalizedOriginSuggestionKey(_ suggestion: OriginSuggestion) -> String {
    let title = localizedChineseLocationText(suggestion.title)
        .replacingOccurrences(of: " ", with: "")
        .lowercased()
    let subtitle = localizedChineseLocationText(suggestion.subtitle)
        .replacingOccurrences(of: " ", with: "")
        .lowercased()
    return "\(title)|\(subtitle)"
}
