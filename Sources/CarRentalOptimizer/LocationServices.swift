import CarRentalDomain
import CoreLocation
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
        subtitle.isEmpty ? title : "\(title)，\(subtitle)"
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
final class AppleCurrentLocationProvider: NSObject, CurrentLocationProviding, @preconcurrency CLLocationManagerDelegate {
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
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
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
        return label.isEmpty ? fallback : label
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
        return uniqueSuggestions(response.mapItems.prefix(8).compactMap { item in
            guard let point = item.placemark.location?.coordinate else { return nil }
            let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = suggestionSubtitle(for: item.placemark)
            let displayTitle = title?.isEmpty == false ? title! : trimmed
            return AddressSuggestion(
                id: "\(displayTitle)-\(subtitle)-\(point.latitude)-\(point.longitude)",
                title: displayTitle,
                subtitle: subtitle,
                point: GeoPoint(lat: point.latitude, lng: point.longitude)
            )
        })
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
