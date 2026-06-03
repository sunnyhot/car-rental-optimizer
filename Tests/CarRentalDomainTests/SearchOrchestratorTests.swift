import XCTest
@testable import CarRentalDomain

// MARK: - Mock Map Service

/// Replicates the TypeScript mockMapService logic exactly.
struct MockMapService: MapService {
    func estimateRoutes(origin: GeoPoint, store: Store) async -> (taxi: RouteEstimate, transit: RouteEstimate) {
        let dist = store.distanceKm

        if dist >= 80 {
            let taxiMinutes = Double(Int(round(dist * 0.75)))
            let transitMinutes = Double(Int(round(dist * 0.35 + 15)))
            let transitCost = Double(Int(round(30 + dist * 0.24)))

            return (
                taxi: RouteEstimate(
                    mode: .taxi,
                    cost: Double(Int(round(90 + dist * 2.5))),
                    durationMinutes: taxiMinutes,
                    distanceKm: dist,
                    summary: "跨城打车约 \(Int(taxiMinutes)) 分钟"
                ),
                transit: RouteEstimate(
                    mode: .transit,
                    cost: transitCost,
                    durationMinutes: transitMinutes,
                    distanceKm: dist,
                    summary: "高铁+市内交通约 \(Int(transitMinutes)) 分钟"
                )
            )
        }

        let taxiMinutes = max(8, Double(Int(round(dist * 1.6 + 12))))
        let transitMinutes = max(15, Double(Int(round(dist * 2 + 24))))
        let transitCost = dist < 1 ? 2 : Double(Int(max(5, round(4 + dist * 0.16))))

        return (
            taxi: RouteEstimate(
                mode: .taxi,
                cost: Double(Int(max(12, round(14 + dist * 2.3)))),
                durationMinutes: taxiMinutes,
                distanceKm: dist,
                summary: "打车约 \(Int(taxiMinutes)) 分钟"
            ),
            transit: RouteEstimate(
                mode: .transit,
                cost: transitCost,
                durationMinutes: transitMinutes,
                distanceKm: dist,
                summary: "公交/地铁约 \(Int(transitMinutes)) 分钟"
            )
        )
    }
}

// MARK: - Mock Rental Adapters

struct MockEhiAdapter: RentalAdapter {
    let platform: PlatformId = .ehi

    func search(request: SearchRequest) async -> [RentalListing] {
        let rentalDays = calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)

        let listings: [RentalListing] = [
            RentalListing(
                id: "ehi-tongzhou-tiggo8",
                platform: .ehi,
                store: makeStore(id: "ehi-tongzhou", name: "北京通州万达店", city: "北京",
                                 address: "北京市通州区万达广场附近", lat: 39.909, lng: 116.657, dist: 6.8, hours: "08:00-22:00"),
                vehicleName: "奇瑞 瑞虎8 1.6T 自动",
                vehicleClass: "中型SUV",
                basePrice: dailyTotal(328, rentalDays),
                platformFees: 36,
                insuranceFees: 50,
                oneWayFee: request.returnMode == .differentStore ? 120 : 0,
                sourceUrl: "https://www.1hai.cn/",
                dataCompleteness: 0.98
            ),
            RentalListing(
                id: "ehi-dezhou-tiggo8",
                platform: .ehi,
                store: makeStore(id: "ehi-dezhou-east", name: "德州东站店", city: "德州",
                                 address: "德州市德州东站出站口附近", lat: 37.443, lng: 116.374, dist: 286, hours: "08:00-20:00"),
                vehicleName: "奇瑞 瑞虎8",
                vehicleClass: "中型SUV",
                basePrice: dailyTotal(120, rentalDays),
                platformFees: 25,
                insuranceFees: 40,
                oneWayFee: request.returnMode == .differentStore ? 180 : 0,
                sourceUrl: "https://www.1hai.cn/",
                dataCompleteness: 0.92,
                warnings: [.crossCityPickup]
            )
        ]

        return listings
            .map { withDynamicDistance(listing: $0, request: request) }
            .filter { $0.store.distanceKm <= request.radiusKm }
    }
}

struct MockCarIncAdapter: RentalAdapter {
    let platform: PlatformId = .carInc

    func search(request: SearchRequest) async -> [RentalListing] {
        let rentalDays = calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)

