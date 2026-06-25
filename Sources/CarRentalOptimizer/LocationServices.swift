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
            return "暂时没有获取到当前位置，可重试定位或手动输入地址。"
        }
    }

    static func normalized(_ error: Error) -> Error {
        guard let code = coreLocationCode(for: error) else { return error }

        switch code {
        case .denied:
            return CurrentLocationError.denied
        case .locationUnknown, .network:
            return CurrentLocationError.unavailable
        default:
            return error
        }
    }

    static func displayDescription(for error: Error) -> String {
        normalized(error).localizedDescription
    }

    static func isRetryable(_ error: Error) -> Bool {
        let normalizedError = normalized(error)
        if let currentLocationError = normalizedError as? CurrentLocationError {
            return currentLocationError == .unavailable
        }

        guard let code = coreLocationCode(for: normalizedError) else { return true }
        return code == .locationUnknown || code == .network
    }

    static func coreLocationCode(for error: Error) -> CLError.Code? {
        if let clError = error as? CLError {
            return clError.code
        }

        let nsError = error as NSError
        guard nsError.domain == kCLErrorDomain else { return nil }
        return CLError.Code(rawValue: nsError.code)
    }
}

@MainActor
final class AppleCurrentLocationProvider: NSObject, CurrentLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var activeLocationRequest: Task<CLLocation, Error>?
    private var bestLocation: CLLocation?

    func currentLocation() async throws -> ResolvedLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw CurrentLocationError.disabled
        }

        let location = try await requestCoalescedLocation()
        return ResolvedLocation(
            label: await reverseGeocodeLabel(for: location),
            point: GeoPoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        )
    }

    private func requestCoalescedLocation() async throws -> CLLocation {
        if let activeLocationRequest {
            return try await activeLocationRequest.value
        }

        let task = Task<CLLocation, Error> { @MainActor in
            try await self.requestLocation()
        }
        activeLocationRequest = task
        defer {
            activeLocationRequest = nil
        }
        return try await task.value
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
            self.manager = manager
            self.continuation = continuation
            bestLocation = nil
            timeoutTask?.cancel()
            timeoutTask = nil

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                startUpdatingLocation(with: manager)
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
            startUpdatingLocation(with: manager)
        case .denied, .restricted:
            finish(with: .failure(CurrentLocationError.denied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(CurrentLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let candidates = locations + (bestLocation.map { [$0] } ?? [])
        guard let location = bestCurrentLocation(from: candidates) else {
            finish(with: .failure(CurrentLocationError.unavailable))
            return
        }
        bestLocation = location

        if location.horizontalAccuracy <= preferredCurrentLocationAccuracyMeters {
            finish(with: .success(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if CurrentLocationError.coreLocationCode(for: error) == .locationUnknown {
            return
        }
        finish(with: .failure(CurrentLocationError.normalized(error)))
    }

    private func startUpdatingLocation(with manager: CLLocationManager) {
        guard self.manager === manager, continuation != nil else { return }
        manager.startUpdatingLocation()
        startLocationTimeout()
    }

    private func startLocationTimeout() {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: currentLocationWaitTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let location = bestLocation {
                    finish(with: .success(location))
                } else {
                    finish(with: .failure(CurrentLocationError.unavailable))
                }
            }
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        bestLocation = nil

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

let preferredCurrentLocationAccuracyMeters: CLLocationAccuracy = 200
let currentLocationWaitTimeoutNanoseconds: UInt64 = 3_500_000_000

func bestCurrentLocation(from locations: [CLLocation]) -> CLLocation? {
    let validLocations = locations.filter { $0.horizontalAccuracy >= 0 }
    return validLocations.min { lhs, rhs in
        if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.horizontalAccuracy < rhs.horizontalAccuracy
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
