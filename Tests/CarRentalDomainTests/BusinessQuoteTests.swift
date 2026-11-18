import XCTest
@testable import CarRentalDomain

final class BusinessQuoteTests: XCTestCase {
    func testCompleteQuotePrecedesCheaperUnknownFees() {
        let partial = quote("partial", price: 100, warnings: [.partialPrice])
        let complete = quote("complete", price: 200)
        XCTAssertEqual(rankRecommendations([partial, complete]).first?.id, "complete")
    }

    func testMonitorNeverSwitchesStoreOrVehicle() {
        let original = quote("original", price: 200)
        let otherStore = quote("other", price: 100)
        XCTAssertNil(selectMonitoredRecommendation(from: [otherStore], signature: ListingSignature(recommendation: original), targetVehicleQuery: "瑞虎8", targetPlatform: .ehi))
        XCTAssertNil(selectMonitoredRecommendation(from: [original], signature: nil, targetVehicleQuery: "不存在", targetPlatform: nil))
    }

    func testMinutePrecisionRentalDuration() {
        XCTAssertEqual(calculateRentalDays(pickupAt: "2027-09-01 10:30", returnAt: "2027-09-02 10:31"), 2)
    }

    private func quote(_ id: String, price: Double, warnings: [ResultWarning] = []) -> Recommendation {
        let store = Store(id: id, platform: .ehi, name: id, city: "北京", address: "北京", location: GeoPoint(lat: 40, lng: 116), distanceKm: 2, hours: "08:00-22:00")
        let listing = RentalListing(id: id, platform: .ehi, store: store, vehicleName: "瑞虎8", vehicleClass: "SUV", basePrice: price, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://example.com", dataCompleteness: 1, warnings: warnings)
        let route = RouteEstimate(mode: .taxi, cost: 10, durationMinutes: 10, distanceKm: 2, summary: "估算")
        return buildRecommendation(listing: listing, match: matchVehicle(query: "瑞虎8", vehicleName: "瑞虎8", vehicleClass: "SUV"), taxiRoute: route, transitRoute: route)
    }
}