        let listings: [RentalListing] = [
            RentalListing(
                id: "car-south-haval-h6",
                platform: .carInc,
                store: makeStore(id: "car-beijing-south", name: "北京南站店", city: "北京",
                                 address: "北京市丰台区北京南站", lat: 39.865, lng: 116.379, dist: 32, hours: "07:30-22:30"),
                vehicleName: "哈弗 H6 自动",
                vehicleClass: "紧凑型SUV",
                basePrice: dailyTotal(268, rentalDays),
                platformFees: 42,
                insuranceFees: 55,
                oneWayFee: request.returnMode == .differentStore ? 150 : 0,
                sourceUrl: "https://www.zuche.com/",
                dataCompleteness: 0.95
            ),
            RentalListing(
                id: "car-tongzhou-lavida",
                platform: .carInc,
                store: makeStore(id: "car-tongzhou-compact", name: "北京通州北苑店", city: "北京",
                                 address: "北京市通州区北苑附近", lat: 39.903, lng: 116.642, dist: 4.2, hours: "08:00-21:00"),
                vehicleName: "大众 朗逸 自动",
                vehicleClass: "紧凑型轿车",
                basePrice: dailyTotal(98, rentalDays),
                platformFees: 30,
                insuranceFees: 45,
                oneWayFee: request.returnMode == .differentStore ? 100 : 0,
                sourceUrl: "https://www.zuche.com/",
                dataCompleteness: 0.94
            )
        ]

        return listings
            .map { withDynamicDistance(listing: $0, request: request) }
            .filter { $0.store.distanceKm <= request.radiusKm }
    }
}

// MARK: - Helper Functions

private func makeStore(id: String, name: String, city: String, address: String,
                        lat: Double, lng: Double, dist: Double, hours: String) -> Store {
    Store(id: id, platform: .ehi, name: name, city: city, address: address,
          location: GeoPoint(lat: lat, lng: lng), distanceKm: dist, hours: hours)
}

private func dailyTotal(_ dailyPrice: Int, _ rentalDays: Int) -> Double {
    Double(dailyPrice * rentalDays)
}

private func withDynamicDistance(listing: RentalListing, request: SearchRequest) -> RentalListing {
    let distanceKm = distanceKmBetween(from: request.origin, to: listing.store.location)
    var warnings = Set(listing.warnings)

    if distanceKm >= 80 {
        warnings.insert(.crossCityPickup)
    } else {
        warnings.remove(.crossCityPickup)
    }

    return RentalListing(
        id: listing.id,
        platform: listing.platform,
        store: Store(
            id: listing.store.id,
            platform: listing.store.platform,
            name: listing.store.name,
            city: listing.store.city,
            address: listing.store.address,
            location: listing.store.location,
            distanceKm: distanceKm,
            hours: listing.store.hours
        ),
        vehicleName: listing.vehicleName,
        vehicleClass: listing.vehicleClass,
        basePrice: listing.basePrice,
        platformFees: listing.platformFees,
        insuranceFees: listing.insuranceFees,
        oneWayFee: listing.oneWayFee,
        sourceUrl: listing.sourceUrl,
        dataCompleteness: listing.dataCompleteness,
        warnings: Array(warnings)
    )
}

// MARK: - Base Request Helper

private func makeBaseRequest(
    origin: GeoPoint = GeoPoint(lat: 39.9169, lng: 116.6462),
    originLabel: String = "北京通州",
    pickupAt: String = "2026-06-05T09:00",
    returnAt: String = "2026-06-07T18:00",
    returnMode: ReturnMode = .sameStore,
    radiusKm: Double = 100,
    vehicleQuery: String = "瑞虎8",
    platforms: [PlatformId] = [.ehi, .carInc]
) -> SearchRequest {
    SearchRequest(
        origin: origin,
        originLabel: originLabel,
        pickupAt: pickupAt,
        returnAt: returnAt,
        returnMode: returnMode,
        radiusKm: radiusKm,
        vehicleQuery: vehicleQuery,
        platforms: platforms
    )
}

// MARK: - Tests

final class SearchOrchestratorTests: XCTestCase {

    private let adapters: [RentalAdapter] = [MockEhiAdapter(), MockCarIncAdapter()]
    private let mapService = MockMapService()

