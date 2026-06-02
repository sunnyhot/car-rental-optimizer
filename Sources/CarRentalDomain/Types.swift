import Foundation

// MARK: - Enums

/// Represents a rental platform identifier.
public enum PlatformId: String, Codable, Equatable, CaseIterable {
    case ehi
    case carInc = "car-inc"
}

/// How the rental vehicle should be returned.
public enum ReturnMode: String, Codable, Equatable, CaseIterable {
    case sameStore = "same-store"
    case differentStore = "different-store"
}

/// How closely a listing matches the user's requested vehicle.
public enum MatchKind: String, Codable, Equatable {
    case exact
    case similarClass = "similar-class"
    case lowConfidence = "low-confidence"
    case notSpecified = "not-specified"
}

/// Transportation mode for reaching the rental store.
public enum RouteMode: String, Codable, Equatable {
    case taxi
    case transit
}

/// Warning flags attached to a rental listing.
public enum ResultWarning: String, Codable, Equatable {
    case crossCityPickup = "cross-city-pickup"
    case partialPrice = "partial-price"
    case loginRequired = "login-required"
    case captchaRequired = "captcha-required"
    case mapCostMissing = "map-cost-missing"
}

// MARK: - Structs

/// A geographic coordinate.
public struct GeoPoint: Codable, Equatable {
    public let lat: Double
    public let lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

/// A rental search request.
public struct SearchRequest: Codable, Equatable {
    public var origin: GeoPoint
    public var originLabel: String
    public var pickupAt: String
    public var returnAt: String
    public var returnMode: ReturnMode
    public var radiusKm: Double
    public var vehicleQuery: String
    public var platforms: [PlatformId]

    public init(
        origin: GeoPoint,
        originLabel: String,
        pickupAt: String,
        returnAt: String,
        returnMode: ReturnMode,
        radiusKm: Double,
        vehicleQuery: String,
        platforms: [PlatformId]
    ) {
        self.origin = origin
        self.originLabel = originLabel
        self.pickupAt = pickupAt
        self.returnAt = returnAt
        self.returnMode = returnMode
        self.radiusKm = radiusKm
        self.vehicleQuery = vehicleQuery
        self.platforms = platforms
    }
}

/// A rental store / pickup location.
public struct Store: Codable, Equatable, Identifiable {
    public let id: String
    public let platform: PlatformId
    public let name: String
    public let city: String
    public let address: String
    public let location: GeoPoint
    public let distanceKm: Double
    public let hours: String

    public init(
        id: String,
        platform: PlatformId,
        name: String,
        city: String,
        address: String,
        location: GeoPoint,
        distanceKm: Double,
        hours: String
    ) {
        self.id = id
        self.platform = platform
        self.name = name
        self.city = city
        self.address = address
        self.location = location
        self.distanceKm = distanceKm
        self.hours = hours
    }
}

/// A rental listing from a platform.
public struct RentalListing: Codable, Equatable, Identifiable {
    public let id: String
    public let platform: PlatformId
    public let store: Store
    public let vehicleName: String
    public let vehicleClass: String
    public let basePrice: Double
    public let platformFees: Double
    public let insuranceFees: Double
    public let oneWayFee: Double
    public let currency: String
    public let sourceUrl: String
    public let dataCompleteness: Double
    public let warnings: [ResultWarning]

    public init(
        id: String,
        platform: PlatformId,
        store: Store,
        vehicleName: String,
        vehicleClass: String,
        basePrice: Double,
        platformFees: Double,
        insuranceFees: Double,
        oneWayFee: Double,
        currency: String = "CNY",
        sourceUrl: String,
        dataCompleteness: Double,
        warnings: [ResultWarning] = []
    ) {
        self.id = id
        self.platform = platform
        self.store = store
        self.vehicleName = vehicleName
        self.vehicleClass = vehicleClass
        self.basePrice = basePrice
        self.platformFees = platformFees
        self.insuranceFees = insuranceFees
        self.oneWayFee = oneWayFee
        self.currency = currency
        self.sourceUrl = sourceUrl
        self.dataCompleteness = dataCompleteness
        self.warnings = warnings
    }
}

/// The result of matching a listing against the user's vehicle query.
public struct VehicleMatch: Codable, Equatable {
    public let kind: MatchKind
    public let score: Double
    public let label: String

    public init(kind: MatchKind, score: Double, label: String) {
        self.kind = kind
        self.score = score
        self.label = label
    }
}

/// Estimated route information for a transportation mode.
public struct RouteEstimate: Codable, Equatable {
    public let mode: RouteMode
    public let cost: Double
    public let durationMinutes: Double
    public let distanceKm: Double
    public let summary: String

    public init(mode: RouteMode, cost: Double, durationMinutes: Double, distanceKm: Double, summary: String) {
        self.mode = mode
        self.cost = cost
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.summary = summary
    }
}

/// A fully scored and ranked rental recommendation.
public struct Recommendation: Codable, Equatable, Identifiable {
    public var id: String { listing.id }

    public let listing: RentalListing
    public let match: VehicleMatch
    public let taxiRoute: RouteEstimate
    public let transitRoute: RouteEstimate
    public let rentalTotal: Double
    public let taxiTotal: Double
    public let transitTotal: Double
    public let bestTotal: Double
    public let bestRouteMode: RouteMode
    public let warnings: [ResultWarning]

    public init(
        listing: RentalListing,
        match: VehicleMatch,
        taxiRoute: RouteEstimate,
        transitRoute: RouteEstimate,
        rentalTotal: Double,
        taxiTotal: Double,
        transitTotal: Double,
        bestTotal: Double,
        bestRouteMode: RouteMode,
        warnings: [ResultWarning]
    ) {
        self.listing = listing
        self.match = match
        self.taxiRoute = taxiRoute
        self.transitRoute = transitRoute
        self.rentalTotal = rentalTotal
        self.taxiTotal = taxiTotal
        self.transitTotal = transitTotal
        self.bestTotal = bestTotal
        self.bestRouteMode = bestRouteMode
        self.warnings = warnings
    }
}
