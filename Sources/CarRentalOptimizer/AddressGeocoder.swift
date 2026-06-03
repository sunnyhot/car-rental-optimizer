import CarRentalDomain
import CoreLocation
import Foundation

protocol AddressGeocoding {
    func geocode(_ address: String) async throws -> GeoPoint
}

struct AppleAddressGeocoder: AddressGeocoding {
    func geocode(_ address: String) async throws -> GeoPoint {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AddressGeocodingError.emptyAddress
        }

        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(trimmed)
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw AddressGeocodingError.notFound
        }
        return GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude)
    }
}

struct CurrentRequestGeocoder: AddressGeocoding {
    let point: GeoPoint

    func geocode(_ address: String) async throws -> GeoPoint {
        point
    }
}

enum AddressGeocodingError: LocalizedError {
    case emptyAddress
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "请输入当前位置。"
        case .notFound:
            return "没有识别到这个地址的位置。"
        }
    }
}