    func testQueriesBothPlatformsAndRanksResults() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(vehicleQuery: "SUV"),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertTrue(results.count > 1)
        let platformSet = Set(results.map { $0.listing.platform })
        XCTAssertTrue(platformSet.contains(.ehi))
        XCTAssertTrue(platformSet.contains(.carInc))
        XCTAssertTrue(results[0].rentalTotal > 0)
        XCTAssertTrue(results[0].taxiTotal > results[0].rentalTotal)
        XCTAssertTrue(results[0].transitTotal > results[0].rentalTotal)
    }

    func testExcludesDezhouAt100kmRadius() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(radiusKm: 100),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertFalse(results.contains { $0.listing.store.name == "德州东站店" })
    }

    func testIncludesDezhouAt500kmAndRanksFirst() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(radiusKm: 500),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertTrue(results.contains { $0.listing.store.name == "德州东站店" })
        XCTAssertEqual(results[0].listing.store.name, "德州东站店")
        XCTAssertTrue(results[0].warnings.contains(.crossCityPickup))
    }

    func testRentalDurationAffectsPricing() async {
        let twoDayResults = await searchRentalOptions(
            request: makeBaseRequest(vehicleQuery: "SUV"),
            rentalAdapters: adapters,
            mapService: mapService
        )
        let thirtyDayResults = await searchRentalOptions(
            request: makeBaseRequest(pickupAt: "2026-09-11T09:00", returnAt: "2026-10-11T18:00", vehicleQuery: "SUV"),
            rentalAdapters: adapters,
            mapService: mapService
        )

        guard let twoDaySouth = twoDayResults.first(where: { $0.listing.store.name == "北京南站店" }),
              let thirtyDaySouth = thirtyDayResults.first(where: { $0.listing.store.name == "北京南站店" })
        else {
            XCTFail("Expected to find 北京南站店 in results")
            return
        }

        // 3 days (Jun 5 09:00 → Jun 7 18:00 = ~57h → ceil(57/24) = 3) × 268 = 804
        XCTAssertEqual(twoDaySouth.listing.basePrice, 804)
        // 31 days (Sep 11 09:00 → Oct 11 18:00 = ~30.375 days → ceil = 31) × 268 = 8308
        XCTAssertEqual(thirtyDaySouth.listing.basePrice, 8308)
        XCTAssertTrue(thirtyDaySouth.rentalTotal > twoDaySouth.rentalTotal)
    }

    func testExcludesUnrelatedVehicleClassesWhenQuerySpecified() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertFalse(results.contains { $0.listing.vehicleName.contains("朗逸") })
    }

    func testSpecificVehicleQueryExcludesSameClassAlternatives() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(vehicleQuery: "瑞虎8"),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertFalse(results.contains { $0.listing.vehicleName.contains("哈弗") })
        XCTAssertTrue(results.allSatisfy { $0.listing.vehicleName.contains("瑞虎8") })
    }

    func testGenericSuvQueryKeepsSuvAlternatives() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(vehicleQuery: "SUV"),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertTrue(results.contains { $0.listing.vehicleName.contains("哈弗") })
        XCTAssertTrue(results.contains { $0.listing.vehicleName.contains("瑞虎8") })
        XCTAssertFalse(results.contains { $0.listing.vehicleName.contains("朗逸") })
    }

    func testShowsAllClassesWhenQueryEmpty() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(vehicleQuery: ""),
            rentalAdapters: adapters,
            mapService: mapService
        )

        guard let sedan = results.first(where: { $0.listing.vehicleName.contains("朗逸") }) else {
            XCTFail("Expected 朗逸 to appear when vehicleQuery is empty")
            return
        }
        XCTAssertEqual(sedan.match.kind, .notSpecified)
    }

    func testOriginCoordinatesFilterStores() async {
        let results = await searchRentalOptions(
            request: makeBaseRequest(
                origin: GeoPoint(lat: 37.443, lng: 116.374),
                originLabel: "德州东站",
                radiusKm: 100
            ),
            rentalAdapters: adapters,
            mapService: mapService
        )

        XCTAssertEqual(results.map { $0.listing.store.name }, ["德州东站店"])
        XCTAssertTrue(results[0].taxiRoute.distanceKm < 1)
    }

    func testRankParsedLiveListings() async {
        let liveListing = RentalListing(
            id: "live-ehi-1",
            platform: .ehi,
            store: Store(
                id: "live-store",
                platform: .ehi,
                name: "德州东站店",
                city: "德州",
                address: "德州东站店",
                location: GeoPoint(lat: 37.443, lng: 116.374),
                distanceKm: 286,
                hours: "以平台页面为准"
            ),
            vehicleName: "奇瑞 瑞虎8 1.6T 自动",
            vehicleClass: "中型SUV",
            basePrice: 268,
            platformFees: 0,
            insuranceFees: 0,
            oneWayFee: 0,
            sourceUrl: "https://booking.1hai.cn/",
            dataCompleteness: 0.72,
            warnings: [.partialPrice]
        )

        let results = await rankRentalListings(
            request: makeBaseRequest(),
            listings: [liveListing],
            mapService: mapService
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].listing.sourceUrl, "https://booking.1hai.cn/")
        XCTAssertEqual(results[0].match.kind, .exact)
    }
}
