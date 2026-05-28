import XCTest
@testable import CarRentalDomain

final class RecommendationTests: XCTestCase {

    // MARK: - Test Fixtures

    private var baseListing: RentalListing {
        RentalListing(
            id: "listing-1",
            platform: .ehi,
            store: Store(
                id: "store-1",
                platform: .ehi,
                name: "北京通州万达店",
                city: "北京",
                address: "通州区",
                location: GeoPoint(lat: 39.9, lng: 116.65),
                distanceKm: 8,
                hours: "08:00-22:00"
            ),
            vehicleName: "奇瑞 瑞虎8",
            vehicleClass: "中型SUV",
            basePrice: 320,
            platformFees: 35,
            insuranceFees: 50,
            oneWayFee: 0,
            sourceUrl: "https://www.1hai.cn/",
            dataCompleteness: 0.98
        )
    }

    private var exactMatch: VehicleMatch {
        VehicleMatch(kind: .exact, score: 1, label: "精确车型")
    }

    private var taxiRoute: RouteEstimate {
        RouteEstimate(mode: .taxi, cost: 42, durationMinutes: 25, distanceKm: 8, summary: "打车约 25 分钟")
    }

    private var transitRoute: RouteEstimate {
        RouteEstimate(mode: .transit, cost: 6, durationMinutes: 45, distanceKm: 8, summary: "地铁+步行约 45 分钟")
    }

    // MARK: - buildRecommendation

    func testBuildRecommendationCalculatesTotals() {
        let rec = buildRecommendation(
            listing: baseListing,
            match: exactMatch,
            taxiRoute: taxiRoute,
            transitRoute: transitRoute
        )

        // rentalTotal = 320 + 35 + 50 + 0 = 405
        XCTAssertEqual(rec.rentalTotal, 405)
        // taxiTotal = 405 + 42 = 447
        XCTAssertEqual(rec.taxiTotal, 447)
        // transitTotal = 405 + 6 = 411
        XCTAssertEqual(rec.transitTotal, 411)
        // transit is cheaper → bestTotal = 411
        XCTAssertEqual(rec.bestTotal, 411)
        XCTAssertEqual(rec.bestRouteMode, .transit)
    }

    // MARK: - rankRecommendations: Cross-city low rental wins

    func testCrossCityLowRentalWinsByTotalCost() {
        let local = buildRecommendation(
            listing: baseListing,
            match: exactMatch,
            taxiRoute: taxiRoute,
            transitRoute: transitRoute
        )

        let dezhouListing = RentalListing(
            id: "listing-dezhou",
            platform: .ehi,
            store: Store(
                id: "store-dezhou",
                platform: .ehi,
                name: "德州东站店",
                city: "德州",
                address: "德州",
                location: GeoPoint(lat: 37.443, lng: 116.374),
                distanceKm: 285,
                hours: "08:00-20:00"
            ),
            vehicleName: "奇瑞 瑞虎8",
            vehicleClass: "中型SUV",
            basePrice: 120,
            platformFees: 25,
            insuranceFees: 40,
            oneWayFee: 0,
            sourceUrl: "https://www.1hai.cn/",
            dataCompleteness: 0.92,
            warnings: [.crossCityPickup]
        )

        let dezhou = buildRecommendation(
            listing: dezhouListing,
            match: exactMatch,
            taxiRoute: RouteEstimate(mode: .taxi, cost: 620, durationMinutes: 210, distanceKm: 285, summary: "跨城打车约 210 分钟"),
            transitRoute: RouteEstimate(mode: .transit, cost: 98, durationMinutes: 115, distanceKm: 285, summary: "高铁+市内交通约 115 分钟")
        )

        let ranked = rankRecommendations([local, dezhou])

        XCTAssertEqual(ranked[0].listing.store.name, "德州东站店")
        // dezhou rentalTotal = 120+25+40+0 = 185, transitTotal = 185+98 = 283
        XCTAssertEqual(ranked[0].bestTotal, 283)
        XCTAssertTrue(ranked[0].warnings.contains(.crossCityPickup))
    }

    // MARK: - rankRecommendations: Tie-break by match kind

    func testExactMatchTieBreakerAfterTotalCost() {
        let similarMatch = VehicleMatch(kind: .similarClass, score: 0.72, label: "同级 SUV")

        let exact = buildRecommendation(
            listing: baseListing,
            match: exactMatch,
            taxiRoute: taxiRoute,
            transitRoute: transitRoute
        )

        let similarListing = RentalListing(
            id: "listing-similar",
            platform: .ehi,
            store: baseListing.store,
            vehicleName: "哈弗 H6",
            vehicleClass: "紧凑型SUV",
            basePrice: 320,
            platformFees: 35,
            insuranceFees: 50,
            oneWayFee: 0,
            sourceUrl: "https://www.1hai.cn/",
            dataCompleteness: 1.0
        )
        let similar = buildRecommendation(
            listing: similarListing,
            match: similarMatch,
            taxiRoute: taxiRoute,
            transitRoute: transitRoute
        )

        let ranked = rankRecommendations([similar, exact])
        XCTAssertEqual(ranked[0].match.kind, .exact)
    }
}
