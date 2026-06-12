import XCTest
@testable import CarRentalDomain

final class PriceMonitorMatchingTests: XCTestCase {
    func testExactSignatureMatchWins() {
        let original = recommendation(id: "original", platform: .ehi, storeID: "store-a", storeName: "一嗨通州万达店", vehicleName: "奇瑞 瑞虎8")
        let other = recommendation(id: "other", platform: .carInc, storeID: "store-b", storeName: "神州通州店", vehicleName: "奇瑞 瑞虎8")
        let signature = ListingSignature(recommendation: original)

        let selected = selectMonitoredRecommendation(from: [other, original], signature: signature, targetVehicleQuery: "瑞虎8", targetPlatform: .ehi)

        XCTAssertEqual(selected?.id, "original")
    }

    func testFallsBackToSamePlatformVehicleWhenStoreChanges() {
        let oldStore = recommendation(id: "old", platform: .ehi, storeID: "store-a", storeName: "一嗨通州万达店", vehicleName: "奇瑞 瑞虎8")
        let newStore = recommendation(id: "new", platform: .ehi, storeID: "store-c", storeName: "一嗨北苑店", vehicleName: "奇瑞瑞虎8")
        let crossPlatform = recommendation(id: "cross", platform: .carInc, storeID: "store-d", storeName: "神州门店", vehicleName: "奇瑞 瑞虎8")

        let selected = selectMonitoredRecommendation(from: [crossPlatform, newStore], signature: ListingSignature(recommendation: oldStore), targetVehicleQuery: "瑞虎8", targetPlatform: .ehi)

        XCTAssertEqual(selected?.id, "new")
    }

    func testFallsBackAcrossPlatformsForSameVehicle() {
        let original = recommendation(id: "original", platform: .ehi, storeID: "store-a", storeName: "一嗨通州万达店", vehicleName: "奇瑞 瑞虎8")
        let crossPlatform = recommendation(id: "cross", platform: .carInc, storeID: "store-d", storeName: "神州门店", vehicleName: "奇瑞 瑞虎8")

        let selected = selectMonitoredRecommendation(from: [crossPlatform], signature: ListingSignature(recommendation: original), targetVehicleQuery: "瑞虎8", targetPlatform: .ehi)

        XCTAssertEqual(selected?.id, "cross")
    }

    func testManualMonitorUsesRankedRecommendationForTargetQuery() {
        let tiger = recommendation(id: "tiger", platform: .ehi, storeID: "store-a", storeName: "一嗨店", vehicleName: "奇瑞 瑞虎8")
        let h6 = recommendation(id: "h6", platform: .ehi, storeID: "store-b", storeName: "一嗨店", vehicleName: "哈弗 H6")

        let selected = selectMonitoredRecommendation(from: [h6, tiger], signature: nil, targetVehicleQuery: "瑞虎8", targetPlatform: nil)

        XCTAssertEqual(selected?.id, "tiger")
    }

    private func recommendation(
        id: String,
        platform: PlatformId,
        storeID: String,
        storeName: String,
        vehicleName: String
    ) -> Recommendation {
        let store = Store(
            id: storeID,
            platform: platform,
            name: storeName,
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 5,
            hours: "08:00-22:00"
        )
        let listing = RentalListing(
            id: id,
            platform: platform,
            store: store,
            vehicleName: vehicleName,
            vehicleClass: "SUV",
            basePrice: 300,
            platformFees: 0,
            insuranceFees: 0,
            oneWayFee: 0,
            sourceUrl: "https://example.com",
            dataCompleteness: 0.9
        )
        return buildRecommendation(
            listing: listing,
            match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
            taxiRoute: RouteEstimate(mode: .taxi, cost: 40, durationMinutes: 20, distanceKm: 5, summary: "打车"),
            transitRoute: RouteEstimate(mode: .transit, cost: 6, durationMinutes: 40, distanceKm: 5, summary: "公交")
        )
    }
}
