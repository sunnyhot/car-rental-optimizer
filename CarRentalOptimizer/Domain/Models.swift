import Foundation

// MARK: - Enums

enum PlatformId: String, CaseIterable, Codable {
    case ehi
    case carInc = "car-inc"
}

enum ReturnMode: String, CaseIterable, Codable {
    case sameStore = "same-store"
    case differentStore = "different-store"
}

enum MatchKind: String, Codable {
    case exact
    case similarClass = "similar-class"
    case lowConfidence = "low-confidence"
    case notSpecified = "not-specified"
}

enum RouteMode: String, Codable {
    case taxi
    case transit
}

enum ResultWarning: String, Codable {
    case crossCityPickup = "cross-city-pickup"
    case partialPrice = "partial-price"
    case loginRequired = "login-required"
    case captchaRequired = "captcha-required"
    case mapCostMissing = "map-cost-missing"
}

// MARK: - Structs

struct GeoPoint: Codable, Equatable {
    let lat: Double
    let lng: Double
}

struct SearchRequest: Codable, Equatable {
    var origin: GeoPoint
    var originLabel: String
    var pickupAt: String
    var returnAt: String
    var returnMode: ReturnMode
    var radiusKm: Double
    var vehicleQuery: String
    var platforms: [PlatformId]
}

struct Store: Codable, Equatable, Identifiable {
    let id: String
    let platform: PlatformId
    let name: String
    let city: String
    let address: String
    let location: GeoPoint
    let distanceKm: Double
    let hours: String
}

struct RentalListing: Codable, Equatable, Identifiable {
    let id: String
    let platform: PlatformId
    let store: Store
    let vehicleName: String
    let vehicleClass: String
    let basePrice: Double
    let platformFees: Double
    let insuranceFees: Double
    let oneWayFee: Double
    let currency: String
    let sourceUrl: String
    let dataCompleteness: Double
    let warnings: [ResultWarning]
}

struct VehicleMatch: Codable, Equatable {
    let kind: MatchKind
    let score: Double
    let label: String
}

struct RouteEstimate: Codable, Equatable {
    let mode: RouteMode
    let cost: Double
    let durationMinutes: Int
    let distanceKm: Double
    let summary: String
}

struct Recommendation: Codable, Equatable, Identifiable {
    var id: String { listing.id }
    let listing: RentalListing
    let match: VehicleMatch
    let taxiRoute: RouteEstimate
    let transitRoute: RouteEstimate
    let rentalTotal: Double
    let taxiTotal: Double
    let transitTotal: Double
    let bestTotal: Double
    let bestRouteMode: RouteMode
    let warnings: [ResultWarning]
}

// MARK: - Platform Labels

extension PlatformId {
    var label: String {
        switch self {
        case .ehi: return "一嗨"
        case .carInc: return "神州"
        }
    }
}

extension ReturnMode {
    var label: String {
        switch self {
        case .sameStore: return "同店取还"
        case .differentStore: return "异店/异地还车"
        }
    }
}

extension MatchKind: Comparable {
    static func < (lhs: MatchKind, rhs: MatchKind) -> Bool {
        let order: [MatchKind] = [.exact, .similarClass, .lowConfidence, .notSpecified]
        guard let leftIndex = order.firstIndex(of: lhs),
              let rightIndex = order.firstIndex(of: rhs) else { return false }
        return leftIndex > rightIndex
    }
}
