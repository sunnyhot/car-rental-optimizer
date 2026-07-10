import CarRentalDomain
import Foundation
@testable import CarRentalOptimizer

func makeComparisonRecommendation(
    id: String,
    platform: PlatformId = .ehi,
    vehicleName: String,
    rentalTotal: Double,
    bestTotal: Double,
    distanceKm: Double,
    dataCompleteness: Double = 0.98,
    warnings: [ResultWarning] = []
) -> Recommendation {
    let store = Store(
        id: "store-\(id)",
        platform: platform,
        name: "\(vehicleName)门店",
        city: "北京",
        address: "北京市测试路\(id)号",
        location: GeoPoint(lat: 39.9, lng: 116.4),
        distanceKm: distanceKm,
        hours: "08:00-20:00"
    )
    let listing = RentalListing(
        id: id,
        platform: platform,
        store: store,
        vehicleName: vehicleName,
        vehicleClass: "SUV 5座",
        basePrice: rentalTotal,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://example.com/\(id)",
        dataCompleteness: dataCompleteness,
        warnings: warnings
    )
    let taxi = RouteEstimate(mode: .taxi, cost: bestTotal - rentalTotal, durationMinutes: 15, distanceKm: distanceKm, summary: "打车")
    let transit = RouteEstimate(mode: .transit, cost: 6, durationMinutes: 25, distanceKm: distanceKm, summary: "地铁")
    return Recommendation(
        listing: listing,
        match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
        taxiRoute: taxi,
        transitRoute: transit,
        rentalTotal: rentalTotal,
        taxiTotal: bestTotal,
        transitTotal: rentalTotal + 6,
        bestTotal: bestTotal,
        bestRouteMode: .taxi,
        warnings: warnings
    )
}

final class StubComparisonInsightService: VehicleInsightProviding {
    var returnedOrigin: VehicleInsightOrigin = .network
    var delayNanoseconds: UInt64 = 0

    func localInsight(for listing: RentalListing) -> VehicleInsight {
        VehicleInsightLocalInferencer.localInsight(for: listing)
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        var insight = localInsight(for: listing)
        insight.origin = returnedOrigin
        insight.sourceName = returnedOrigin == .network ? "测试车型库" : "本地推断"
        return insight
    }
}
