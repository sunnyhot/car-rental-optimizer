import CarRentalDomain
@preconcurrency import CoreLocation
import Foundation
import MapKit

struct ResolvedLocation: Equatable {
    let label: String
    let point: GeoPoint
}

struct AddressSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let point: GeoPoint

    var displayName: String {
        let localizedTitle = localizedChineseLocationText(title)
        let localizedSubtitle = localizedChineseLocationText(subtitle)
        return localizedSubtitle.isEmpty ? localizedTitle : "\(localizedTitle)，\(localizedSubtitle)"
    }
}

protocol CurrentLocationProviding {
    func currentLocation() async throws -> ResolvedLocation
}

protocol AddressSuggestionProviding {
    func suggestions(for query: String, near origin: GeoPoint?) async throws -> [AddressSuggestion]
}

enum CurrentLocationError: LocalizedError {
    case denied
    case disabled
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "定位权限未开启，可手动输入地址。"
        case .disabled:
            return "系统定位服务未开启，可手动输入地址。"
        case .unavailable:
            return "暂时没有获取到当前位置。"
        }
    }
}

@MainActor
final class AppleCurrentLocationProvider: NSObject, CurrentLocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    func currentLocation() async throws -> ResolvedLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw CurrentLocationError.disabled
        }

        let location = try await requestLocation()
        return ResolvedLocation(
            label: await reverseGeocodeLabel(for: location),
            point: GeoPoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        )
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            self.manager = manager
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await MainActor.run {
                    self?.finish(with: .failure(CurrentLocationError.unavailable))
                }
            }

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                finish(with: .failure(CurrentLocationError.denied))
            @unknown default:
                finish(with: .failure(CurrentLocationError.unavailable))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(CurrentLocationError.denied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(CurrentLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(CurrentLocationError.unavailable))
            return
        }
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.delegate = nil
        manager = nil

        switch result {
        case let .success(location):
            continuation.resume(returning: location)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func reverseGeocodeLabel(for location: CLLocation) async -> String {
        let fallback = String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: preferredChineseLocationLocale).first else {
            return fallback
        }

        let parts = [
            placemark.locality,
            placemark.subLocality,
            placemark.name,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        let label = unique(parts).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? fallback : localizedChineseLocationText(label)
    }
}

struct AppleAddressSuggestionProvider: AddressSuggestionProviding {
    func suggestions(for query: String, near origin: GeoPoint?) async throws -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let origin {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: origin.lat, longitude: origin.lng),
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        var suggestions: [AddressSuggestion] = []
        for item in response.mapItems.prefix(8) {
            guard let point = item.placemark.location?.coordinate else { continue }
            let fallbackTitle = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackSubtitle = suggestionSubtitle(for: item.placemark)
            let text = await localizedSuggestionText(
                for: point,
                fallbackTitle: fallbackTitle?.isEmpty == false ? fallbackTitle! : trimmed,
                fallbackSubtitle: fallbackSubtitle
            )
            suggestions.append(AddressSuggestion(
                id: "\(text.title)-\(text.subtitle)-\(point.latitude)-\(point.longitude)",
                title: text.title,
                subtitle: text.subtitle,
                point: GeoPoint(lat: point.latitude, lng: point.longitude)
            ))
        }
        return uniqueSuggestions(suggestions)
    }

    private func localizedSuggestionText(
        for coordinate: CLLocationCoordinate2D,
        fallbackTitle: String,
        fallbackSubtitle: String
    ) async -> (title: String, subtitle: String) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: preferredChineseLocationLocale).first {
            let title = unique([
                placemark.name,
                placemark.subLocality,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .joined(separator: " ")
            let subtitle = unique([
                placemark.locality,
                placemark.administrativeArea,
                placemark.thoroughfare,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .joined(separator: " ")

            if !title.isEmpty || !subtitle.isEmpty {
                return (
                    localizedChineseLocationText(title.isEmpty ? fallbackTitle : title),
                    localizedChineseLocationText(subtitle)
                )
            }
        }

        return (
            localizedChineseLocationText(fallbackTitle),
            localizedChineseLocationText(fallbackSubtitle)
        )
    }

    private func suggestionSubtitle(for placemark: MKPlacemark) -> String {
        unique([
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
        .joined(separator: " ")
    }

    private func uniqueSuggestions(_ suggestions: [AddressSuggestion]) -> [AddressSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { suggestion in
            let key = "\(suggestion.title)-\(suggestion.subtitle)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

private func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { value in
        guard !seen.contains(value) else { return false }
        seen.insert(value)
        return true
    }
}

let preferredChineseLocationLocale = Locale(identifier: "zh_CN")

func localizedChineseLocationText(_ text: String) -> String {
    var result = text.replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    for replacement in chineseLocationReplacements {
        result = result.replacingOccurrences(
            of: replacement.english,
            with: replacement.chinese,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
    }
    return result.replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func originCityCandidates(from label: String) -> [String] {
    let localized = localizedChineseLocationText(label)
    let lowercased = label.lowercased()
    var candidates: [String] = []
    for city in chineseCityAliases {
        if localized.contains(city.chinese) || city.aliases.contains(where: { lowercased.contains($0) }) {
            candidates.append(city.chinese)
        }
    }
    return unique(candidates)
}

private let chineseLocationReplacements: [(english: String, chinese: String)] = [
    ("Jingdong Group Quanqiu Headquarters Beijing No.2Park", "京东集团全球总部2号园区"),
    ("Jinghai Road Subway Station West Entrance Exit A1 Pedestrian 120 Meters", "经海路地铁站A1西口步行120米"),
    ("Beijing Economic and Technological Development Zone", "北京经济技术开发区"),
    ("Beijing Tongzhou", "北京通州"),
    ("Tongzhou District", "通州区"),
    ("Beijing", "北京"),
    ("Tongzhou", "通州"),
    ("Shanghai", "上海"),
    ("Guangzhou", "广州"),
    ("Shenzhen", "深圳"),
    ("Hangzhou", "杭州"),
    ("Nanjing", "南京"),
    ("Suzhou", "苏州"),
    ("Chengdu", "成都"),
    ("Wuhan", "武汉"),
    ("Tianjin", "天津"),
    ("Chongqing", "重庆"),
    ("Xi'an", "西安"),
]

private let chineseCityAliases: [(chinese: String, aliases: [String])] = [
    ("北京", ["beijing", "peking"]),
    ("通州", ["tongzhou"]),
    ("上海", ["shanghai"]),
    ("广州", ["guangzhou", "canton"]),
    ("深圳", ["shenzhen"]),
    ("杭州", ["hangzhou"]),
    ("南京", ["nanjing"]),
    ("苏州", ["suzhou"]),
    ("成都", ["chengdu"]),
    ("武汉", ["wuhan"]),
    ("天津", ["tianjin"]),
    ("重庆", ["chongqing"]),
    ("西安", ["xi'an", "xian"]),
]
